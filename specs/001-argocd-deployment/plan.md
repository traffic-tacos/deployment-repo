# Implementation Plan: ArgoCD Deployment Infrastructure

**Branch**: `001-argocd-deployment` | **Date**: 2025-09-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-argocd-deployment/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → ✅ Feature spec loaded from /specs/001-argocd-deployment/spec.md
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → ✅ Project Type detected: Infrastructure (Kubernetes deployment)
   → ✅ Structure Decision set for Infrastructure project type
3. Fill the Constitution Check section based on the content of the constitution document.
   → ✅ Constitution v1.0.0 requirements applied
4. Evaluate Constitution Check section below
   → ✅ All constitutional requirements aligned
   → ✅ Progress Tracking: Initial Constitution Check PASS
5. Execute Phase 0 → research.md
   → ✅ Research completed for ArgoCD best practices and EKS integration
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, CLAUDE.md
   → ✅ Helm values schema, GitOps workflow contracts, and quickstart guide generated
7. Re-evaluate Constitution Check section
   → ✅ No new constitutional violations detected
   → ✅ Progress Tracking: Post-Design Constitution Check PASS
8. Plan Phase 2 → Task generation approach described
   → ✅ Ready for /tasks command execution
9. STOP - Ready for /tasks command
   → ✅ /plan command execution complete
```

## Summary
Deploy ArgoCD as the GitOps control plane in the dedicated argocd namespace to manage Traffic Tacos microservices deployments. The implementation will use Helm charts with EKS integration, RBAC policies, and automated sync capabilities to support 30k RPS microservices platform requirements.

## Technical Context
**Language/Version**: Helm 3.x, Kubernetes 1.33+
**Primary Dependencies**: ArgoCD 2.8+, AWS Load Balancer Controller, cert-manager
**Storage**: EKS persistent volumes, Git repositories for manifests
**Testing**: Helm lint, ArgoCD health checks, kubectl dry-run validation
**Target Platform**: Amazon EKS cluster (ticket-cluster) in ap-northeast-2
**Project Type**: Infrastructure - Kubernetes deployment manifests and Helm charts
**Performance Goals**: Support GitOps operations for 30k RPS microservices platform
**Constraints**: argocd namespace isolation, RBAC compliance, certificate management
**Scale/Scope**: 5 microservices across 3 namespaces (argocd, gateway, tacos)

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**✅ GitOps-First Deployment**: ArgoCD serves as the central GitOps control plane
**✅ Namespace Isolation**: Deployed exclusively in argocd namespace
**✅ Helm Chart Standardization**: Uses official ArgoCD Helm chart with standardized values
**✅ AWS Integration**: Integrates with EKS cluster using tacos AWS profile
**✅ Performance Standards**: Designed to support 30k RPS microservices management
**✅ Security Requirements**: RBAC, TLS, Pod Security Standards compliance
**✅ Mandatory Security Controls**: Network policies, restricted security contexts
**✅ Observability**: Prometheus metrics, health checks, distributed tracing support

**Constitutional Compliance**: ✅ PASS - All requirements satisfied

## Project Structure

### Documentation (this feature)
```
specs/001-argocd-deployment/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
│   ├── argocd-values.yaml    # Helm values schema
│   ├── application-crd.yaml  # ArgoCD Application CRD examples
│   └── gitops-workflow.md    # GitOps workflow contracts
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
# Infrastructure project structure
manifests/
├── argocd/
│   ├── namespace.yaml
│   ├── helm-values/
│   │   ├── dev-values.yaml
│   │   ├── staging-values.yaml
│   │   └── prod-values.yaml
│   └── applications/
│       ├── gateway-app.yaml
│       └── tacos-apps.yaml
├── gateway/
└── tacos/

helm-charts/
├── argocd-config/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── custom-applications/
```

**Structure Decision**: Infrastructure project - Kubernetes manifests and Helm charts organization

## Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - ArgoCD version compatibility with EKS 1.33
   - Best practices for ArgoCD RBAC in multi-namespace environments
   - Integration patterns with AWS Load Balancer Controller
   - Certificate management strategies for ArgoCD UI/API

2. **Generate and dispatch research agents**:
   ```
   Task: "Research ArgoCD 2.8+ compatibility with EKS 1.33 and best version selection"
   Task: "Find best practices for ArgoCD RBAC configuration in multi-namespace EKS environments"
   Task: "Research ArgoCD integration patterns with AWS Load Balancer Controller"
   Task: "Find certificate management best practices for ArgoCD in EKS environments"
   ```

3. **Consolidate findings** in `research.md`:
   - Decision: ArgoCD version and deployment method
   - Rationale: EKS compatibility and feature requirements
   - Alternatives considered: Helm vs. manifest deployment, ingress options

**Output**: research.md with all technical decisions resolved

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - ArgoCD Application (name, source repo, target namespace, sync policy)
   - Git Repository (URL, credentials, branch/tag patterns)
   - Sync Policy (automated vs manual, self-heal, prune policies)
   - Application Project (RBAC boundaries, resource restrictions)

2. **Generate Helm contracts** from functional requirements:
   - ArgoCD Helm values schema defining all configuration options
   - Application manifest templates for microservices
   - RBAC policy templates for service accounts
   - Output structured values to `/contracts/`

3. **Generate validation tests** from contracts:
   - Helm chart validation tests (helm lint, template validation)
   - ArgoCD application health check scenarios
   - RBAC permission verification tests
   - Tests must fail until implementation complete

4. **Extract deployment scenarios** from user stories:
   - GitOps sync workflow integration test
   - Multi-namespace application deployment test
   - Rollback and recovery scenario validation

5. **Update CLAUDE.md incrementally**:
   - Add ArgoCD deployment context and best practices
   - Include EKS integration patterns and troubleshooting
   - Preserve existing Traffic Tacos context
   - Keep focused on current implementation needs

**Output**: data-model.md, /contracts/*, failing tests, quickstart.md, CLAUDE.md

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from ArgoCD deployment requirements
- Each Helm values configuration → validation task [P]
- Each RBAC policy → permission verification task [P]
- Each application template → deployment test task
- Integration tasks for EKS and AWS Load Balancer Controller

**Ordering Strategy**:
- Infrastructure first: Namespace creation, RBAC setup
- Core deployment: ArgoCD Helm chart installation
- Configuration: Values files, application projects
- Integration: AWS services, certificate management
- Validation: Health checks, GitOps workflow testing
- Mark [P] for parallel execution (independent configurations)

**Estimated Output**: 20-25 numbered, ordered tasks in tasks.md

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Implementation (execute tasks.md following constitutional principles)
**Phase 5**: Validation (ArgoCD health checks, GitOps workflow validation, performance testing)

## Complexity Tracking
*No constitutional violations detected - section left empty*

## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented (none required)

---
*Based on Constitution v1.0.0 - See `.specify/memory/constitution.md`*