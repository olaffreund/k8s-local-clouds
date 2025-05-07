{
  description = "Kubernetes local development environment with minikube";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Scripts for build, deploy, and test operations
      buildScript = pkgs.writeShellScriptBin "k8s-build" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "🔨 Building application container images..."

        # Check if APP_PATH is provided
        APP_PATH=''${1:-"./apps/demo"}
        APP_NAME=$(basename $APP_PATH)
        echo "Building $APP_NAME from $APP_PATH"

        # Build the Docker image with Buildah
        if [ -f "$APP_PATH/Dockerfile" ]; then
          echo "Found Dockerfile, building with Docker..."
          docker build -t "local/$APP_NAME:latest" "$APP_PATH"
          # Load the image into minikube
          echo "Loading image into minikube..."
          minikube image load "local/$APP_NAME:latest"
        else
          echo "No Dockerfile found at $APP_PATH"
          exit 1
        fi

        echo "✅ Build completed successfully!"
      '';

      deployScript = pkgs.writeShellScriptBin "k8s-deploy" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "🚀 Deploying to Kubernetes..."

        # Ensure namespace exists
        kubectl apply -f deployment/namespace.yaml

        # Apply deployments
        if [ $# -eq 0 ]; then
          echo "Deploying all resources in deployment directory..."
          kubectl apply -f deployment/
        else
          echo "Deploying specific resources: $@"
          for resource in "$@"; do
            kubectl apply -f "deployment/$resource.yaml"
          done
        fi

        echo "Waiting for deployments to be ready..."
        kubectl wait --namespace=local-apps --for=condition=available deployments --all --timeout=300s

        echo "✅ Deployment completed successfully!"

        # Show running pods
        echo "📊 Current pods:"
        kubectl get pods -n local-apps
      '';

      testScript = pkgs.writeShellScriptBin "k8s-test" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "🧪 Running tests against deployed services..."

        # Check if specific service is provided
        SERVICE_NAME=''${1:-"demo-app-svc"}
        NAMESPACE=''${2:-"local-apps"}

        # Ensure service exists
        if ! kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" &>/dev/null; then
          echo "❌ Service $SERVICE_NAME not found in namespace $NAMESPACE"
          exit 1
        fi

        # Port forward to the service
        echo "Setting up port forwarding to $SERVICE_NAME..."
        PORT=8080
        kubectl port-forward "service/$SERVICE_NAME" "$PORT:80" -n "$NAMESPACE" &
        PF_PID=$!

        # Wait for port-forwarding to be established
        sleep 2

        # Test service with curl
        echo "Testing service connectivity..."
        if curl -s "http://localhost:$PORT" -o /dev/null; then
          echo "✅ Service is responding"
          HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT")
          echo "HTTP Status: $HTTP_STATUS"
        else
          echo "❌ Service is not responding"
        fi

        # Clean up port forwarding
        kill $PF_PID

        # Run additional test scripts if they exist
        TEST_SCRIPT="./tests/test-$SERVICE_NAME.sh"
        if [ -f "$TEST_SCRIPT" ]; then
          echo "Running custom test script: $TEST_SCRIPT"
          bash "$TEST_SCRIPT"
        fi

        echo "✅ Testing completed!"
      '';

      cleanupScript = pkgs.writeShellScriptBin "k8s-cleanup" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "🧹 Cleaning up resources..."

        if [ $# -eq 0 ]; then
          echo "Removing all resources in local-apps namespace..."
          kubectl delete namespace local-apps --wait=true
          kubectl create -f deployment/namespace.yaml
        else
          echo "Removing specific resources: $@"
          for resource in "$@"; do
            kubectl delete -f "deployment/$resource.yaml" --wait=true
          done
        fi

        echo "✅ Cleanup completed!"
      '';

      # New script for deploying Crossplane resources
      crossplaneDeployScript = pkgs.writeShellScriptBin "crossplane-deploy" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "🚀 Deploying Crossplane resources..."

        # Check if namespace exists, if not create it
        if ! kubectl get namespace crossplane-system &>/dev/null; then
          echo "Creating crossplane-system namespace..."
          kubectl apply -f deployment/crossplane/core/namespace.yaml
        fi

        # Deploy specific resources or all if no arguments provided
        if [ $# -eq 0 ]; then
          echo "Deploying all Crossplane resources..."

          # First apply providers
          echo "Applying Crossplane providers..."
          kubectl apply -f deployment/crossplane/providers/

          # Wait for providers to be healthy
          echo "Waiting for providers to be ready (this may take a while)..."
          sleep 10

          # Then apply resources
          echo "Applying cloud resources..."
          kubectl apply -f deployment/crossplane/resources/aws/
          kubectl apply -f deployment/crossplane/resources/azure/
          kubectl apply -f deployment/crossplane/resources/gcp/
        else
          echo "Deploying specific Crossplane resources: $@"
          for resource in "$@"; do
            case "$resource" in
              aws|AWS)
                kubectl apply -f deployment/crossplane/resources/aws/
                ;;
              azure|Azure)
                kubectl apply -f deployment/crossplane/resources/azure/
                ;;
              gcp|GCP)
                kubectl apply -f deployment/crossplane/resources/gcp/
                ;;
              *)
                echo "Unknown resource type: $resource"
                echo "Available options: aws, azure, gcp"
                exit 1
                ;;
            esac
          done
        fi

        echo "✅ Crossplane resources deployed successfully!"
      '';
    in {
      # Expose the scripts as packages
      packages = {
        build = buildScript;
        deploy = deployScript;
        test = testScript;
        cleanup = cleanupScript;
        crossplane-deploy = crossplaneDeployScript;
        default = pkgs.symlinkJoin {
          name = "k8s-tools";
          paths = [buildScript deployScript testScript cleanupScript crossplaneDeployScript];
        };
      };

      # Expose the scripts as apps
      apps = {
        build = flake-utils.lib.mkApp {drv = buildScript;};
        deploy = flake-utils.lib.mkApp {drv = deployScript;};
        test = flake-utils.lib.mkApp {drv = testScript;};
        cleanup = flake-utils.lib.mkApp {drv = cleanupScript;};
        crossplane-deploy = flake-utils.lib.mkApp {drv = crossplaneDeployScript;};
        default = flake-utils.lib.mkApp {drv = deployScript;};
      };

      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Kubernetes tools
          kubectl
          kubernetes-helm
          minikube
          k9s
          kubectx
          stern

          # Infrastructure as Code tools
          kustomize

          # Supporting tools
          docker
          jq
          yq

          # Environment setup
          direnv

          # Crossplane tools
          crossplane-cli

          # Our custom scripts
          buildScript
          deployScript
          testScript
          cleanupScript
          crossplaneDeployScript
        ];

        shellHook = ''
                    echo "🚀 Welcome to Kubernetes Local Development Environment"
                    echo "Commands available:"
                    echo "  - minikube start        # Start local Kubernetes cluster"
                    echo "  - minikube dashboard    # Open Kubernetes dashboard"
                    echo "  - kubectl get pods      # List running pods"
                    echo "  - k9s                   # Terminal UI for Kubernetes"
                    echo ""
                    echo "Build, Deploy & Test commands:"
                    echo "  - k8s-build [app_path]  # Build container for app (default: ./apps/demo)"
                    echo "  - k8s-deploy [resource] # Deploy all or specific resources"
                    echo "  - k8s-test [service]    # Test service connectivity (default: demo-app-svc)"
                    echo "  - k8s-cleanup [resource]# Clean up all or specific resources"
                    echo "  - crossplane-deploy     # Deploy Crossplane resources to cloud providers"
                    echo ""
                    echo "Your deployment configurations are in the ./deployment directory"

                    # Initialize direnv
                    eval "$(direnv hook bash)"

                    # Create a .envrc file if it doesn't exist
                    if [ ! -f .envrc ]; then
                      echo "Creating default .envrc file..."
                      cat > .envrc << 'EOF'
          # Environment variables for the project
          export KUBECONFIG="$PWD/.kube/config"
          export MINIKUBE_HOME="$PWD/.minikube"
          export DOCKER_CONFIG="$PWD/.docker"

          # Path to deployment configurations
          export K8S_DEPLOYMENT_PATH="$PWD/deployment"

          # Add project bin to PATH
          export PATH="$PWD/bin:$PATH"
          EOF
                      direnv allow .
                      echo "Created .envrc file with default environment variables"
                    else
                      echo "Using existing .envrc file"
                      direnv allow .
                    fi

                    echo "🔄 Environment variables are now managed by direnv"

                    # Function to set up minikube with default configuration
                    function setup-minikube() {
                      minikube start --driver=docker --cpus=2 --memory=4096 --disk-size=20g

                      # Enable standard addons
                      minikube addons enable ingress
                      minikube addons enable metrics-server

                      # Install Crossplane using Helm
                      echo "Installing Crossplane via Helm..."
                      helm repo add crossplane-stable https://charts.crossplane.io/stable
                      helm repo update
                      helm install crossplane crossplane-stable/crossplane \
                        --namespace crossplane-system \
                        --create-namespace \
                        --version 1.15.0

                      # Wait for Crossplane to be ready
                      echo "Waiting for Crossplane pods to be ready..."
                      kubectl wait --for=condition=available --timeout=300s deployment/crossplane -n crossplane-system

                      kubectl config use-context minikube
                      echo "Minikube is now running with Crossplane installed!"
                    }

                    # Function to set up Crossplane providers
                    function setup-crossplane-providers() {
                      echo "🔌 Setting up Crossplane providers..."

                      # Apply core configurations first
                      kubectl apply -f deployment/crossplane/core/crossplane.yaml

                      # Install cloud providers
                      kubectl apply -f deployment/crossplane/providers/

                      echo "⏳ Waiting for Crossplane providers to become healthy..."
                      echo "This may take a few minutes..."
                      echo "You can check the status with: kubectl get providers"
                    }

                    # Function for full workflow
                    function k8s-workflow() {
                      echo "📋 Running complete workflow: build → deploy → test"
                      APP_PATH=''${1:-"./apps/demo"}
                      APP_NAME=$(basename $APP_PATH)

                      k8s-build "$APP_PATH" && \
                      k8s-deploy && \
                      k8s-test "''${2:-"$APP_NAME-svc"}"

                      echo "✨ Workflow completed!"
                    }

                    # Export the functions
                    export -f setup-minikube
                    export -f setup-crossplane-providers
                    export -f k8s-workflow
                    echo "Run 'setup-minikube' to configure your minikube cluster with Crossplane"
                    echo "Run 'setup-crossplane-providers' to install cloud providers for Crossplane"
                    echo "Run 'k8s-workflow [app_path] [service_name]' for the full build-deploy-test workflow"
        '';
      };
    });
}
