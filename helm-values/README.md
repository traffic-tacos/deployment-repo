# Helm Values Configuration

This directory contains environment-specific Helm values files for Traffic Tacos deployments.

## Structure

```
helm-values/
├── argocd-prod-values.yaml     # Production ArgoCD configuration
├── argocd-dev-values.yaml      # Development ArgoCD configuration
├── gateway-api/                # Gateway API Helm values
│   ├── prod-values.yaml
│   ├── staging-values.yaml
│   └── dev-values.yaml
└── microservices/              # Microservices Helm values
    ├── reservation-api/
    ├── inventory-api/
    ├── payment-sim-api/
    └── reservation-worker/
```

## Environment Configuration

### Production (`*-prod-values.yaml`)
- High availability configurations
- Production resource limits
- SSL/TLS enforcement
- Monitoring and alerting enabled
- Backup and disaster recovery

### Staging (`*-staging-values.yaml`)
- Production-like configuration
- Lower resource limits
- Testing and validation focus
- Integration with CI/CD pipelines

### Development (`*-dev-values.yaml`)
- Minimal resource usage
- Development-friendly settings
- Local development support
- Debug mode enabled

## Usage

```bash
# Deploy with specific values file
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values helm-values/argocd-prod-values.yaml

# Override specific values
helm upgrade --install app ./chart \
  --values helm-values/app/prod-values.yaml \
  --set image.tag=v1.2.3
```

## Security Notes

- Sensitive values should use Kubernetes secrets
- Never commit credentials or API keys
- Use sealed-secrets or external-secrets for production
- Regular rotation of access tokens and certificates