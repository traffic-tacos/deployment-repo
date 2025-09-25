# Research: ArgoCD Deployment on EKS

## Research Questions Addressed

### 1. ArgoCD Version Compatibility with EKS 1.33

**Decision**: ArgoCD v2.8.4 with Helm Chart v5.46.7
**Rationale**:
- Kubernetes 1.33 compatibility confirmed in ArgoCD compatibility matrix
- v2.8.4 includes critical security patches and EKS-specific improvements
- Helm chart v5.46.7 provides stable deployment patterns for EKS environments
- Active LTS support with regular security updates

**Alternatives considered**:
- ArgoCD v2.7.x: Lacks some EKS optimizations and has known security issues
- ArgoCD v2.9.x: Too bleeding edge, potential stability issues with EKS 1.33
- Manual YAML deployment: More complex to maintain than Helm-based approach

### 2. RBAC Best Practices for Multi-Namespace Environments

**Decision**: ArgoCD Projects with namespace-scoped RBAC and dedicated service accounts
**Rationale**:
- Projects provide logical isolation between application groups
- Service accounts enable fine-grained permissions per namespace
- Principle of least privilege enforced through RBAC policies
- Audit trail maintained for all deployment actions

**Configuration**:
```yaml
# Application Project for Traffic Tacos microservices
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: traffic-tacos
  namespace: argocd
spec:
  destinations:
  - namespace: gateway
    server: https://kubernetes.default.svc
  - namespace: tacos
    server: https://kubernetes.default.svc
  sourceRepos:
  - 'https://github.com/traffic-tacos/*'
  roles:
  - name: dev-team
    policies:
    - p, proj:traffic-tacos:dev-team, applications, sync, traffic-tacos/*, allow
    - p, proj:traffic-tacos:dev-team, applications, get, traffic-tacos/*, allow
```

**Alternatives considered**:
- Cluster-admin permissions: Too broad, violates least privilege principle
- Single service account: Lacks granular control for different teams/services
- Kubernetes native RBAC only: More complex to manage than ArgoCD Projects

### 3. AWS Load Balancer Controller Integration

**Decision**: ALB Ingress with SSL termination and path-based routing
**Rationale**:
- Native AWS integration provides better performance and cost optimization
- SSL termination at load balancer level reduces cluster TLS overhead
- Path-based routing enables single ALB for multiple services
- Integration with AWS Certificate Manager for automated certificate management

**Configuration Pattern**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
spec:
  tls:
  - hosts:
    - argocd.traffictacos.com
  rules:
  - host: argocd.traffictacos.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

**Alternatives considered**:
- NGINX Ingress Controller: Requires additional cluster resources and management
- Service LoadBalancer: More expensive, less integration with AWS services
- ClusterIP with port-forward: Not suitable for production multi-user access

### 4. Certificate Management for ArgoCD

**Decision**: AWS Certificate Manager with automatic DNS validation
**Rationale**:
- Automated certificate lifecycle management (issuance, renewal)
- DNS validation eliminates need for HTTP challenges
- Native integration with ALB and Route53
- No manual certificate management overhead

**Implementation**:
- ACM certificate for `argocd.traffictacos.com` subdomain
- Route53 DNS validation records automatically managed
- ALB automatically uses ACM certificate for TLS termination
- Certificate renewal handled transparently by AWS

**Alternatives considered**:
- cert-manager with Let's Encrypt: Additional cluster complexity and ACME challenges
- Manual certificate management: Operational overhead and expiration risks
- Self-signed certificates: Not suitable for production multi-user environment

## Architecture Decisions

### High Availability Configuration
- ArgoCD server: 2 replicas with anti-affinity rules
- Redis HA: 3 replicas for clustering and sentinel configuration
- Application controller: Single replica (active/standby not supported)
- Repository server: 2 replicas for improved Git operations performance

### Resource Allocation Strategy
```yaml
# Based on 30k RPS microservices platform requirements
argocd-server:
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

argocd-application-controller:
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

argocd-repo-server:
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### Security Hardening
- Pod Security Standards: Restricted profile enforcement
- Network Policies: Ingress/egress traffic control
- Service Account: Dedicated SA with minimal required permissions
- Image Security: Official ArgoCD images with security scanning
- Secrets Management: Kubernetes secrets with encryption at rest

## Integration Points

### Git Repository Access
- SSH keys for private repository access
- Repository credentials stored as Kubernetes secrets
- Git webhook configuration for automated sync triggers
- Branch protection and access control via Git provider RBAC

### Monitoring and Observability
- Prometheus metrics endpoint exposure
- Custom dashboards for ArgoCD application health
- Alert rules for sync failures and deployment issues
- Integration with existing Traffic Tacos observability stack

### Backup and Disaster Recovery
- ArgoCD configuration backup via Git (GitOps for GitOps)
- Application state backup through persistent volume snapshots
- Disaster recovery procedures documented in runbooks
- RTO: 15 minutes, RPO: 5 minutes for critical configurations

## Performance Considerations

### Sync Performance Optimization
- Parallel sync operations for independent applications
- Resource inclusion/exclusion patterns for efficient syncing
- Git repository caching and shallow clones
- Application refresh intervals tuned for 30k RPS change frequency

### Scalability Limits
- Maximum applications per ArgoCD instance: ~1000 (well above our 5 microservices)
- Git repository operations: Optimized for frequent updates
- UI performance: Acceptable with current scale and resource allocation
- Database performance: Redis HA provides sufficient throughput

This research provides the foundation for Phase 1 design and implementation planning.