#!/bin/bash

# Environment Configuration Script for ArgoCD Deployment
# This script helps configure the actual environment values for deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration variables
AWS_PROFILE="tacos"
AWS_REGION="ap-northeast-2"
DOMAIN_NAME="traffictacos.com"
ARGOCD_SUBDOMAIN="argocd"

echo "========================================="
echo "    ArgoCD Environment Configuration"
echo "========================================="

# 1. Check AWS credentials and get account info
log_info "Checking AWS configuration..."
if AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile $AWS_PROFILE --query 'Account' --output text 2>/dev/null); then
    log_success "AWS Account ID: $AWS_ACCOUNT_ID"
else
    log_error "Failed to get AWS account info. Please check AWS profile '$AWS_PROFILE'"
    exit 1
fi

# 2. Check Route53 hosted zone
log_info "Checking Route53 hosted zone for $DOMAIN_NAME..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --profile $AWS_PROFILE --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text 2>/dev/null | cut -d'/' -f3)
if [[ -n "$HOSTED_ZONE_ID" ]]; then
    log_success "Route53 Hosted Zone ID: $HOSTED_ZONE_ID"
else
    log_warning "Route53 hosted zone not found. DNS setup will need to be done manually."
    HOSTED_ZONE_ID="MANUAL_SETUP_REQUIRED"
fi

# 3. Check ACM certificate
log_info "Checking ACM certificate for *.${DOMAIN_NAME}..."
CERT_ARN=$(aws acm list-certificates --region $AWS_REGION --profile $AWS_PROFILE \
    --query "CertificateSummaryList[?DomainName=='*.${DOMAIN_NAME}' || DomainName=='${DOMAIN_NAME}'].CertificateArn" \
    --output text 2>/dev/null | head -1)

if [[ -n "$CERT_ARN" && "$CERT_ARN" != "None" ]]; then
    log_success "ACM Certificate ARN: $CERT_ARN"
else
    log_warning "ACM certificate not found. You'll need to create one manually."
    CERT_ARN="MANUAL_SETUP_REQUIRED"
fi

# 4. Check EKS cluster
log_info "Checking EKS cluster access..."
if kubectl cluster-info >/dev/null 2>&1; then
    CURRENT_CONTEXT=$(kubectl config current-context)
    log_success "EKS cluster accessible. Context: $CURRENT_CONTEXT"
else
    log_error "Cannot access EKS cluster. Please check kubectl configuration."
    exit 1
fi

# 5. Generate updated configuration files
log_info "Generating updated configuration files..."

# Update Helm values file
log_info "Updating helm-values/argocd-prod-values.yaml..."
if [[ "$CERT_ARN" != "MANUAL_SETUP_REQUIRED" ]]; then
    # Update certificate ARN in Helm values
    yq eval ".server.ingress.annotations.\"alb.ingress.kubernetes.io/certificate-arn\" = \"$CERT_ARN\"" \
        -i helm-values/argocd-prod-values.yaml
fi

# Update ingress configuration
log_info "Updating manifests/argocd/ingress.yaml..."
if [[ "$CERT_ARN" != "MANUAL_SETUP_REQUIRED" ]]; then
    sed -i.bak "s|# alb.ingress.kubernetes.io/certificate-arn:.*|alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN|" \
        manifests/argocd/ingress.yaml
    sed -i.bak "s|arn:aws:acm:ap-northeast-2:ACCOUNT-ID:certificate/CERT-ID|$CERT_ARN|g" \
        manifests/argocd/ingress.yaml
fi

# Update AWS account references
log_info "Updating AWS Account ID references..."
find . -name "*.yaml" -type f -exec sed -i.bak "s|ACCOUNT-ID|$AWS_ACCOUNT_ID|g" {} \;

# Update domain references if different
if [[ "$DOMAIN_NAME" != "traffictacos.com" ]]; then
    log_info "Updating domain name references..."
    find . -name "*.yaml" -type f -exec sed -i.bak "s|traffictacos\\.com|$DOMAIN_NAME|g" {} \;
fi

# 6. Create environment-specific configuration
cat > .env.deployment << EOF
# ArgoCD Deployment Environment Configuration
# Generated on: $(date)

AWS_PROFILE=$AWS_PROFILE
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

DOMAIN_NAME=$DOMAIN_NAME
ARGOCD_DOMAIN=$ARGOCD_SUBDOMAIN.$DOMAIN_NAME

HOSTED_ZONE_ID=$HOSTED_ZONE_ID
CERT_ARN=$CERT_ARN

KUBERNETES_CONTEXT=$CURRENT_CONTEXT
EOF

log_success "Environment configuration saved to .env.deployment"

# 7. Create GitHub repository credentials template
log_info "Creating GitHub repository credentials template..."
cat > manifests/argocd/repository-credentials.yaml << EOF
# GitHub Repository Credentials for ArgoCD
# Update the GitHub token before applying

apiVersion: v1
kind: Secret
metadata:
  name: github-repo-credentials
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
  annotations:
    argocd.argoproj.io/sync-wave: "1"
type: Opaque
stringData:
  type: git
  url: https://github.com/traffic-tacos
  username: git
  password: GITHUB_TOKEN_HERE  # Replace with actual GitHub Personal Access Token
---
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-secret
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-webhook
  annotations:
    argocd.argoproj.io/sync-wave: "1"
type: Opaque
stringData:
  webhook.github.secret: WEBHOOK_SECRET_HERE  # Replace with actual webhook secret
EOF

# 8. Summary and next steps
echo ""
log_success "========================================="
log_success "    Configuration Complete"
log_success "========================================="
echo ""
log_info "Configuration Summary:"
echo "  AWS Account:     $AWS_ACCOUNT_ID"
echo "  Region:          $AWS_REGION"
echo "  Domain:          $DOMAIN_NAME"
echo "  ArgoCD URL:      https://$ARGOCD_SUBDOMAIN.$DOMAIN_NAME"
echo "  Certificate:     ${CERT_ARN:0:50}..."
echo "  Hosted Zone:     $HOSTED_ZONE_ID"
echo ""

if [[ "$CERT_ARN" == "MANUAL_SETUP_REQUIRED" ]]; then
    log_warning "MANUAL SETUP REQUIRED:"
    echo "  1. Create ACM certificate for *.$DOMAIN_NAME"
    echo "  2. Update certificate ARN in configuration files"
    echo ""
fi

if [[ "$HOSTED_ZONE_ID" == "MANUAL_SETUP_REQUIRED" ]]; then
    log_warning "MANUAL SETUP REQUIRED:"
    echo "  1. Create Route53 hosted zone for $DOMAIN_NAME"
    echo "  2. Update DNS settings with your domain registrar"
    echo ""
fi

log_info "REQUIRED MANUAL STEPS:"
echo "  1. Create GitHub Personal Access Token"
echo "  2. Update manifests/argocd/repository-credentials.yaml with actual token"
echo "  3. Review and customize helm-values/argocd-prod-values.yaml if needed"
echo ""

log_info "READY TO DEPLOY:"
echo "  ./deploy-argocd.sh validate    # Test configuration"
echo "  ./deploy-argocd.sh deploy      # Full deployment"
echo ""

# 9. Cleanup backup files
find . -name "*.bak" -type f -delete 2>/dev/null || true

log_success "Environment configuration completed!"
EOF