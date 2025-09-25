# ArgoCD Deployment Quickstart Guide

This guide provides step-by-step instructions for deploying ArgoCD in the Traffic Tacos EKS environment.

## Prerequisites

Before starting, ensure you have:

- [ ] EKS cluster `ticket-cluster` running in `ap-northeast-2`
- [ ] `kubectl` configured with access to the EKS cluster
- [ ] Helm 3.x installed locally
- [ ] AWS CLI configured with `tacos` profile
- [ ] Domain `traffictacos.com` configured in Route53
- [ ] ACM certificate issued for `argocd.traffictacos.com`

## Quick Verification

Verify your environment setup:

```bash
# Check EKS cluster access
kubectl cluster-info

# Check AWS profile
aws sts get-caller-identity --profile tacos

# Check Helm installation
helm version

# Verify namespace creation capability
kubectl auth can-i create namespaces
```

Expected output: All commands should complete successfully.

## Step 1: Prepare Namespace and RBAC

Create the ArgoCD namespace and required RBAC:

```bash
# Create argocd namespace
kubectl create namespace argocd

# Label namespace for monitoring
kubectl label namespace argocd name=argocd
kubectl label namespace argocd app.kubernetes.io/name=argocd
```

## Step 2: Add ArgoCD Helm Repository

Add and update the ArgoCD Helm repository:

```bash
# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm

# Update repository cache
helm repo update

# Verify repository
helm search repo argo/argo-cd
```

Expected output: ArgoCD chart version 5.46.7 or later should be available.

## Step 3: Configure Values File

Create the ArgoCD values file:

```bash
# Create values directory
mkdir -p helm-values

# Copy the values template
cp specs/001-argocd-deployment/contracts/argocd-values.yaml helm-values/argocd-prod-values.yaml
```

Update the values file with your specific configuration:

```yaml
# Update these values in helm-values/argocd-prod-values.yaml
global:
  domain: argocd.traffictacos.com  # Your actual domain

server:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: ${YOUR_ACM_CERTIFICATE_ARN}
    hosts:
      - argocd.traffictacos.com  # Your actual domain
    tls:
      - secretName: argocd-server-tls
        hosts:
          - argocd.traffictacos.com
```

## Step 4: Deploy ArgoCD

Install ArgoCD using Helm:

```bash
# Deploy ArgoCD with custom values
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values helm-values/argocd-prod-values.yaml \
  --version 5.46.7 \
  --wait \
  --timeout 10m

# Verify deployment
kubectl get pods -n argocd
kubectl get svc -n argocd
kubectl get ingress -n argocd
```

Expected output: All ArgoCD pods should be in `Running` state.

## Step 5: Access ArgoCD UI

### Option A: Through ALB (Recommended)

1. Wait for ALB to be provisioned:
```bash
# Check ALB creation status
kubectl get ingress argocd-server-ingress -n argocd

# Get ALB DNS name
kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

2. Update Route53 DNS (if not automated):
```bash
# Create Route53 record pointing to ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id ${YOUR_HOSTED_ZONE_ID} \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "argocd.traffictacos.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$(kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')'"} ]
      }
    }]
  }'
```

3. Access ArgoCD UI:
```bash
# Open ArgoCD UI in browser
open https://argocd.traffictacos.com
```

### Option B: Through Port Forward (Development)

```bash
# Port forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Access ArgoCD UI
open https://localhost:8080
```

## Step 6: Get Initial Admin Password

Retrieve the initial admin password:

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

Login with:
- Username: `admin`
- Password: (output from command above)

## Step 7: Create Traffic Tacos Project

Create the ArgoCD project for Traffic Tacos applications:

```bash
# Apply the Traffic Tacos project
kubectl apply -f specs/001-argocd-deployment/contracts/application-crd.yaml
```

This creates:
- Traffic Tacos project with appropriate permissions
- RBAC policies for development and operations teams

## Step 8: Configure Repository Access

Add GitHub repository credentials:

```bash
# Create GitHub access token secret
kubectl create secret generic github-token \
  --from-literal=url=https://github.com/traffic-tacos \
  --from-literal=username=git \
  --from-literal=password=${GITHUB_TOKEN} \
  --namespace argocd

# Label the secret for ArgoCD
kubectl label secret github-token -n argocd argocd.argoproj.io/secret-type=repository
```

## Step 9: Deploy First Application

Deploy the Gateway API application as a test:

```bash
# Extract Gateway API application from contracts
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gateway-api
  namespace: argocd
spec:
  project: traffic-tacos
  source:
    repoURL: https://github.com/traffic-tacos/gateway-api
    targetRevision: main
    path: k8s/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: gateway
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

## Step 10: Verify Deployment

Check ArgoCD application status:

```bash
# Check application status
kubectl get applications -n argocd

# Check application details
kubectl describe application gateway-api -n argocd

# Check target namespace
kubectl get pods -n gateway
```

Expected output: Application should show as `Healthy` and `Synced`.

## Step 11: Configure Monitoring

Set up monitoring for ArgoCD:

```bash
# Verify metrics endpoint
kubectl port-forward svc/argocd-metrics -n argocd 8082:8082 &
curl http://localhost:8082/metrics

# Check for ServiceMonitor (if Prometheus Operator is installed)
kubectl get servicemonitor -n argocd
```

## Validation Checklist

After deployment, verify these items:

- [ ] ArgoCD UI accessible via https://argocd.traffictacos.com
- [ ] Admin login successful with retrieved password
- [ ] Traffic Tacos project visible in UI
- [ ] GitHub repository connection successful
- [ ] Gateway API application deployed and healthy
- [ ] ArgoCD metrics endpoint responding
- [ ] All pods in argocd namespace running
- [ ] ALB health checks passing

## Troubleshooting

### Common Issues

**Issue**: ArgoCD UI not accessible
```bash
# Check ingress status
kubectl describe ingress argocd-server-ingress -n argocd

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Issue**: Application sync failing
```bash
# Check application events
kubectl describe application gateway-api -n argocd

# Check ArgoCD server logs
kubectl logs deployment/argocd-server -n argocd
```

**Issue**: Repository connection failed
```bash
# Check repository secret
kubectl get secret github-token -n argocd -o yaml

# Test repository access
kubectl exec -n argocd deployment/argocd-repo-server -- \
  git ls-remote https://github.com/traffic-tacos/gateway-api
```

### Log Collection

Collect ArgoCD logs for support:

```bash
# Collect all ArgoCD component logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server > argocd-server.log
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller > argocd-controller.log
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server > argocd-repo.log
```

## Next Steps

After successful ArgoCD deployment:

1. **Configure OIDC/SSO**: Set up authentication with your identity provider
2. **Deploy remaining applications**: Add reservation-api, inventory-api, payment-sim-api, and reservation-worker
3. **Set up monitoring**: Configure alerts and dashboards for ArgoCD metrics
4. **Implement backup**: Set up regular backups of ArgoCD configuration
5. **Configure webhooks**: Set up Git webhooks for faster sync times

## Security Hardening

Additional security steps for production:

```bash
# Disable admin user after OIDC setup
kubectl patch configmap argocd-cmd-params-cm -n argocd --patch '{"data":{"server.disable.admin":"true"}}'

# Enable audit logging
kubectl patch configmap argocd-server-config -n argocd --patch '{"data":{"server.audit.enabled":"true"}}'

# Set up network policies
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-network-policy
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: argocd
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - {}
EOF
```

This quickstart guide provides a complete deployment path for ArgoCD in the Traffic Tacos environment. Follow the validation checklist to ensure a successful deployment.