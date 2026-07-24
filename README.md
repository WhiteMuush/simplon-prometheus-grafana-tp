<div align="center">

<h1>
  <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/prometheus/prometheus-original.svg" height="30" alt="Prometheus"/>
  &nbsp;Extended Monitoring &amp; Observability on Azure&nbsp;
  <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/grafana/grafana-original.svg" height="30" alt="Grafana"/>
</h1>

![Azure](https://img.shields.io/badge/Azure-francecentral-0078D4?logo=microsoftazure&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.9-7B42BC?logo=terraform&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-3.12_managed-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Azure_Managed-F46800?logo=grafana&logoColor=white)
![App Insights](https://img.shields.io/badge/Application_Insights-OpenTelemetry-0078D4?logo=microsoftazure&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)

</div>

Two complementary monitoring signals for the same Flask API, combined in a single Grafana dashboard: HTTP traces through Application Insights, and custom business metrics through Azure Monitor managed service for Prometheus. Everything is provisioned with Terraform, nothing is self-hosted except the small VM that relays Prometheus metrics.

> This is my work write-up. The full assignment lives in [`docs/CONSIGNES.md`](docs/CONSIGNES.md).

## What this deploys

| Component | Azure resource | Purpose |
|---|---|---|
| App | Linux Web App (Python 3.11, Oryx build, no Docker) | Hosts the log-analyser Flask API |
| Traces | Application Insights + Log Analytics Workspace | HTTP telemetry, queried in KQL |
| Metrics store | Azure Monitor Workspace | Managed Prometheus storage, queried in PromQL |
| Metrics relay | Linux VM running Prometheus 3.12 | Scrapes `/metrics`, pushes via `remote_write` |
| Dashboard | Azure Managed Grafana | One dashboard, both data sources |
| Alerting | Prometheus rule group + scheduled query rule + Action Group | Business alert and technical alert, email delivery |

The app carries a dual instrumentation: `azure-monitor-opentelemetry` sends traces to Application Insights, while `prometheus-flask-exporter` exposes `/metrics` for Prometheus to scrape.

### App routes

| Route | Behaviour | What it exercises |
|---|---|---|
| `/` | 200, returns a greeting | Baseline traffic |
| `/health` | 200, `{"status": "ok"}` | Liveness check |
| `/error` | 500, logs at `ERROR` | Feeds `log_erreurs_total` and Application Insights failures |
| `/slow` | 200 after 3 s | Response-time panel |
| `/crash` | Raises, logs at `CRITICAL` | Unhandled exception path |

`log_erreurs_total` is a Prometheus `Counter` incremented by a `logging.Handler` attached to the Flask logger, so any log record at `ERROR` or above is counted wherever it is emitted, rather than counting by hand inside each route.

## Architecture

```mermaid
flowchart LR
    APP(["🐍 App Service<br/><b>log-analyser</b> · Flask"])

    subgraph METRICS ["📊 Metrics signal — PromQL"]
        direction TB
        VM["Prometheus VM<br/><i>dedicated subnet</i>"]
        AMW["Azure Monitor<br/>Workspace"]
        VM -- "remote_write" --> AMW
    end

    subgraph TRACES ["🔎 Traces signal — KQL"]
        direction TB
        APPI["Application<br/>Insights"]
        LAW["Log Analytics<br/>Workspace"]
        APPI -- "stores" --> LAW
    end

    GRAF{{"📈 Azure Managed Grafana<br/><b>one dashboard, both sources</b>"}}
    AG["🔔 Action Group"]
    USER(["📧 You"])

    APP -- "scrape /metrics" --> VM
    APP -- "OpenTelemetry" --> APPI

    AMW -- "PromQL" --> GRAF
    LAW -- "KQL" --> GRAF

    AMW -. "rule group<br/>(business alert)" .-> AG
    APPI -. "scheduled query<br/>(technical alert)" .-> AG
    AG -- "email" --> USER

    classDef source fill:#3776AB,stroke:#1b4a6b,color:#fff
    classDef metric fill:#E6522C,stroke:#8f2f15,color:#fff
    classDef trace fill:#0078D4,stroke:#004a85,color:#fff
    classDef viz fill:#F46800,stroke:#9c4200,color:#fff
    classDef alert fill:#B71C1C,stroke:#7a1010,color:#fff

    class APP source
    class VM,AMW metric
    class APPI,LAW trace
    class GRAF viz
    class AG,USER alert
```

The Prometheus VM is the only piece introducing classic networking (VNet, dedicated subnet, NSG, public IP) into an otherwise fully managed stack. On AKS that layer disappears: the managed Prometheus addon handles scraping and ingestion inside the cluster.

## Tech stack

- **Terraform** `>= 1.9`, provider `azurerm ~> 4.0`, `azurerm` remote backend with one state key per team
- **Azure** managed services: App Service, Application Insights, Azure Monitor Workspace, Azure Managed Grafana
- **Prometheus** 3.12.0 on Ubuntu 22.04, authenticated to Azure with a system-assigned managed identity (3.50+ is required for an empty `client_id`)
- **Python** 3.11, Flask, `azure-monitor-opentelemetry`, `prometheus-flask-exporter`
- **Auth**: managed identity end to end, no secret in the Prometheus config

## Repository layout

```
terraform/                 # one root module, one file per concern
├── backend.tf             # azurerm remote state, one key per team
├── providers.tf           # azurerm ~> 4.0
├── variables.tf           # resource group, owner suffix, alert email, tags
├── example.tfvars         # template to copy to terraform.tfvars, which stays out of git
├── data.tf                # resource group + client_config lookups
├── locals.tf              # name suffix and common tags
├── network.tf             # VNet, subnet, NSG, public IP, NIC
├── app_service.tf         # service plan + Linux Web App
├── monitoring.tf          # Log Analytics + App Insights + Monitor Workspace
├── prometheus_vm.tf       # Prometheus VM
├── role_assignments.tf    # RBAC for the VM identity
├── grafana.tf             # Managed Grafana + its role assignments
├── alerts.tf              # Action Group + business and technical alerts
└── outputs.tf             # app URL, Grafana endpoint, DCE and DCR ids
app/
├── app.py                 # Flask API, instrumented for App Insights + Prometheus
└── requirements.txt
scripts/                   # shell helpers, one per Makefile target
function/                  # HTTP-triggered Function App, kept from the previous lab
prometheus/
└── prometheus.yml         # scrape config + remote_write to the Azure Monitor Workspace
docs/
└── CONSIGNES.md           # full assignment
captures/                  # Grafana dashboard and triggered alerts
Makefile                   # deploy, connect, status and stress-test shortcuts
simulate-incident.sh       # fires errors at the app to trigger both alerts
```

The Terraform code is a single flat root module split by domain, one file per
concern. No sub-modules: the stack is a single environment deployed once, so
plain files keep resource references direct and the graph readable, which is
the idiomatic layout at this size.

## Dashboard panels

| Panel | Data source | Query |
|---|---|---|
| Requests per minute | Azure Monitor Logs (KQL) | `requests \| summarize count() by bin(timestamp, 1m)` |
| Failure rate (%) | Azure Monitor Logs (KQL) | `requests \| summarize total=count(), failed=countif(success==false) by bin(timestamp,5m)` |
| Log error count | Azure Monitor Workspace (PromQL) | `log_erreurs_total` |
| App availability | Azure Monitor Workspace (PromQL) | `up{job="log-analyser-app"}` |

## Run it

Nothing in this repo carries a real address, IP or subscription id: they are
either variables without a default, or `__PLACEHOLDER__` markers you substitute
at deploy time. Start by filling in your own values.

```bash
cd terraform
cp example.tfvars terraform.tfvars   # gitignored, put your email and public IP there
terraform init                       # see backend.tf before running this
terraform plan
terraform apply
```

`alert_email` and `allowed_source_ip` have no default, so a missing
`terraform.tfvars` fails at plan time rather than silently deploying someone
else's values.

Then deploy the application code and check both signals:

```bash
cd app
az webapp up --name app-monitoring-mpetit --resource-group mpetitRG --runtime "PYTHON:3.11"

curl https://app-monitoring-mpetit.azurewebsites.net/health
curl https://app-monitoring-mpetit.azurewebsites.net/metrics
```

Prometheus data lands in the Azure Monitor Workspace a few minutes after the VM starts. Check it in the portal under **Prometheus Explorer** with the query `log_erreurs_total`.

### Make shortcuts

A `Makefile` wraps the common steps, each target delegating to a script in
`scripts/`. Endpoints (VM IP, Grafana URL, app URL) are read from the Terraform
outputs, nothing is hard-coded.

```bash
make                  # list every target (default)
make deploy-terraform # terraform init/fmt/validate/plan/apply, then push the app code
make deploy-app       # push the Flask code only (az webapp up)
make status           # deployed resource count and endpoints
make prometheus-connect  # SSH into the Prometheus VM
make grafana-open     # print the Grafana URL
make stress-test      # fire errors at the app to trigger both alerts
make destroy-terraform   # destroy the resources (the tfstate blob is kept)
```

### Substituting the placeholders

`prometheus/prometheus.yml` and `grafana/dashboard-monitoring-etendu.json` ship
with markers instead of the ingestion path and the subscription id. Replace them
before deploying the config and before importing the dashboard:

```bash
# Prometheus remote_write, on the VM
DCE_HOST=$(az monitor data-collection endpoint show --ids "$(terraform -chdir=terraform output -raw dce_id)" --query metricsIngestion.endpoint -o tsv)
DCR_IMM=$(az monitor data-collection rule show --ids "$(terraform -chdir=terraform output -raw dcr_id)" --query immutableId -o tsv)
sed -e "s|__DCE_METRICS_INGESTION_ENDPOINT__|$DCE_HOST|" \
    -e "s|__DCR_IMMUTABLE_ID__|$DCR_IMM|" prometheus/prometheus.yml > /tmp/prometheus.yml

# Grafana dashboard, before importing it
sed "s|__SUBSCRIPTION_ID__|$(az account show --query id -o tsv)|g" \
    grafana/dashboard-monitoring-etendu.json > /tmp/dashboard.json
```

## Trigger the alerts

```bash
make stress-test                           # reads the app URL from the Terraform outputs
# or, targeting an app by name directly:
./simulate-incident.sh                     # defaults to app-monitoring-mpetit
./simulate-incident.sh autre-app-service   # or target another app
```

It fires 20 requests at `/error` and 10 at `/crash`, then prints the `log_erreurs_total` counter straight from `/metrics`. Both alerts should follow: the Prometheus rule group on the business metric, and the scheduled query rule on Application Insights failures.

The counter only moves once the Flask code is actually deployed. If `/metrics` returns a 404, the App Service is still serving the default page: run `make deploy-app` first.

## Gotchas worth knowing

- Role assignments take **up to 30 minutes** to propagate. A `403` in the Prometheus logs right after `terraform apply` is usually just propagation delay.
- `Monitoring Metrics Publisher` alone is not enough. Reading the auto-created Data Collection Endpoint and Rule also requires `Monitoring Reader`, otherwise the `az monitor data-collection ... show` calls fail with `AuthorizationFailed`.
- Never set a manual startup command on the App Service. It breaks Azure's Flask autodetection and produces `ModuleNotFoundError: No module named 'app'`.
- Prometheus 2.x rejects an empty `client_id` with a system-assigned identity. Use 3.50 or later.
- `log_erreurs_total` is a Counter, so it only ever grows. The assignment's `log_erreurs_total > 5` would fire once and never clear until the App Service restarts. The rule group uses `increase(log_erreurs_total[5m]) > 5` instead, which resolves on its own once errors stop.

## Outputs

- `app_service_url`: the Flask API HTTPS URL
- `grafana_endpoint`: the Azure Managed Grafana URL
- `dce_id`, `dcr_id`: ids needed to build the `remote_write` URL

## Cleanup

```bash
cd terraform
terraform destroy
# The resource group itself is kept, it is pre-created by the instructor
```

---

*DevSecOps Azure training, Simplon.*
