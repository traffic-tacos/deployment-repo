# ArgoCD Applications

This directory contains ArgoCD Application manifests for Traffic Tacos microservices.

## Structure

```
applications/
├── gateway/                    # Gateway namespace applications
│   └── gateway-api.yaml       # Gateway API service
└── tacos/                     # Tacos namespace applications
    ├── reservation-api.yaml   # Reservation management service
    ├── inventory-api.yaml     # Inventory management service
    ├── payment-sim-api.yaml   # Payment simulation service
    └── reservation-worker.yaml # Background job processor
```

## Application Naming Convention

Applications follow the naming pattern: `{service-name}` in their respective namespaces.

## Repository Structure Expected

Each application expects the following structure in its source repository:

```
{service-repository}/
├── k8s/
│   ├── manifests/              # Kubernetes manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml (optional)
│   │   └── configmap.yaml (optional)
│   ├── values-prod.yaml        # Production Helm values
│   ├── values-staging.yaml     # Staging Helm values
│   └── values-dev.yaml         # Development Helm values
└── Chart.yaml (if using Helm)
```

## Sync Policies

### Automatic Sync (Production)
- `prune: true` - Remove resources not in Git
- `selfHeal: true` - Revert manual changes
- Retry mechanism with exponential backoff

### Deployment Windows
- Production deployments: Business hours (9-17 KST, Mon-Fri)
- Development/Staging: 24/7 automatic sync

## Health Checks

All applications must expose health check endpoints:
- `/health/live` - Liveness probe
- `/health/ready` - Readiness probe
- `/health/startup` - Startup probe

## Rollback Strategy

- ArgoCD maintains 10 revision history per application
- Rollback via ArgoCD UI or CLI
- Emergency rollback: `argocd app rollback {app-name} {revision}`

## Monitoring

Applications are monitored for:
- Sync status and health
- Deployment duration
- Resource utilization
- Error rates and availability