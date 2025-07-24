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

      sleep 5

      log_info "Applying fresh Keycloak configuration..."
      kubectl apply -f "$config_file"
      kubectl apply -f "$resolved_ingress_config"
    else
      log_info "Attempting to update existing resources..."

      if kubectl replace -f "$resolved_ingress_config" --force; then
        log_success "Resources replaced successfully"
      else
        log_warning "Replace failed, falling back to delete-and-apply..."

        kubectl delete service keycloak --ignore-not-found
        sleep 2

        kubectl apply -f "$config_file"
        kubectl apply -f "$resolved_ingress_config"
      fi
    fi
  else
    log_info "No existing Keycloak service found, applying configuration..."
    kubectl apply -f "$config_file"
    kubectl apply -f "$resolved_ingress_config"
  fi

  rm -f "$resolved_ingress_config"
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
  apply_keycloak_resources "$ingress_config_file" "$config_file"

  wait_for_postgres
  wait_for_keycloak

  log_info "Enabling Ingress addon for Minikube..."
  minikube addons enable ingress &>/dev/null

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
