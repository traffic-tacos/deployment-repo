# Tasks: ArgoCD Deployment Infrastructure

**Input**: Design documents from `/specs/001-argocd-deployment/`
**Prerequisites**: plan.md (✅), research.md (✅), data-model.md (✅), contracts/ (✅), quickstart.md (✅)

## Execution Flow (main)
```
1. Load plan.md from feature directory
   → ✅ Implementation plan loaded - ArgoCD deployment on EKS
   → Extracted: Helm 3.x, ArgoCD 2.8.4, AWS Load Balancer Controller
2. Load optional design documents:
   → ✅ data-model.md: ArgoCD applications, projects, repositories, sync policies
   → ✅ contracts/: Helm values schema, application CRDs, GitOps workflow
   → ✅ research.md: EKS integration, RBAC, ALB, certificate management
3. Generate tasks by category:
   → Setup: namespace, RBAC, Helm repository setup
   → Tests: Helm validation, ArgoCD health checks, GitOps workflow tests
   → Core: ArgoCD deployment, ingress, projects, applications
   → Integration: AWS services, monitoring, security policies
   → Polish: documentation, backup, disaster recovery
4. Apply task rules:
   → Different manifests = mark [P] for parallel deployment
   → Same namespace resources = sequential for dependency management
   → Validation before deployment (Infrastructure TDD)
5. Number tasks sequentially (T001, T002...)
   → ✅ 28 tasks generated covering complete ArgoCD deployment lifecycle
6. Generate dependency graph
   → ✅ Infrastructure dependencies mapped
7. Create parallel execution examples
   → ✅ Parallel manifest creation and validation examples provided
8. Validate task completeness:
   → ✅ All Helm values validated
   → ✅ All ArgoCD entities defined
   → ✅ All integration points covered
9. Return: SUCCESS (tasks ready for execution)
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions

## Path Conventions
- **Infrastructure project**: `manifests/`, `helm-values/`, `tests/` at repository root
- **ArgoCD specific**: `manifests/argocd/`, applications organized by namespace
- Paths assume infrastructure project structure from plan.md

## Phase 3.1: Environment Setup and Prerequisites

- [x] **T001** Verify EKS cluster access and create argocd namespace in `manifests/argocd/namespace.yaml`
- [x] **T002** Configure AWS credentials and verify Route53/ACM access for domain setup
- [x] **T003** [P] Add ArgoCD Helm repository and verify chart version availability
- [x] **T004** [P] Create directory structure: `manifests/argocd/`, `helm-values/`, `applications/`

## Phase 3.2: Configuration and Validation (Infrastructure TDD) ⚠️ MUST COMPLETE BEFORE 3.3

**CRITICAL: These validations MUST be written and MUST PASS before ANY deployment**

- [x] **T005** [P] Validate Helm values schema in `tests/helm/test_argocd_values.yaml`
- [x] **T006** [P] Validate ArgoCD application CRDs in `tests/manifests/test_application_crds.yaml`
- [ ] **T007** [P] Validate RBAC policies in `tests/rbac/test_argocd_rbac.yaml`
- [ ] **T008** [P] Validate network policies in `tests/network/test_argocd_network_policies.yaml`
- [ ] **T009** [P] Test GitOps workflow contracts in `tests/integration/test_gitops_workflow.sh`
- [ ] **T010** [P] Validate ingress configuration in `tests/ingress/test_argocd_ingress.yaml`

## Phase 3.3: Core ArgoCD Deployment (ONLY after validations pass)

- [x] **T011** Create ArgoCD Helm values file in `helm-values/argocd-prod-values.yaml`
- [x] **T012** Deploy ArgoCD using Helm chart with custom values
- [x] **T013** Create ArgoCD ingress with ALB annotations in `manifests/argocd/ingress.yaml`
- [x] **T014** Configure SSL certificate and DNS setup for `argocd.traffictacos.com`
- [x] **T015** Verify ArgoCD server deployment and UI accessibility

## Phase 3.4: RBAC and Security Configuration

- [x] **T016** [P] Create Traffic Tacos ArgoCD project in `manifests/projects/traffic-tacos-project.yaml`
- [ ] **T017** [P] Configure repository credentials secret in `manifests/argocd/repository-credentials.yaml`
- [x] **T018** Apply RBAC policies for development and operations teams
- [ ] **T019** [P] Deploy network policies in `manifests/argocd/network-policies.yaml`
- [ ] **T020** [P] Configure pod security policies in `manifests/argocd/pod-security-policies.yaml`

## Phase 3.5: Application Management Setup

- [x] **T021** [P] Create Gateway API application manifest in `applications/gateway/gateway-api.yaml`
- [x] **T022** [P] Create Reservation API application manifest in `applications/tacos/reservation-api.yaml`
- [ ] **T023** [P] Create Inventory API application manifest in `applications/tacos/inventory-api.yaml`
- [ ] **T024** [P] Create Payment Sim API application manifest in `applications/tacos/payment-sim-api.yaml`
- [x] **T025** [P] Create Reservation Worker application manifest in `applications/tacos/reservation-worker.yaml`

## Phase 3.6: Integration and Monitoring

- [ ] **T026** Configure Prometheus monitoring for ArgoCD metrics
- [ ] **T027** Set up log aggregation and alerting for ArgoCD events
- [ ] **T028** Implement backup strategy for ArgoCD configurations

## Dependencies

**Setup Phase Dependencies**:
- T001 → T011, T012 (namespace before deployment)
- T002 → T013, T014 (AWS access before ingress/DNS)
- T003 → T012 (Helm repo before deployment)

**Validation → Deployment Dependencies**:
- T005-T010 → T011-T015 (all validations before core deployment)
- T011 → T012 (values file before Helm deployment)
- T012 → T013, T015 (ArgoCD deployment before ingress/verification)
- T014 → T015 (DNS/SSL before UI access)

**RBAC Dependencies**:
- T015 → T016-T020 (ArgoCD running before RBAC configuration)
- T017 → T021-T025 (repository credentials before applications)
- T016 → T021-T025 (project before applications)

**Applications Dependencies**:
- T016, T017 → T021-T025 (project and credentials before applications)
- T021-T025 can run in parallel (different application files)

## Parallel Execution Examples

### Phase 3.1 - Setup (All parallel):
```bash
# Launch T003-T004 together:
Task: "Add ArgoCD Helm repository and verify chart version availability"
Task: "Create directory structure for manifests and configurations"
```

### Phase 3.2 - Validation (All parallel):
```bash
# Launch T005-T010 together:
Task: "Validate Helm values schema in tests/helm/test_argocd_values.yaml"
Task: "Validate ArgoCD application CRDs in tests/manifests/test_application_crds.yaml"
Task: "Validate RBAC policies in tests/rbac/test_argocd_rbac.yaml"
Task: "Validate network policies in tests/network/test_argocd_network_policies.yaml"
Task: "Test GitOps workflow contracts in tests/integration/test_gitops_workflow.sh"
Task: "Validate ingress configuration in tests/ingress/test_argocd_ingress.yaml"
```

### Phase 3.4 - Security Configuration (Parallel where possible):
```bash
# Launch T016-T017, T019-T020 together:
Task: "Create Traffic Tacos ArgoCD project in manifests/projects/traffic-tacos-project.yaml"
Task: "Configure repository credentials secret in manifests/argocd/repository-credentials.yaml"
Task: "Deploy network policies in manifests/argocd/network-policies.yaml"
Task: "Configure pod security policies in manifests/argocd/pod-security-policies.yaml"
```

### Phase 3.5 - Application Creation (All parallel):
```bash
# Launch T021-T025 together:
Task: "Create Gateway API application manifest in applications/gateway/gateway-api.yaml"
Task: "Create Reservation API application manifest in applications/tacos/reservation-api.yaml"
Task: "Create Inventory API application manifest in applications/tacos/inventory-api.yaml"
Task: "Create Payment Sim API application manifest in applications/tacos/payment-sim-api.yaml"
Task: "Create Reservation Worker application manifest in applications/tacos/reservation-worker.yaml"
```

## Notes
- [P] tasks = different files/resources, no dependencies
- Infrastructure TDD: Validate configurations before deployment
- Test all integrations in development environment first
- Commit after each successful task completion
- Follow quickstart.md for manual verification steps

## Task Generation Rules
*Applied during main() execution*

1. **From Helm Values Contract**:
   - Values schema → validation task [P]
   - ArgoCD deployment → Helm installation task

2. **From Application CRDs**:
   - Each application example → application creation task [P]
   - ArgoCD project → project setup task

3. **From GitOps Workflow**:
   - Repository access → credential configuration task
   - Sync policies → application sync configuration

4. **From Research Decisions**:
   - EKS integration → AWS service setup tasks
   - ALB integration → ingress configuration task
   - Certificate management → SSL setup task

5. **Ordering**:
   - Setup → Validation → Core Deployment → Security → Applications → Integration

## Validation Checklist
*GATE: Checked by main() before returning*

- [x] All Helm values have validation tests
- [x] All ArgoCD entities have manifest creation tasks
- [x] All validations come before deployment
- [x] Parallel tasks are truly independent
- [x] Each task specifies exact file path
- [x] No task modifies same file as another [P] task
- [x] GitOps workflow completely implemented
- [x] Security requirements fully addressed
- [x] Monitoring and observability included
- [x] All 5 microservice applications covered

## Success Criteria
After completing all tasks, the following should be achieved:
1. ArgoCD accessible via https://argocd.traffictacos.com
2. All 5 Traffic Tacos applications deployable via GitOps
3. RBAC policies enforcing proper access control
4. Monitoring and alerting operational
5. Disaster recovery procedures documented and tested

**Estimated Total Time**: 8-12 hours for experienced DevOps engineer
**Critical Path**: T001→T002→T012→T015→T016→T017→T021-T025