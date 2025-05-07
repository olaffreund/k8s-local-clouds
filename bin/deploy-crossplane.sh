#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="${SCRIPT_DIR}/../deployment"

echo "🚀 Deploying Crossplane to Kubernetes..."

# Create the crossplane-system namespace
echo "Creating crossplane-system namespace..."
kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/core/namespace.yaml"

echo "Installing Crossplane using Helm..."
# Install Crossplane via Helm
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --wait

# Wait for Crossplane to be ready
echo "Waiting for Crossplane pods to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/crossplane -n crossplane-system

echo "Installing Crossplane provider configurations..."
# Apply provider configurations
kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/core/crossplane.yaml"

# Wait for the function controllers to be ready
echo "Waiting for Crossplane Function controller to be ready..."
kubectl wait --for=condition=established --timeout=60s crd/functions.pkg.crossplane.io
sleep 10

echo "Installing cloud providers..."
# Install cloud providers - AWS, Azure, GCP
kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/providers/aws-provider.yaml"
kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/providers/azure-provider.yaml"
kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/providers/gcp-provider.yaml"

# Wait for providers to be ready
echo "Waiting for providers to be healthy..."
echo "This may take a few minutes..."
sleep 30
kubectl wait --for=condition=healthy --timeout=180s provider.pkg.crossplane.io/provider-aws
kubectl wait --for=condition=healthy --timeout=180s provider.pkg.crossplane.io/provider-azure
kubectl wait --for=condition=healthy --timeout=180s provider.pkg.crossplane.io/provider-gcp

echo "ℹ️ Before deploying cloud resources, update provider secrets with actual credentials"
echo "You can use the update-cloud-credentials.sh script for this purpose"

read -p "Do you want to deploy cloud resources now? (yes/no) " -r
echo
if [[ $REPLY =~ ^[Yy]es|[Yy]$ ]]; then
    echo "Deploying AWS resources..."
    kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/resources/aws/"
    
    echo "Deploying Azure resources..."
    kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/resources/azure/"
    
    echo "Deploying GCP resources..."
    kubectl apply -f "${DEPLOYMENT_DIR}/crossplane/resources/gcp/"
    
    echo "✅ Resources deployed successfully! Check status with:"
    echo "kubectl get managed"
else
    echo "Skipping resource deployment."
    echo "You can deploy resources later with:"
    echo "kubectl apply -f ${DEPLOYMENT_DIR}/crossplane/resources/<provider>/"
fi