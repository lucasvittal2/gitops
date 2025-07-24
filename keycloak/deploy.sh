#!/bin/bash

# Color codes for logging
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Parse command line arguments
FORCE_RECREATE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENV="$2"
      shift 2
      ;;
    --force)
      FORCE_RECREATE=true
      shift
      ;;
    *)
      log_error "Unknown option $1"
      echo "Usage: $0 --env <homolog|production> [--force]"
      exit 1
      ;;
  esac
done

# Check if env variable is set
if [[ -z "$ENV" ]]; then
  log_error "--env parameter is required"
  echo "Usage: $0 --env <homolog|production> [--force]"
  exit 1
fi

# Function to fix NGINX Ingress Controller issues
fix_ingress_controller() {
  log_info "Checking NGINX Ingress Controller status..."
  
  # Check if ingress addon is enabled
  if ! minikube addons list | grep -q "ingress.*enabled"; then
    log_info "Enabling Minikube ingress addon..."
    minikube addons enable ingress
    
    # Wait for ingress controller to be ready
    log_info "Waiting for ingress controller to be ready..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=300s
  fi
  
  # Check if admission webhook is causing issues
  if kubectl get validatingwebhookconfiguration ingress-nginx-admission &>/dev/null; then
    log_info "Checking admission webhook health..."
    
    # Test if webhook is responsive
    if ! kubectl get pods -n ingress-nginx | grep -q "ingress-nginx-controller.*Running"; then
      log_warning "Ingress controller pods not running properly"
      
      # Restart the ingress addon
      log_info "Restarting ingress addon..."
      minikube addons disable ingress
      sleep 5
      minikube addons enable ingress
      
      # Wait for controller to be ready
      kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    fi
    
    # If still having issues, temporarily disable admission webhook
    if ! kubectl get svc ingress-nginx-controller-admission -n ingress-nginx &>/dev/null; then
      log_warning "Admission webhook service not found, disabling validation temporarily"
      kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found
    fi
  fi
}

# Function to safely apply or recreate Kubernetes resources
apply_keycloak_resources() {
  local ingress_config_file=$1
  local config_file=$2
  local resolved_ingress_config="keycloak/keycloak-ingress.yaml"

  sed "s/KEYCLOAK_HOST/keycloak.$(minikube ip).nip.io/" "$ingress_config_file" > "$resolved_ingress_config"

  log_info "Checking for existing Keycloak service..."

  if kubectl get service keycloak &> /dev/null; then
    log_warning "Keycloak service already exists"

    if [[ "$FORCE_RECREATE" == "true" ]]; then
      log_info "Force recreate enabled - deleting existing Keycloak resources..."

      kubectl delete service keycloak --ignore-not-found
      kubectl delete service keycloak-discovery --ignore-not-found
      kubectl delete statefulset keycloak --ignore-not-found
      kubectl delete deployment postgres --ignore-not-found
      kubectl delete service postgres --ignore-not-found
      kubectl delete ingress keycloak-ingress --ignore-not-found

      sleep 5

      log_info "Applying fresh Keycloak configuration..."
      kubectl apply -f "$config_file"
      
      # Apply ingress with retry logic
      apply_ingress_with_retry "$resolved_ingress_config"
    else
      log_info "Attempting to update existing resources..."

      # Delete existing ingress first to avoid conflicts
      kubectl delete ingress keycloak-ingress --ignore-not-found
      sleep 2

      if kubectl apply -f "$config_file"; then
        apply_ingress_with_retry "$resolved_ingress_config"
        log_success "Resources updated successfully"
      else
        log_warning "Update failed, falling back to delete-and-apply..."

        kubectl delete service keycloak --ignore-not-found
        sleep 2

        kubectl apply -f "$config_file"
        apply_ingress_with_retry "$resolved_ingress_config"
      fi
    fi
  else
    log_info "No existing Keycloak service found, applying configuration..."
    kubectl apply -f "$config_file"
    apply_ingress_with_retry "$resolved_ingress_config"
  fi

  rm -f "$resolved_ingress_config"
}

# Function to apply ingress with retry logic
apply_ingress_with_retry() {
  local ingress_file=$1
  local max_attempts=3
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    log_info "Applying ingress configuration (attempt $attempt/$max_attempts)..."
    
    if kubectl apply -f "$ingress_file"; then
      log_success "Ingress applied successfully"
      return 0
    else
      log_warning "Ingress application failed on attempt $attempt"
      
      if [[ $attempt -eq $max_attempts ]]; then
        log_error "Failed to apply ingress after $max_attempts attempts"
        log_info "You can manually apply the ingress later with: kubectl apply -f $ingress_file"
        return 1
      fi
      
      # Wait and fix ingress controller before next attempt
      sleep 10
      fix_ingress_controller
      ((attempt++))
    fi
  done
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
  log_info "Waiting for PostgreSQL to be ready..."
  if kubectl wait --for=condition=available deployment/postgres --timeout=120s; then
    log_success "PostgreSQL is ready"
  else
    log_warning "PostgreSQL readiness check timed out, continuing anyway..."
  fi
}

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
  log_info "Waiting for Keycloak pods to be ready..."
  if kubectl wait --for=condition=ready pod -l app=keycloak --timeout=300s; then
    log_success "Keycloak pods are ready"
  else
    log_warning "Timeout waiting for Keycloak pods to be ready"
  fi
}

# Main deployment logic
deploy_environment() {
  local env=$1
  local ingress_config_file
  local config_file

  case "$env" in
    dev)
      ingress_config_file="keycloak/dev/keycloak-ingress_template.yaml"
      config_file="keycloak/dev/keycloak.yaml"
      ;;
    homolog)
      ingress_config_file="keycloak/homolog/keycloak-ingress_template.yaml"
      config_file="keycloak/homolog/keycloak.yaml"
      ;;
    production)
      ingress_config_file="keycloak/production/keycloak-ingress.yaml"
      config_file="keycloak/production/keycloak.yaml"
      ;;
    *)
      log_error "Invalid environment '$env'"
      echo "Supported environments: homolog, production"
      exit 1
      ;;
  esac

  if [[ ! -f "$config_file" ]]; then
    log_error "Configuration file '$config_file' not found"
    exit 1
  fi

  log_info "Starting deployment for $env environment..."
  
  # Fix ingress controller issues before deployment
  fix_ingress_controller
  
  apply_keycloak_resources "$ingress_config_file" "$config_file"

  wait_for_postgres
  wait_for_keycloak

  local ip
  ip=$(minikube ip)
  export KEYCLOAK_URL="https://keycloak.$ip.nip.io"

  echo ""
  echo "**********************************************************************"
  echo "KEYCLOAK DEPLOYMENT SUCCESSFUL - $env ENVIRONMENT"
  echo "**********************************************************************"
  echo "Keycloak:                 $KEYCLOAK_URL"
  echo "Keycloak Admin Console:   $KEYCLOAK_URL/admin"
  echo "Keycloak Account Console: $KEYCLOAK_URL/realms/myrealm/account"
  echo ""
  echo "Default Admin Credentials:"
  echo "Username: admin"
  echo "Password: admin"
  echo ""
  echo "**********************************************************************"

  log_success "Keycloak deployed successfully for $env environment"
}

# Execute deployment
deploy_environment "$ENV"