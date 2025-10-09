# 보안 모범 사례 가이드 (Security Best Practices)

## 📋 목차

1. [개요](#개요)
2. [Public Repository 보안 점검](#public-repository-보안-점검)
3. [발견된 민감 정보 분석](#발견된-민감-정보-분석)
4. [권장 조치사항](#권장-조치사항)
5. [Secrets 관리 전략](#secrets-관리-전략)
6. [보안 체크리스트](#보안-체크리스트)
7. [참고 자료](#참고-자료)

---

## 개요

이 문서는 Traffic Tacos Deployment Repository의 보안 모범 사례를 정리한 가이드입니다. Public GitHub Repository에서 민감한 정보 유출을 방지하고, Kubernetes 환경에서 안전한 Secrets 관리 방법을 제시합니다.

### 보안 원칙

1. **최소 권한 원칙 (Least Privilege)**: 필요한 최소한의 권한만 부여
2. **Defense in Depth**: 다층 보안 방어 체계 구축
3. **Secrets 분리**: 코드와 인증 정보 완전 분리
4. **감사 가능성 (Auditability)**: 모든 접근 로그 기록
5. **Zero Trust**: 네트워크 위치와 무관한 인증/인가

---

## Public Repository 보안 점검

### 점검 일자

**최초 점검**: 2025-10-09  
**점검자**: Traffic Tacos Team  
**Repository**: [traffic-tacos/deployment-repo](https://github.com/traffic-tacos/deployment-repo)

### 점검 방법

```bash
# 1. AWS Account ID 검색
grep -r "137406935518\|AWS_ACCOUNT" . --include="*.yaml" --include="*.md"

# 2. Secret/Password 키워드 검색
grep -ri "password\|secret\|token\|key\|credential" . --include="*.yaml" --include="*.md"

# 3. IAM Role ARN 검색
grep -r "arn:aws:iam::" . --include="*.yaml" --include="*.md"

# 4. 실제 credential 파일 검색
find . -name "*.pem" -o -name "*.key" -o -name "*credentials*" -o -name ".env"
```

---

## 발견된 민감 정보 분석

### 🔴 높은 위험 (High Risk)

#### 1. AWS Account ID 노출

**발견 위치**: 36곳
- README.md (4곳)
- ECR Image URLs (모든 deployment.yaml)
- IAM Role ARNs (모든 serviceaccount.yaml)
- SQS Queue URLs
- ACM Certificate ARNs

**노출된 Account ID**: `137406935518`

**위험도**: 🔴 **높음**

**위험 시나리오**:
- 공격자가 AWS Account를 타겟팅할 수 있는 기반 정보 제공
- 인프라 구조 및 리소스 이름 추론 가능
- Phishing 공격 시 정확한 Account 정보로 신뢰도 증가

**영향 범위**:
- ✅ **직접적인 접근 불가능**: Account ID만으로는 AWS 리소스 접근 불가
- ⚠️ **정찰 정보 제공**: 공격자가 인프라 구조 파악 가능
- ⚠️ **타겟팅 공격 위험**: Account 기반 맞춤형 공격 가능

#### 2. ACM Certificate ARN

```yaml
# applications/gateway/gateway.yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: 
  "arn:aws:acm:ap-northeast-2:137406935518:certificate/467dbda7-edf0-44b7-9381-833f74dc554b"
```

**위험도**: 🟡 **중간**

**분석**:
- Certificate는 본질적으로 공개 정보 (HTTPS 인증서)
- 하지만 Certificate ID를 통해 인프라 구조 추론 가능
- IAM 권한 없이는 Certificate 자체 접근 불가

#### 3. SQS Queue URL

```yaml
# manifests/reservation-worker/deployment.yaml
env:
- name: SQS_QUEUE_URL
  value: https://sqs.ap-northeast-2.amazonaws.com/137406935518/traffic-tacos-reservation-events
```

**위험도**: 🟡 **중간**

**분석**:
- Queue 이름과 구조 노출
- IAM 정책 없이는 Queue 접근 불가
- DDOS 타겟 정보로 활용 가능성

### 🟢 낮은 위험 (Low Risk)

#### 4. Secret 참조 (실제 값 없음)

```yaml
# manifests/gateway-api/deployment.yaml
env:
- name: JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: gateway-api-secrets
      key: jwt-secret
```

**위험도**: 🟢 **낮음**

**분석**:
- Secret 이름만 노출, 실제 값은 Kubernetes Secret에 저장
- Kubernetes RBAC으로 접근 제어
- 클러스터 외부에서 접근 불가

#### 5. IAM Role ARN

```yaml
# manifests/gateway-api/serviceaccount.yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::137406935518:role/traffic-tacos-gateway-api-sa-role
```

**위험도**: 🟢 **낮음**

**분석**:
- IRSA (IAM Roles for Service Accounts) 기반
- EKS 클러스터 내부 Pod에서만 사용 가능
- ServiceAccount Token 필요 (외부에서 획득 불가)
- Trust Policy로 특정 클러스터/네임스페이스만 허용

#### 6. 도메인 정보

- `traffictacos.store`
- `api.traffictacos.store`
- `www.traffictacos.store`

**위험도**: 🟢 **낮음 (Public 정보)**

**분석**:
- DNS는 본질적으로 공개 정보
- 문제 없음

### ✅ 안전 (Safe)

#### 7. 실제 Credential 파일 검사

**검사 결과**:
```bash
# 실제 credential 파일 검색 결과
$ find . -name "*.pem" -o -name "*.key" -o -name "*credentials*" -o -name ".env"
# (결과 없음)
```

**.gitignore 설정 확인**:
```gitignore
# Kubernetes secrets (real credentials)
*secret*.yaml
*credentials*.yaml
!*-template.yaml

# Environment-specific files
.env.deployment
*.env
```

**결론**: ✅ **실제 credential은 Git에 포함되지 않음**

---

## 권장 조치사항

### Phase 1: 즉시 조치 (High Priority)

#### 1.1 README.md에서 AWS Account ID 마스킹

**현재 (문제)**:
```markdown
- **AWS Account**: 137406935518
```

**수정 후**:
```markdown
- **AWS Account**: `<YOUR_AWS_ACCOUNT_ID>`
```

**수정 위치**:
- README.md 라인 901
- README.md 예제 코드 섹션 (라인 657)

#### 1.2 예제 코드에서 Account ID 플레이스홀더 사용

**현재**:
```yaml
env:
- name: AWS_ROLE_ARN
  value: arn:aws:iam::137406935518:role/traffic-tacos-gateway-api-sa-role
```

**권장**:
```yaml
env:
- name: AWS_ROLE_ARN
  value: arn:aws:iam::<AWS_ACCOUNT_ID>:role/traffic-tacos-gateway-api-sa-role
```

### Phase 2: 중기 조치 (Medium Priority)

#### 2.1 Kustomize를 통한 환경별 설정 분리

**디렉토리 구조**:
```
manifests/
├── base/                    # Base manifests (no account ID)
│   ├── gateway-api/
│   │   ├── deployment.yaml  # Placeholder 사용
│   │   └── kustomization.yaml
│   └── ...
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

**base/gateway-api/deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway-api
spec:
  template:
    spec:
      containers:
      - name: gateway-api
        image: <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/traffic-tacos-gateway-api:latest
        env:
        - name: AWS_ROLE_ARN
          value: arn:aws:iam::<AWS_ACCOUNT_ID>:role/traffic-tacos-gateway-api-sa-role
```

**overlays/prod/kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base/gateway-api

replacements:
- source:
    kind: ConfigMap
    name: env-config
    fieldPath: data.AWS_ACCOUNT_ID
  targets:
  - select:
      kind: Deployment
      name: gateway-api
    fieldPaths:
    - spec.template.spec.containers.[name=gateway-api].image
    - spec.template.spec.containers.[name=gateway-api].env.[name=AWS_ROLE_ARN].value

configMapGenerator:
- name: env-config
  literals:
  - AWS_ACCOUNT_ID=137406935518
```

**장점**:
- Base 매니페스트를 Public Repository에 안전하게 공개 가능
- Overlay는 Private Repository 또는 CI/CD에서만 관리
- 환경별 설정 명확히 분리

#### 2.2 ArgoCD에서 런타임 변수 주입

**ArgoCD Application 설정**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gateway-api-app
spec:
  source:
    helm:
      parameters:
      - name: aws.accountId
        value: $ARGOCD_APP_NAMESPACE  # ArgoCD가 자동 주입
    kustomize:
      commonAnnotations:
        aws-account-id: "137406935518"  # Private repo에만 저장
```

### Phase 3: 장기 조치 (Best Practice)

#### 3.1 External Secrets Operator 도입

**설치**:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
```

**SecretStore 설정**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: tacos-app
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

**ExternalSecret 정의**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gateway-api-secrets
  namespace: tacos-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: gateway-api-secrets
    creationPolicy: Owner
  data:
  - secretKey: jwt-secret
    remoteRef:
      key: traffic-tacos/gateway/jwt-secret
  - secretKey: redis-password
    remoteRef:
      key: traffic-tacos/redis/auth-token
```

**장점**:
- AWS Secrets Manager에서 중앙 관리
- Secret 자동 회전 (Rotation) 지원
- Kubernetes Secret 수동 생성 불필요
- 감사 로그 자동 기록

#### 3.2 AWS Systems Manager Parameter Store 활용

**Account ID 저장**:
```bash
aws ssm put-parameter \
  --name "/traffic-tacos/common/aws-account-id" \
  --value "137406935518" \
  --type "String" \
  --profile tacos
```

**애플리케이션에서 조회**:
```go
// Go 예시
import "github.com/aws/aws-sdk-go/service/ssm"

func getAccountID() string {
    svc := ssm.New(session.Must(session.NewSession()))
    param, _ := svc.GetParameter(&ssm.GetParameterInput{
        Name: aws.String("/traffic-tacos/common/aws-account-id"),
    })
    return *param.Parameter.Value
}
```

#### 3.3 HashiCorp Vault 통합 (Advanced)

**Vault Agent Injector**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway-api
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "gateway-api"
        vault.hashicorp.com/agent-inject-secret-config: "traffic-tacos/data/gateway"
    spec:
      serviceAccountName: gateway-api-sa
      containers:
      - name: gateway-api
        image: gateway-api:latest
```

---

## Secrets 관리 전략

### 현재 아키텍처 (As-Is)

```
┌─────────────────────────────────────────────┐
│         Kubernetes Cluster (EKS)            │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │  Kubernetes Secrets                │    │
│  │  • gateway-api-secrets             │    │
│  │  • redis-password                  │    │
│  │  • payment-webhook-secret          │    │
│  └────────────────────────────────────┘    │
│                  ▲                          │
│                  │ (Manual Creation)        │
│                  │                          │
│  ┌────────────────────────────────────┐    │
│  │  Application Pods                  │    │
│  │  • gateway-api                     │    │
│  │  • reservation-api                 │    │
│  │  • payment-sim-api                 │    │
│  └────────────────────────────────────┘    │
│                  │                          │
│                  │ (IRSA)                   │
└──────────────────┼──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│      AWS Secrets Manager (Optional)         │
│  • traffic-tacos/redis/auth-token          │
│  • traffic-tacos/gateway/jwt-secret        │
└─────────────────────────────────────────────┘
```

**특징**:
- ✅ Kubernetes Secret으로 기본 보안 제공
- ✅ IRSA로 AWS 리소스 안전하게 접근
- ⚠️ Secret 수동 관리 필요
- ⚠️ Secret 회전 수동 처리

### 권장 아키텍처 (To-Be)

```
┌─────────────────────────────────────────────┐
│         Kubernetes Cluster (EKS)            │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │  External Secrets Operator         │    │
│  │  (Automatic Sync)                  │    │
│  └────────────┬───────────────────────┘    │
│               │                             │
│               ▼                             │
│  ┌────────────────────────────────────┐    │
│  │  Kubernetes Secrets (Generated)    │    │
│  │  • gateway-api-secrets ←──────┐    │    │
│  │  • redis-password              │    │    │
│  └────────────────────────────────┼────┘    │
│                  ▲                │         │
│                  │                │         │
│  ┌────────────────────────────────┼────┐    │
│  │  Application Pods              │    │    │
│  │  • gateway-api                 │    │    │
│  │  • reservation-api             │    │    │
│  └────────────────────────────────┘    │    │
│                  │                      │    │
│                  │ (IRSA)               │    │
└──────────────────┼──────────────────────┼────┘
                   │                      │
                   ▼                      │
┌──────────────────────────────────────────┼──┐
│      AWS Secrets Manager                 │  │
│  • traffic-tacos/redis/auth-token        │  │
│  • traffic-tacos/gateway/jwt-secret      │  │
│  • Auto Rotation Enabled ────────────────┘  │
└─────────────────────────────────────────────┘
```

**특징**:
- ✅ Secret 자동 동기화 (External Secrets Operator)
- ✅ 중앙 집중 관리 (AWS Secrets Manager)
- ✅ Secret 자동 회전 (Rotation Lambda)
- ✅ 감사 로그 자동 기록 (CloudTrail)
- ✅ 버전 관리 (Secret Version)

---

## 보안 체크리스트

### Public Repository 공개 전 체크리스트

- [ ] **실제 Credential 제거**
  - [ ] `.env` 파일 제외 확인
  - [ ] `*.pem`, `*.key` 파일 제외 확인
  - [ ] Secret YAML 파일 제외 확인
  
- [ ] **민감 정보 마스킹**
  - [ ] AWS Account ID 플레이스홀더 처리
  - [ ] IAM Role ARN 예제만 포함
  - [ ] 도메인 정보 검토 (필요 시 example.com 사용)
  
- [ ] **.gitignore 설정 확인**
  - [ ] `*.env` 포함
  - [ ] `*secret*.yaml` 포함
  - [ ] `*credentials*.yaml` 포함
  
- [ ] **문서 검토**
  - [ ] README.md 민감 정보 확인
  - [ ] 예제 코드에 실제 값 없음 확인
  - [ ] 보안 가이드 문서 포함

### Kubernetes Secrets 관리 체크리스트

- [ ] **Secret 생성 및 배포**
  - [ ] Kubernetes Secret 수동 생성 완료
  - [ ] Secret 네임스페이스 분리 (tacos-app, argocd 등)
  - [ ] Secret RBAC 설정 (최소 권한)
  
- [ ] **IRSA 설정**
  - [ ] ServiceAccount 생성
  - [ ] IAM Role Trust Policy 설정
  - [ ] Pod에 ServiceAccount 연결
  
- [ ] **Secrets Manager 통합 (Optional)**
  - [ ] AWS Secrets Manager에 Secret 저장
  - [ ] External Secrets Operator 설치
  - [ ] SecretStore 및 ExternalSecret 생성

### 보안 모니터링 체크리스트

- [ ] **감사 로그**
  - [ ] CloudTrail 로그 활성화
  - [ ] EKS Audit Log 활성화
  - [ ] Secrets Manager 접근 로그 모니터링
  
- [ ] **알림 설정**
  - [ ] Secret 접근 실패 알림
  - [ ] IAM Role 변경 알림
  - [ ] 비정상 API 호출 패턴 탐지

---

## 실행 가이드

### 1. README.md 민감 정보 제거

```bash
cd /path/to/deployment-repo

# 백업 생성
cp README.md README.md.backup

# AWS Account ID 마스킹 (수동 편집 권장)
# 137406935518 → <YOUR_AWS_ACCOUNT_ID>
```

### 2. Git History에서 민감 정보 제거 (필요 시)

**⚠️ 주의**: 이 작업은 Git history를 재작성하므로 신중히 진행

```bash
# BFG Repo-Cleaner 사용 (권장)
brew install bfg
bfg --replace-text sensitive-data.txt deployment-repo.git

# 또는 git filter-branch 사용
git filter-branch --tree-filter '
  find . -name "*.yaml" -exec sed -i "s/137406935518/<AWS_ACCOUNT_ID>/g" {} \;
' HEAD

# Force push (팀원들에게 사전 공지 필수!)
git push --force
```

### 3. External Secrets Operator 설치

```bash
# Helm 설치
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Operator 설치
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true

# 설치 확인
kubectl get pods -n external-secrets-system
```

### 4. AWS Secrets Manager에 Secret 생성

```bash
# JWT Secret 생성
aws secretsmanager create-secret \
  --name traffic-tacos/gateway/jwt-secret \
  --description "Gateway API JWT Secret" \
  --secret-string '{"secret":"your-jwt-secret-here"}' \
  --region ap-northeast-2 \
  --profile tacos

# Redis Auth Token
aws secretsmanager create-secret \
  --name traffic-tacos/redis/auth-token \
  --description "Redis Authentication Token" \
  --secret-string '{"password":"your-redis-password"}' \
  --region ap-northeast-2 \
  --profile tacos
```

### 5. SecretStore 및 ExternalSecret 생성

```bash
# SecretStore 적용
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: tacos-app
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF

# ExternalSecret 적용
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gateway-api-secrets
  namespace: tacos-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: gateway-api-secrets
  data:
  - secretKey: jwt-secret
    remoteRef:
      key: traffic-tacos/gateway/jwt-secret
      property: secret
EOF

# Secret 생성 확인
kubectl get secret gateway-api-secrets -n tacos-app
```

---

## 참고 자료

### AWS 보안 문서
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [EKS Security Best Practices](https://aws.github.io/aws-eks-best-practices/security/docs/)
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)

### Kubernetes 보안
- [Kubernetes Secrets Management](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

### External Secrets Operator
- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Secrets Manager Integration](https://external-secrets.io/latest/provider/aws-secrets-manager/)

### GitOps & ArgoCD
- [ArgoCD Security Best Practices](https://argo-cd.readthedocs.io/en/stable/operator-manual/security/)
- [Kustomize Secrets Management](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/secretgenerator/)

### 보안 도구
- [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/) - Git history에서 민감 정보 제거
- [git-secrets](https://github.com/awslabs/git-secrets) - AWS credential 커밋 방지
- [truffleHog](https://github.com/trufflesecurity/trufflehog) - Git repository에서 Secret 스캔

---

## 변경 이력

| 날짜 | 버전 | 작성자 | 변경 내용 |
|-----|------|--------|----------|
| 2025-10-09 | 1.0 | Traffic Tacos Team | 최초 작성 |

---

**작성일**: 2025-10-09  
**작성자**: Traffic Tacos Team  
**문서 상태**: 🟢 Active


