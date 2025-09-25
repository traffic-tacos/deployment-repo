# Data Model: ArgoCD Deployment Infrastructure

## Core Entities

### 1. ArgoCD Application
Represents a deployed microservice managed by ArgoCD with its configuration and lifecycle.

**Attributes**:
- `name`: Unique identifier for the application (e.g., "gateway-api", "reservation-api")
- `namespace`: Target deployment namespace ("gateway" or "tacos")
- `source.repoURL`: Git repository URL containing the application manifests
- `source.path`: Path within the repository to the application manifests
- `source.targetRevision`: Git branch, tag, or commit to deploy (e.g., "main", "v1.2.3")
- `destination.server`: Kubernetes cluster API server URL
- `destination.namespace`: Target namespace for deployment
- `project`: ArgoCD project for RBAC and resource restrictions
- `syncPolicy.automated`: Boolean indicating automatic sync enablement
- `syncPolicy.selfHeal`: Boolean for automatic drift correction
- `syncPolicy.prune`: Boolean for removing resources not in Git

**Validation Rules**:
- `name` must be unique within ArgoCD instance
- `namespace` must exist in destination cluster
- `source.repoURL` must be accessible with configured credentials
- `destination.server` must match EKS cluster endpoint
- `project` must exist and grant permissions to target namespace

**State Transitions**:
```
OutOfSync → Syncing → Healthy
         → Syncing → Degraded → (Manual intervention)
Healthy → OutOfSync (on Git changes or cluster drift)
```

### 2. Git Repository
Source of truth containing application manifests and configuration.

**Attributes**:
- `url`: Repository URL (HTTPS or SSH format)
- `credentials`: Authentication method (SSH key, username/password, token)
- `type`: Repository type ("git", "helm", "oci")
- `project`: Associated ArgoCD project for access control
- `connectionState`: Current connectivity status ("successful", "failed")

**Relationships**:
- One repository can contain multiple applications (monorepo pattern)
- Each application references exactly one repository
- Repository credentials are shared across applications using the same repo

### 3. Sync Policy
Rules defining how and when applications synchronize from Git to cluster.

**Attributes**:
- `automated`: Enable automatic synchronization on Git changes
- `selfHeal`: Automatically revert manual changes to match Git state
- `prune`: Remove resources not present in Git repository
- `syncOptions`: Advanced sync behaviors (e.g., "CreateNamespace=true")
- `retry.limit`: Maximum number of sync retry attempts
- `retry.backoff`: Retry interval and exponential backoff configuration

**Business Rules**:
- Production applications should have `selfHeal=true` for consistency
- Development environments may use `automated=false` for manual control
- `prune=true` recommended for complete GitOps compliance

### 4. Application Project
Logical grouping of applications with shared RBAC policies and resource restrictions.

**Attributes**:
- `name`: Project identifier (e.g., "traffic-tacos", "platform-tools")
- `description`: Human-readable project description
- `sourceRepos`: List of allowed Git repositories
- `destinations`: List of allowed cluster/namespace combinations
- `clusterResourceWhitelist`: Allowed cluster-scoped resource types
- `namespaceResourceWhitelist`: Allowed namespace-scoped resource types
- `roles`: RBAC roles with permissions for project resources

**Validation Rules**:
- Applications can only be created within project boundaries
- Source repositories must be explicitly allowed
- Destination clusters and namespaces must be pre-approved
- Resource types must be whitelisted for security

### 5. Repository Credentials
Secure authentication information for accessing private Git repositories.

**Attributes**:
- `url`: Repository URL pattern for credential matching
- `username`: Username for HTTPS authentication (optional)
- `password`: Password or access token for HTTPS authentication
- `sshPrivateKey`: Private key for SSH authentication
- `tlsClientCertData`: Client certificate for TLS authentication
- `type`: Credential type ("git", "helm", "oci")

**Security Rules**:
- Stored as Kubernetes secrets with restricted access
- SSH keys preferred over passwords for better security
- Token-based authentication preferred over username/password
- Regular credential rotation enforced through policies

## Entity Relationships

```
Application Project (1) ←→ (N) ArgoCD Application
ArgoCD Application (N) ←→ (1) Git Repository
Git Repository (1) ←→ (1) Repository Credentials
ArgoCD Application (1) ←→ (1) Sync Policy
```

## Data Flow Patterns

### 1. Application Creation Flow
```
1. Define Application Project with allowed repositories and destinations
2. Configure Repository Credentials for Git access
3. Create ArgoCD Application with reference to project and repository
4. Define Sync Policy for application lifecycle management
5. ArgoCD validates application against project restrictions
6. Initial sync deploys application to target namespace
```

### 2. GitOps Sync Flow
```
1. Git repository receives new commits
2. ArgoCD detects changes through polling or webhooks
3. Sync Policy evaluates whether automatic sync is enabled
4. ArgoCD pulls latest manifests from Git repository
5. Kubernetes resources are applied/updated in target namespace
6. Application status updated based on resource health
```

### 3. Drift Detection Flow
```
1. ArgoCD continuously monitors deployed resources
2. Resource changes detected through Kubernetes watch API
3. Drift comparison performed against Git source of truth
4. If selfHeal enabled, automatic revert to Git state
5. If selfHeal disabled, OutOfSync status reported
```

## Configuration Schema

### ArgoCD Application Manifest
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {APPLICATION_NAME}
  namespace: argocd
spec:
  project: traffic-tacos
  source:
    repoURL: https://github.com/traffic-tacos/{SERVICE_NAME}
    targetRevision: main
    path: k8s/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: {TARGET_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m0s
```

### Application Project Schema
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: traffic-tacos
  namespace: argocd
spec:
  description: Traffic Tacos microservices platform
  sourceRepos:
  - 'https://github.com/traffic-tacos/*'
  destinations:
  - namespace: gateway
    server: https://kubernetes.default.svc
  - namespace: tacos
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  namespaceResourceWhitelist:
  - group: ''
    kind: '*'
  - group: 'apps'
    kind: '*'
  - group: 'networking.k8s.io'
    kind: '*'
```

This data model provides the foundation for ArgoCD application management within the Traffic Tacos platform architecture.