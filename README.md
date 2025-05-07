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
  - `/simple-demo` - Simple demo application
  - `/database` - Database (PostgreSQL) deployment
  - `/redis` - Redis cache deployment
  - `/nginx` - Web server deployment

- `/tests` - Contains test scripts for all deployments
  - `test-demo-app-svc.sh` - Tests for the simple demo app
  - `test-nginx-web-svc.sh` - Tests for the Nginx web server
  - `test-postgres-svc.sh` - Tests for the PostgreSQL database
  - `test-redis-svc.sh` - Tests for the Redis cache

## Deployment and Testing

### Deployment Options

This repository provides several deployments that can be used individually or together:

#### Simple Demo Application
```bash
kubectl apply -f deployment/namespace.yaml
kubectl apply -f deployment/simple-demo/
```

#### Complete Infrastructure Stack
```bash
# Apply namespace first
kubectl apply -f deployment/namespace.yaml

# Deploy database
kubectl apply -f deployment/database/postgres.yaml

# Deploy Redis cache
kubectl apply -f deployment/redis/redis.yaml

# Deploy Nginx web server (connects to both database and Redis)
kubectl apply -f deployment/nginx/nginx.yaml
```

You can also use the flake-provided deploy script:
```bash
# Deploy everything
k8s-deploy

# Deploy specific components
k8s-deploy database/postgres
k8s-deploy redis/redis
k8s-deploy nginx/nginx
```

### Accessing the Applications

#### Accessing the Nginx Web Application

**Option 1: Using Ingress (Recommended)**

1. Get the minikube IP address:
   ```bash
   minikube ip
   ```

2. Add the domain to your hosts file:
   ```bash
   echo "$(minikube ip) web-app.local" | sudo tee -a /etc/hosts
   ```

3. Access the application in your browser:
   ```
   http://web-app.local
   ```

**Option 2: Using Port Forwarding**

```bash
kubectl port-forward -n local-apps svc/nginx-web-svc 8080:80
```
Then access the application at http://localhost:8080

**Option 3: Using Minikube Service Command**

```bash
minikube service nginx-web-svc -n local-apps
```
This will automatically open your browser to the service.

#### Accessing the PostgreSQL Database

```bash
kubectl port-forward -n local-apps svc/postgres-svc 5432:5432
```

Connect using:
- Host: localhost
- Port: 5432
- User: appuser
- Password: apppassword
- Database: appdb

#### Accessing the Redis Cache

```bash
kubectl port-forward -n local-apps svc/redis-svc 6379:6379
```

Connect using:
- Host: localhost
- Port: 6379
- No password required

### Testing

The repository includes test scripts for all deployments in the `/tests` directory:

```bash
# Test the demo application
./tests/test-demo-app-svc.sh

# Test the Nginx web server
./tests/test-nginx-web-svc.sh

# Test the PostgreSQL database
./tests/test-postgres-svc.sh

# Test the Redis cache
./tests/test-redis-svc.sh
```

You can also use the flake-provided test script:
```bash
# Test specific service
k8s-test nginx-web-svc
k8s-test postgres-svc
k8s-test redis-svc

# Default tests the demo-app-svc
k8s-test
```

### Complete Build-Deploy-Test Workflow

To run the entire workflow (build container images, deploy to Kubernetes, and run tests):

```bash
k8s-workflow [app_path] [service_name]
```

Example:
```bash
k8s-workflow ./apps/demo nginx-web-svc
```

## Customizing the Environment

Edit the `flake.nix` file to add more development tools as needed.