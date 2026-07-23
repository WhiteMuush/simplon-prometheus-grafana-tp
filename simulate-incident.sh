#!/bin/bash
# Simule un incident sur l'App Service pour tester les alertes :
# - Http5xx (Application Insights, scheduled-query)
# - log_erreurs_total (Prometheus managé)
#
# Usage : ./simulate-incident.sh [nom-app-service]
set -e

APP="${1:-app-monitoring-groupe1}"
URL="https://${APP}.azurewebsites.net"

echo "Cible : $URL"

echo "→ 20 requêtes sur /error..."
for i in $(seq 1 20); do curl -s "$URL/error" > /dev/null; done

echo "→ 10 requêtes sur /crash..."
for i in $(seq 1 10); do curl -s "$URL/crash" > /dev/null; done

echo "→ Vérification du compteur log_erreurs_total :"
curl -s "$URL/metrics" | grep log_erreurs_total

echo "Terminé. Vérifie Prometheus Explorer et Application Insights → Failures dans le portail."
