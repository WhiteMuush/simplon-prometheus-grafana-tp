import time
import logging
import os
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import Counter

# Instrumentation Application Insights — MANQUAIT jusqu'ici : APPLICATIONINSIGHTS_CONNECTION_STRING
# était bien injectée par Terraform (app-service.tf) mais jamais consommée par le code, donc
# aucune télémétrie n'a jamais été envoyée et les tables (traces, requests...) n'existent même
# pas encore dans le Log Analytics Workspace (erreur KQL "Failed to resolve table" dans Grafana).
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.flask import FlaskInstrumentor

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
if connection_string:
    configure_azure_monitor(connection_string=connection_string)
    FlaskInstrumentor().instrument_app(app)
else:
    app.logger.warning(
        "APPLICATIONINSIGHTS_CONNECTION_STRING absente — télémétrie Application Insights désactivée"
    )

# Expose /metrics + les métriques HTTP automatiques (requêtes, latence, code retour
# par route) — scrapé par la VM Prometheus définie dans observability-prometheus.tf.
metrics = PrometheusMetrics(app)

# Métrique custom surveillée par l'alerte Prometheus (log_erreurs_total > 5,
# cf. azurerm_monitor_alert_prometheus_rule_group.alerte_erreurs). Alimentée par un
# handler de logging plutôt qu'en incrémentant dans chaque route à la main, pour
# rester correcte même si une erreur remonte ailleurs dans le code plus tard.
log_erreurs_total = Counter(
    "log_erreurs_total",
    "Nombre de logs ERROR ou plus critiques emis par l'application",
)


class CompteurErreursHandler(logging.Handler):
    def emit(self, record):
        if record.levelno >= logging.ERROR:
            log_erreurs_total.inc()


app.logger.addHandler(CompteurErreursHandler())


@app.route("/")
def index():
    app.logger.info("Page d'accueil consultée")
    return jsonify({"message": "Hello from App Service 🚀", "owner": os.getenv("OWNER", "unknown")})


@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/error")
def error():
    app.logger.error("Erreur 500 déclenchée intentionnellement")
    return jsonify({"error": "Something went wrong"}), 500


@app.route("/slow")
def slow():
    app.logger.warning("Requête lente déclenchée (3s)")
    time.sleep(3)
    return jsonify({"message": "Réponse lente", "delay_seconds": 3}), 200


@app.route("/crash")
def crash():
    app.logger.critical("CRASH simulé")
    raise RuntimeError("Simulation de crash applicatif")


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    app.run(host="0.0.0.0", port=port)
