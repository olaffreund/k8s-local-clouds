# Kubernetes Local Development Environment

This repository provides a Nix-based development environment for local Kubernetes development using minikube.

## Prerequisites

- [Nix package manager](https://nixos.org/download.html) with flakes enabled
- Docker (if using the docker driver for minikube)

## Getting Started

1. Clone this repository
2. Enter the development shell:
```bash
nix develop
```

3. Setup minikube with the pre-configured settings:
```bash
setup-minikube
```

4. Apply the Kubernetes configurations:
```bash
kubectl apply -f deployment/namespace.yaml
kubectl apply -f deployment/demo-app.yaml
kubectl apply -f deployment/ingress.yaml
```

5. Add the demo-app.local hostname to your /etc/hosts file:
```bash
echo "$(minikube ip) demo-app.local" | sudo tee -a /etc/hosts
```

6. Access the demo app at http://demo-app.local

## Available Commands

- `setup-minikube` - Initialize minikube with recommended settings
- `kubectl get pods -n local-apps` - Check the status of your pods
- `minikube dashboard` - Open the Kubernetes dashboard
- `k9s` - Start the terminal-based Kubernetes UI

## Directory Structure

- `/deployment` - Contains Kubernetes deployment manifests
  - `namespace.yaml` - Defines the local-apps namespace
  - `demo-app.yaml` - Demo application deployment and service
  - `ingress.yaml` - Ingress configuration for the demo app

## Customizing the Environment

Edit the `flake.nix` file to add more development tools as needed.