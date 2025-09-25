# Infrastructure Manifests

This directory contains Kubernetes manifests organized by namespace and component.

## Directory Structure

```
manifests/
├── argocd/                 # ArgoCD deployment manifests
│   ├── namespace.yaml      # Namespace and resource quotas
│   ├── ingress.yaml        # ArgoCD UI ingress with ALB
│   ├── network-policies.yaml
│   └── pod-security-policies.yaml
├── projects/               # ArgoCD Project definitions
│   └── traffic-tacos-project.yaml
├── applications/           # ArgoCD Application manifests
│   ├── gateway/
│   │   └── gateway-api.yaml
│   └── tacos/
│       ├── reservation-api.yaml
│       ├── inventory-api.yaml
│       ├── payment-sim-api.yaml
│       └── reservation-worker.yaml
└── shared/                 # Shared resources (RBAC, etc.)
    ├── rbac.yaml
    └── secrets.yaml
```

## Usage

Apply manifests using kubectl:

```bash
# Apply namespace first
kubectl apply -f manifests/argocd/namespace.yaml

# Apply ArgoCD core manifests
kubectl apply -f manifests/argocd/

# Apply projects and applications
kubectl apply -f manifests/projects/
kubectl apply -f manifests/applications/
```

## Conventions

- All resources include appropriate labels for tracking and cost allocation
- Resources follow Traffic Tacos naming conventions
- Manifests are validated before deployment
- Security policies are applied to all namespaces