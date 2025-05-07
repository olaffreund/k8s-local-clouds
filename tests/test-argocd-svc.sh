#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Testing ArgoCD service..."

# Variables
NAMESPACE=argocd
SVC_NAME=argocd-server
PORT=8080
LOCAL_PORT=8080
TIMEOUT=5

# Check if ArgoCD namespace exists
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
  echo "❌ ArgoCD namespace not found. Is ArgoCD installed?"
  exit 1
fi

# Check if ArgoCD server pod is running
ARGOCD_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$ARGOCD_POD" ]; then
  echo "❌ ArgoCD server pod not found. Is ArgoCD fully deployed?"
  exit 1
fi

# Check pod status
POD_STATUS=$(kubectl get pod $ARGOCD_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
echo "ArgoCD server pod status: $POD_STATUS"
if [ "$POD_STATUS" != "Running" ]; then
  echo "❌ ArgoCD server pod is not running. Current status: $POD_STATUS"
  exit 1
fi

# Port forward to ArgoCD server
echo "Setting up port forwarding to ArgoCD server ($SVC_NAME)..."
kubectl port-forward "svc/$SVC_NAME" "$LOCAL_PORT:$PORT" -n "$NAMESPACE" &
PF_PID=$!

# Wait for port-forwarding to be established
echo "Waiting for port-forwarding to be established..."
sleep 3

# Test ArgoCD server with curl
echo "Testing ArgoCD server connectivity..."
if timeout $TIMEOUT curl -s -k "https://localhost:$LOCAL_PORT" -o /dev/null; then
  echo "✅ ArgoCD server is responding"
  HTTP_STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" "https://localhost:$LOCAL_PORT")
  echo "HTTP Status: $HTTP_STATUS"
else
  echo "❌ ArgoCD server is not responding or the connection timed out"
  # Kill port forwarding process
  kill $PF_PID 2>/dev/null || true
  exit 1
fi

# Get initial admin password (if available)
if kubectl -n $NAMESPACE get secret argocd-initial-admin-secret &>/dev/null; then
  echo "📝 Initial admin password available in secret: argocd-initial-admin-secret"
  echo "To retrieve it: kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
else
  echo "ℹ️ Initial admin password secret not found. It might have been already used or not yet created."
fi

# Kill port forwarding process
kill $PF_PID 2>/dev/null || true

echo "✅ ArgoCD service test completed!"