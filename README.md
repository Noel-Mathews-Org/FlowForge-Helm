# FlowForge Helm & Kubernetes Infrastructure Repository

This repository contains the configuration, templates, and manifests required to deploy and monitor the **FlowForge** microservices application onto Kubernetes (specifically targeting Azure Kubernetes Service, or AKS). It supports GitOps-driven deployment using ArgoCD for both dev and prod environments.

---

## Repository Structure

```text
FlowForge-Helm/
├── Helm/                   # Main Helm chart templates and value files
├── argocd/                 # ArgoCD Application manifests for Dev and Prod
├── infra/                  # Third-party cluster infrastructure and monitoring utilities
└── k8s/                    # Static Kubernetes manifests for bootstrapping/reference
```

---

## 1. Helm Folder (`/Helm`)
This folder contains a parameterized Helm chart used to package and deploy FlowForge as a unified application. It supports deploying to multiple namespaces (`flowforge-dev` and `flowforge-prod`) using environment-specific values.

### Files & Layout:
* **`Chart.yaml`**: Standard Helm chart metadata defining the chart name, version, and apiVersion.
* **`values-common.yaml`**: Shared global parameters such as the default AI deployment name (`summary-agent`) and common storage containers.
* **`values-dev.yaml` / `values-prod.yaml`**: Environment-specific configurations containing database connection settings, domain addresses, Managed Identity client IDs, and microservice image tags.
* **`charts/`**: Subcharts separating each service component:
  * `frontend` (recently migrated from Argo Rollouts to standard Deployment)
  * `gateway` (API Gateway routing)
  * `auth-service` (identity & authentication)
  * `project-service` (project resources management)
  * `task-service` (background tasks scheduler)
  * `analysis-service` (AI analysis backend)
  * `notification-worker` (emails and event processor)
* **`templates/`**: Shared global cluster resources:
  * **`ingress.yaml`**: The central application Ingress. Configured with the class `azure-application-gateway` to use Azure Application Gateway. Sets up TLS bindings (`flowforge-tls`) for the application domain (e.g., `dev.flowforge.fun` or `flowforge.fun`) and routes `/api/*` to the gateway service and `/` traffic to the frontend service.
  * **`network-policy.yaml`**: A namespace-wide egress/ingress firewall. It blocks unexpected external network traffic while allowing:
    * Inter-pod communication in the namespace.
    * Ingress requests from monitoring tools, cert-manager, ArgoCD, and Actions Runner Controller.
    * Egress to `kube-system` DNS (port 53), Azure IMDS token metadata endpoint (`169.254.169.254`), SMTP (587), PostgreSQL (5432), and Redis (10000).
  * **`global-config.yaml`**: Generates a unified `flowforge-config` ConfigMap containing environment variables referenced by the microservices (e.g. backend API URLs, tenant IDs, keyvault connections, and DB connection hosts).

---

## 2. ArgoCD Folder (`/argocd`)
Contains GitOps specifications for continuous deployment using ArgoCD.

* **`argocd-dev-app.yaml`**: Provisions an ArgoCD Application targeting the `flowforge-dev` namespace. It syncs from the `Cloud-Track-dev` branch of this repository and loads `values-common.yaml` and `values-dev.yaml`.
* **`argocd-prod-app.yaml`**: Provisions an ArgoCD Application targeting the `flowforge-prod` namespace. It syncs from the `main` branch and loads `values-common.yaml` and `values-prod.yaml`.

---

## 3. Kubernetes Folder (`/k8s`)
This directory contains static, hardcoded Kubernetes manifests. Originally created for initial bootstrapping and manual verification before transitioning to Helm-based packaging, these manifests are kept organized for developer reference.

* **`/common`**: Global prerequisites like the `default` namespace, secrets, central ingress routes, network policies, and config maps.
* **Service Folders (`/frontend`, `/gateway`, `/auth-service`, etc.)**: Each service has its own folder containing modular, single-resource manifests:
  * `deployment.yaml`: Configures the rolling update deployment strategy (with 50% max surge/max unavailable parameters).
  * `service.yaml`: Internal cluster IPs and port mappings.
  * `hpa.yaml`: Horizontal Pod Autoscalers configured to scale based on CPU utilization.
  * `serviceaccount.yaml`: Workload identities that authenticate pods to Azure services using OIDC federated credentials.

---

## 4. Infrastructure Folder (`/infra`)
Houses auxiliary files to set up core cluster services, automation, telemetry, and monitoring:

* **Actions Runner Controller (ARC) Setup (`arc-sa.yaml`, `arc-values.yaml`, `runner.yaml`)**:
  * Configures self-hosted GitHub Actions runners inside the cluster in the `arc-system` namespace.
  * `runner.yaml` defines a `RunnerDeployment` for `terraform-runner` to securely update secrets in the Azure Key Vault for `Noel-Mathews-Org/FlowForge-Terraform` workflows using Workload Identity.
* **ArgoCD Chart Values (`argo-values.yaml`)**:
  * Values used to customize the ArgoCD installation, binding an Ingress controller on `argocd.flowforge.fun` and forcing control-plane services onto system node pools.
* **Cert-Manager SSL Issuer (`issuer.yaml`)**:
  * Registers a `letsencrypt-prod` ClusterIssuer to automatically request and renew SSL/TLS certificates via ACME HTTP-01 validation.
* **OpenTelemetry Collection (`otel-dev.yaml`, `otel-prod.yaml`)**:
  * Launches an OpenTelemetry Collector daemon inside the application namespaces.
  * Collects trace context, metrics, and logs from microservices and securely exports them to Azure Monitor (Application Insights) via a managed identity backend.
* **Monitoring & Alerts (`prom-values.yaml`)**:
  * Supplies value configurations for the Prometheus-Community stack (Prometheus, Grafana, Alertmanager).
  * Enables external routing at `prometheus.flowforge.fun` and `grafana.flowforge.fun`.
  * Registers custom alerting rules for application anomalies (e.g. `PodCrashLoopingCustom`, `PodPendingCustom`, and high ingress error rates).
  * Integrates Alertmanager email alerts (routing critical severity emails to admins) and Slack hook notifications.

---

## 5. Security & Branch Protection

To guarantee infrastructure reliability and maintain strict controls over production deployments, the following safety guidelines are enforced:

* **Pull Request Requirement**: Direct pushes to the `main` branch are blocked. All changes must be proposed via a Pull Request (PR) from a feature or development branch (e.g. `Cloud-Track-dev`).
* **Admin Review**: At least one administrator approval is required on pull requests before changes can be merged into `main`.
* **GitOps Execution**: Merges to `main` automatically trigger production synchronization via ArgoCD (`argocd-prod-app`), ensuring that only reviewed, authorized commits modify production resources.
