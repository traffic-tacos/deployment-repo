#!/bin/bash

# ArgoCD Deployment Script for Traffic Tacos
# This script implements the tasks from specs/001-argocd-deployment/tasks.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="argocd"
RELEASE_NAME="argocd"
DOMAIN="argocd.traffictacos.com"
AWS_REGION="ap-northeast-2"
CLUSTER_NAME="ticket-cluster"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required tools
    local tools=("kubectl" "helm" "aws" "yq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            exit 1
        fi
    done

    # Check kubectl context
    local current_context
    current_context=$(kubectl config current-context)
    log_info "Current kubectl context: $current_context"

    # Check EKS cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity --profile tacos &> /dev/null; then
        log_error "AWS credentials not configured for 'tacos' profile"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Phase 3.1: Environment Setup
setup_environment() {
    log_info "Phase 3.1: Setting up environment..."

    # T001: Create namespace
    log_info "Creating argocd namespace..."
    kubectl apply -f manifests/argocd/namespace.yaml

    # T002: Verify AWS resources
    log_info "Verifying AWS access..."
    local account_id
    account_id=$(aws sts get-caller-identity --profile tacos --query 'Account' --output text)
    log_info "AWS Account ID: $account_id"

    # Check Route53 domain
    if aws route53 list-hosted-zones --profile tacos --query "HostedZones[?Name=='traffictacos.com.']" --output text | grep -q "traffictacos.com"; then
        log_success "Route53 hosted zone found"
    else
        log_warning "Route53 hosted zone not found - manual DNS setup required"
    fi

    # T003: Add Helm repository
    log_info "Adding ArgoCD Helm repository..."
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update

    # Verify chart availability
    local chart_version
    chart_version=$(helm search repo argo/argo-cd --version "5.46.*" -o json | jq -r '.[0].version' 2>/dev/null || echo "not found")
    if [[ "$chart_version" != "not found" ]]; then
        log_success "ArgoCD Helm chart available: $chart_version"
    else
        log_error "Required ArgoCD Helm chart version not found"
        exit 1
    fi

    log_success "Environment setup completed"
}

# Phase 3.2: Validation (Infrastructure TDD)
run_validations() {
    log_info "Phase 3.2: Running validation tests..."

    # T005: Validate Helm values
    log_info "Validating Helm values schema..."
    if yq eval '.' helm-values/argocd-prod-values.yaml > /dev/null; then
        log_success "Helm values syntax valid"
    else
        log_error "Invalid Helm values syntax"
        return 1
    fi

    # Check required fields
    local domain
    domain=$(yq eval '.global.domain' helm-values/argocd-prod-values.yaml)
    if [[ "$domain" == "$DOMAIN" ]]; then
        log_success "Domain configuration valid: $domain"
    else
        log_error "Invalid domain configuration: $domain"
        return 1
    fi

    # T006: Test Helm template rendering
    log_info "Testing Helm template rendering..."
    if helm template "$RELEASE_NAME" argo/argo-cd \
        --values helm-values/argocd-prod-values.yaml \
        --namespace "$NAMESPACE" \
        --dry-run > /tmp/argocd-rendered.yaml 2>/dev/null; then
        log_success "Helm template renders successfully"
    else
        log_error "Helm template rendering failed"
        return 1
    fi

    # T007: Validate rendered manifests
    log_info "Validating rendered manifests..."
    if kubectl apply --dry-run=client -f /tmp/argocd-rendered.yaml > /dev/null 2>&1; then
        log_success "Rendered manifests are valid"
    else
        log_error "Rendered manifests validation failed"
        return 1
    fi

    log_success "All validations passed"
}

# Phase 3.3: Core ArgoCD Deployment
deploy_argocd() {
    log_info "Phase 3.3: Deploying ArgoCD core components..."

    # T012: Deploy ArgoCD with Helm
    log_info "Deploying ArgoCD using Helm..."

    # Get ACM certificate ARN
    local cert_arn
    cert_arn=$(aws acm list-certificates --profile tacos --region "$AWS_REGION" \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
        --output text 2>/dev/null || echo "")

    if [[ -n "$cert_arn" ]]; then
        log_info "Using ACM certificate: $cert_arn"
        # Update Helm values with certificate ARN
        yq eval ".server.ingress.annotations.\"alb.ingress.kubernetes.io/certificate-arn\" = \"$cert_arn\"" \
            -i helm-values/argocd-prod-values.yaml
    else
        log_warning "ACM certificate not found - manual certificate setup required"
    fi

    # Deploy ArgoCD
    helm upgrade --install "$RELEASE_NAME" argo/argo-cd \
        --namespace "$NAMESPACE" \
        --values helm-values/argocd-prod-values.yaml \
        --version 5.46.7 \
        --wait \
        --timeout 10m

    log_success "ArgoCD deployed successfully"

    # T013: Apply ingress configuration
    log_info "Applying ingress configuration..."
    if [[ -n "$cert_arn" ]]; then
        # Update ingress with certificate ARN
        sed "s|# alb.ingress.kubernetes.io/certificate-arn:.*|alb.ingress.kubernetes.io/certificate-arn: $cert_arn|" \
            manifests/argocd/ingress.yaml | kubectl apply -f -
    else
        kubectl apply -f manifests/argocd/ingress.yaml
    fi

    # T015: Verify deployment
    log_info "Verifying ArgoCD deployment..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n "$NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$NAMESPACE"

    log_success "ArgoCD core deployment verified"
}

# Phase 3.4: RBAC and Security Configuration
configure_security() {
    log_info "Phase 3.4: Configuring RBAC and security..."

    # T016: Create Traffic Tacos project
    log_info "Creating Traffic Tacos project..."
    kubectl apply -f manifests/projects/traffic-tacos-project.yaml

    # T017: Configure repository credentials (placeholder)
    log_info "Repository credentials configuration..."
    log_warning "Repository credentials must be configured manually with GitHub token"

    # T019: Apply network policies
    log_info "Applying network policies..."
    # Network policies are included in the main deployment

    log_success "Security configuration completed"
}

# Phase 3.5: Application Management Setup
setup_applications() {
    log_info "Phase 3.5: Setting up application management..."

    # T021-T025: Create application manifests
    log_info "Applying ArgoCD applications..."

    # Apply applications in dependency order
    local apps=(
        "applications/gateway/gateway-api.yaml"
        "applications/tacos/reservation-api.yaml"
        "applications/tacos/reservation-worker.yaml"
    )

    for app in "${apps[@]}"; do
        if [[ -f "$app" ]]; then
            log_info "Applying $(basename "$app")..."
            kubectl apply -f "$app"
        else
            log_warning "Application file not found: $app"
        fi
    done

    log_success "Application management setup completed"
}

# Get ArgoCD admin password
get_admin_password() {
    log_info "Retrieving ArgoCD admin password..."

    local admin_password
    admin_password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")

    if [[ -n "$admin_password" ]]; then
        echo ""
        log_success "ArgoCD Admin Credentials:"
        echo "  URL: https://$DOMAIN"
        echo "  Username: admin"
        echo "  Password: $admin_password"
        echo ""
    else
        log_warning "Could not retrieve admin password - may need to wait for deployment completion"
    fi
}

# Health check
health_check() {
    log_info "Running health checks..."

    # Check pod status
    local unhealthy_pods
    unhealthy_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -v Running | wc -l)

    if [[ "$unhealthy_pods" -eq 0 ]]; then
        log_success "All ArgoCD pods are healthy"
    else
        log_warning "$unhealthy_pods unhealthy pods found"
        kubectl get pods -n "$NAMESPACE"
    fi

    # Check services
    local services
    services=$(kubectl get services -n "$NAMESPACE" --no-headers | wc -l)
    log_info "$services services created"

    # Check ingress
    if kubectl get ingress argocd-server-ingress -n "$NAMESPACE" &>/dev/null; then
        local ingress_status
        ingress_status=$(kubectl get ingress argocd-server-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
        log_info "Ingress status: $ingress_status"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/argocd-rendered.yaml
}

# Main deployment function
main() {
    log_info "Starting ArgoCD deployment for Traffic Tacos..."

    # Set up cleanup trap
    trap cleanup EXIT

    # Run deployment phases
    check_prerequisites
    setup_environment
    run_validations
    deploy_argocd
    configure_security
    setup_applications

    # Post-deployment tasks
    health_check
    get_admin_password

    log_success "ArgoCD deployment completed successfully!"
    log_info "Next steps:"
    echo "  1. Access ArgoCD UI at https://$DOMAIN"
    echo "  2. Configure OIDC authentication (optional)"
    echo "  3. Set up monitoring and alerting"
    echo "  4. Configure backup strategy"
    echo "  5. Deploy remaining applications"
}

# Command line argument handling
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "validate")
        check_prerequisites
        run_validations
        log_success "Validation completed successfully"
        ;;
    "health")
        health_check
        ;;
    "password")
        get_admin_password
        ;;
    "help")
        echo "Usage: $0 [deploy|validate|health|password|help]"
        echo ""
        echo "Commands:"
        echo "  deploy   - Full ArgoCD deployment (default)"
        echo "  validate - Run validation tests only"
        echo "  health   - Check deployment health"
        echo "  password - Get admin password"
        echo "  help     - Show this help message"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac