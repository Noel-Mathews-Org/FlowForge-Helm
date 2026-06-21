#!/bin/bash
set -e

echo "?? Starting Kubernetes Infrastructure Bootstrapping..."

echo "?? 1. Installing ArgoCD..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "? Waiting for ArgoCD pods to be ready (this may take a few minutes)..."
sleep 15
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

echo "?? Patching ArgoCD server to run in insecure mode for AGIC compatibility..."
kubectl -n argocd patch deployment argocd-server --type json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--insecure"}]'
sleep 5
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

echo "?? 2. Installing Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml

echo "? Waiting for Cert-Manager pods to be ready..."
sleep 15
kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=300s

echo "?? Waiting an extra 20 seconds for Cert-Manager Webhooks to stabilize..."
sleep 20

echo "?? 3. Deploying the Infra ArgoCD Application (Prometheus, Grafana, Dashboards)..."
kubectl apply -f argocd/infra-app.yaml

echo "? Waiting for ArgoCD to sync the Infra Application..."
sleep 30

echo "?? 4. Fetching Initial Passwords..."
echo "--------------------------------------------------------"

# Fetch ArgoCD Password
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "???  ArgoCD URL:      http://argocd.flowforge.fun"
echo "?? ArgoCD Username: admin"
echo "?? ArgoCD Password: $ARGOCD_PASS"
echo ""

# Fetch Grafana Password
GRAFANA_PASS=$(kubectl -n monitoring get secret infra-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d || kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d || echo "Still generating...")
echo "?? Grafana URL:      http://grafana.flowforge.fun"
echo "?? Grafana Username: admin"
echo "?? Grafana Password: $GRAFANA_PASS"
echo "--------------------------------------------------------"

echo "? Bootstrapping Complete! You can now manually install your FlowForge Dev/Prod Argo apps."

