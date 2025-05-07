#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="${SCRIPT_DIR}/../deployment"

echo "🔑 Cloud Provider Credential Update Utility"
echo "============================================"

function update_aws_credentials() {
    echo "Updating AWS credentials..."
    
    # Check if AWS CLI is configured
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI not found. Please install and configure it first."
        return 1
    fi
    
    # Prompt for AWS credentials
    read -p "Use AWS CLI credentials? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy]es|[Yy]$ ]]; then
        # Generate credentials JSON from AWS CLI
        echo "Generating AWS credentials from AWS CLI config..."
        AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
        AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
        
        if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
            echo "❌ AWS credentials not found in AWS CLI config."
            return 1
        fi
        
        # Create JSON and encode as base64
        AWS_CREDS=$(echo -n "{\"aws_access_key_id\":\"$AWS_ACCESS_KEY_ID\",\"aws_secret_access_key\":\"$AWS_SECRET_ACCESS_KEY\"}" | base64 -w 0)
    else
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -p "AWS Secret Access Key: " -s AWS_SECRET_ACCESS_KEY
        echo
        
        # Create JSON and encode as base64
        AWS_CREDS=$(echo -n "{\"aws_access_key_id\":\"$AWS_ACCESS_KEY_ID\",\"aws_secret_access_key\":\"$AWS_SECRET_ACCESS_KEY\"}" | base64 -w 0)
    fi
    
    # Update Kubernetes secret
    echo "Creating/updating Kubernetes secret for AWS..."
    kubectl create secret generic aws-creds \
        --namespace crossplane-system \
        --from-literal=creds="$AWS_CREDS" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✅ AWS credentials updated successfully!"
}

function update_azure_credentials() {
    echo "Updating Azure credentials..."
    
    # Check if Azure CLI is configured
    if ! command -v az &> /dev/null; then
        echo "❌ Azure CLI not found. Please install and configure it first."
        return 1
    fi
    
    # Prompt for Azure account
    read -p "Use current Azure CLI credentials? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy]es|[Yy]$ ]]; then
        # Generate credentials JSON from Azure CLI
        echo "Generating service principal for Crossplane..."
        
        SP_NAME="crossplane-sp-$(date +%s)"
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        
        echo "Creating service principal: $SP_NAME..."
        SP_OUTPUT=$(az ad sp create-for-rbac --name "$SP_NAME" --role Contributor --scopes "/subscriptions/$SUBSCRIPTION_ID" --query "{clientId:appId,clientSecret:password,tenantId:tenant}")
        
        CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
        CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.clientSecret')
        TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenantId')
        
        # Create JSON and encode as base64
        AZURE_CREDS=$(echo -n "{\"clientId\":\"$CLIENT_ID\",\"clientSecret\":\"$CLIENT_SECRET\",\"tenantId\":\"$TENANT_ID\",\"subscriptionId\":\"$SUBSCRIPTION_ID\"}" | base64 -w 0)
    else
        read -p "Azure Client ID: " CLIENT_ID
        read -p "Azure Client Secret: " -s CLIENT_SECRET
        echo
        read -p "Azure Tenant ID: " TENANT_ID
        read -p "Azure Subscription ID: " SUBSCRIPTION_ID
        
        # Create JSON and encode as base64
        AZURE_CREDS=$(echo -n "{\"clientId\":\"$CLIENT_ID\",\"clientSecret\":\"$CLIENT_SECRET\",\"tenantId\":\"$TENANT_ID\",\"subscriptionId\":\"$SUBSCRIPTION_ID\"}" | base64 -w 0)
    fi
    
    # Update Kubernetes secret
    echo "Creating/updating Kubernetes secret for Azure..."
    kubectl create secret generic azure-creds \
        --namespace crossplane-system \
        --from-literal=creds="$AZURE_CREDS" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✅ Azure credentials updated successfully!"
}

function update_gcp_credentials() {
    echo "Updating GCP credentials..."
    
    # Check if GCP CLI is configured
    if ! command -v gcloud &> /dev/null; then
        echo "❌ Google Cloud SDK not found. Please install and configure it first."
        return 1
    fi
    
    # Prompt for GCP account
    read -p "Generate new service account credentials using current gcloud config? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy]es|[Yy]$ ]]; then
        # Generate service account using gcloud
        echo "Generating service account for Crossplane..."
        
        PROJECT_ID=$(gcloud config get-value project)
        if [ -z "$PROJECT_ID" ]; then
            echo "❌ No GCP project found in gcloud config."
            return 1
        fi
        
        SA_NAME="crossplane-sa-$(date +%s)"
        SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
        
        echo "Creating service account: $SA_NAME in project $PROJECT_ID..."
        gcloud iam service-accounts create "$SA_NAME" --display-name="Crossplane Service Account"
        
        # Grant roles
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SA_EMAIL" \
            --role="roles/editor"
        
        # Create and download key
        echo "Generating key file..."
        KEY_FILE="$SCRIPT_DIR/gcp-credentials.json"
        gcloud iam service-accounts keys create "$KEY_FILE" --iam-account="$SA_EMAIL"
        
        # Create Kubernetes secret
        echo "Creating/updating Kubernetes secret for GCP..."
        kubectl create secret generic gcp-creds \
            --namespace crossplane-system \
            --from-file=creds="$KEY_FILE" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        # Update provider config with project ID
        echo "Updating GCP provider configuration with project ID: $PROJECT_ID"
        sed -i "s/projectID: \"your-gcp-project-id\"/projectID: \"$PROJECT_ID\"/" "$DEPLOYMENT_DIR/crossplane/providers/gcp-provider.yaml"
        
        # Clean up key file after creating secret
        rm -f "$KEY_FILE"
    else
        read -p "Path to GCP credentials JSON file: " GCP_CREDS_FILE
        
        if [ ! -f "$GCP_CREDS_FILE" ]; then
            echo "❌ File not found: $GCP_CREDS_FILE"
            return 1
        fi
        
        # Extract project ID
        PROJECT_ID=$(jq -r '.project_id' "$GCP_CREDS_FILE")
        if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" == "null" ]; then
            read -p "GCP Project ID: " PROJECT_ID
        else
            echo "Found Project ID: $PROJECT_ID"
        fi
        
        # Update provider config with project ID
        echo "Updating GCP provider configuration with project ID: $PROJECT_ID"
        sed -i "s/projectID: \"your-gcp-project-id\"/projectID: \"$PROJECT_ID\"/" "$DEPLOYMENT_DIR/crossplane/providers/gcp-provider.yaml"
        
        # Create Kubernetes secret
        echo "Creating/updating Kubernetes secret for GCP..."
        kubectl create secret generic gcp-creds \
            --namespace crossplane-system \
            --from-file=creds="$GCP_CREDS_FILE" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    echo "✅ GCP credentials updated successfully!"
}

# Make script executable
chmod +x "$0"

PS3="Select a cloud provider to update credentials (or 4 to update all): "
options=("AWS" "Azure" "GCP" "Update All" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "AWS")
            update_aws_credentials
            break
            ;;
        "Azure")
            update_azure_credentials
            break
            ;;
        "GCP")
            update_gcp_credentials
            break
            ;;
        "Update All")
            update_aws_credentials
            update_azure_credentials
            update_gcp_credentials
            break
            ;;
        "Quit")
            echo "Exiting without updating credentials."
            exit 0
            ;;
        *) 
            echo "Invalid option $REPLY"
            ;;
    esac
done

echo "Done! Credentials have been updated for your cloud providers."
echo "You can now deploy your cloud resources with:"
echo "kubectl apply -f ${DEPLOYMENT_DIR}/crossplane/resources/<provider>/"