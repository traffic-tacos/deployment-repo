# Traffic Tacos Deployment 플랜

## 📋 개요

3만 RPS를 처리하는 Traffic Tacos 애플리케이션을 EKS 클러스터에 GitOps 방식으로 배포합니다.

**목표:**
- ✅ ArgoCD 기반 GitOps 구성
- ✅ 3만 RPS 처리 가능한 인프라 구성
- ✅ 보안 강화 (네트워크 정책, RBAC, Pod Security)
- ✅ FinOps 최적화 (리소스 관리, HPA, VPA)

**환경:**
- EKS Cluster: `ticket-cluster`
- Region: `ap-northeast-2`
- AWS Profile: `tacos`
- AWS Account: `137406935518`

---

## 🔍 현재 클러스터 상태 (2025-09-30 확인)

### ✅ Phase 1: Gateway API (완료)
- **Gateway 리소스**: `api-traffictacos-gateway` (정상 작동)
- **도메인**: `api.traffictacos.store`
- **ALB**: `k8s-gateway-apitraff-bd9ec75eb6-309235565.ap-northeast-2.elb.amazonaws.com`
- **HTTPRoute**: `api-traffictacos-route`, `http-redirect-route` (정상)
- **ACM 인증서**: ✅ 적용됨
- **External DNS**: ✅ 설정됨

### ❌ Phase 2: ArgoCD (미배포)
- **argocd 네임스페이스**: ✅ 존재
- **ArgoCD Pods**: ❌ 배포 안됨

### ⚠️ Phase 3: Applications (부분 배포)
- **tacos-app 네임스페이스**: ✅ 존재
- **배포된 서비스** (33시간 전 배포):
  - `gateway-api`: ⚠️ **문제 있음** (0/2 Ready)
    - 원인: AWS Secrets Store CSI Provider Pod가 해당 노드에 없음
  - `reservation-api`: ✅
  - `inventory-api`: ✅
  - `payment-sim-api`: ✅
  - `reservation-worker`: ✅

### 🔧 발견된 문제들
1. **AWS Secrets Store CSI Provider 배포 불완전**
   - Provider Pod가 일부 노드에만 배포됨 (2/3 노드)
   - gateway-api Pod가 Provider 없는 노드에 스케줄됨
2. **SecretProviderClass 설정 오류** (수정 완료)
   - jmesPath 필드 제거 완료
3. **gateway-api 컨테이너 문제**
   - Redis 연결 실패 (타임아웃)
   - CSI Provider 마운트 실패

---

## 🎯 Phase 1: Gateway API 배포 (기반 인프라) ✅ **완료**

### 목표
외부 트래픽을 처리할 Gateway API를 먼저 배포하고, 이후 ArgoCD 및 애플리케이션 노출에 사용

### 작업 항목

#### 1.1 네임스페이스 및 기본 리소스
- [x] `gateway` 네임스페이스 생성
- [x] NetworkPolicy 설정

#### 1.2 Gateway API CRD 설치
- [x] Gateway API CRD 버전 확인 (v1.0.0+) - **v1 설치됨**
- [x] CRD 설치 (kubectl apply)
- [x] Gateway Class 생성 (AWS Load Balancer Controller) - **aws-alb-gateway-class**

#### 1.3 AWS Load Balancer Controller 확인
- [x] AWS Load Balancer Controller 설치 확인 - **정상 작동**
- [x] IRSA 설정 확인
- [x] ACM 인증서 확인/생성 (*.traffictacos.store) - **arn:...467dbda7-edf0-44b7-9381-833f74dc554b**

#### 1.4 Gateway 리소스 생성
- [x] Gateway 리소스 생성 - **api-traffictacos-gateway**
  - TLS 인증서 설정 ✅
  - Listener 설정 (HTTP/HTTPS) ✅
  - AWS ALB 어노테이션 ✅
- [x] Gateway LoadBalancer 생성 확인 - **k8s-gateway-apitraff-bd9ec75eb6**

#### 1.5 Route53 설정
- [x] Gateway ALB 주소 확인
- [x] Route53 레코드 생성 - **External DNS로 자동 생성**
  - `api.traffictacos.store` → Gateway ALB ✅

#### 1.6 검증
- [x] Gateway LoadBalancer 생성 확인 ✅
- [x] TLS 인증서 적용 확인 ✅
- [x] DNS 해석 확인 ✅

---

## 🚨 우선순위 작업 (즉시 해결 필요)

### 문제 1: AWS Secrets Store CSI Provider 문제 해결

**현재 상황:**
- Provider Pod가 일부 노드에만 배포됨
- gateway-api Pod가 Secrets 마운트 실패

**해결 방안:**
1. **임시 해결**: NodeAffinity로 gateway-api를 Provider 있는 노드로 스케줄
2. **근본 해결**: Provider DaemonSet 수정하여 모든 노드에 배포

### 문제 2: gateway-api Redis 연결 실패

**현재 상황:**
- Redis 연결 타임아웃
- ElastiCache 주소: `master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379`

**확인 필요:**
1. ElastiCache 보안 그룹 설정
2. NetworkPolicy 설정
3. Redis 엔드포인트 접근 가능 여부

---

## 🔄 Phase 2: ArgoCD 배포 (GitOps) - **다음 단계**

### 목표
GitOps를 위한 ArgoCD를 EKS 클러스터에 배포하고 Gateway API를 통해 노출

### 작업 항목

#### 2.1 네임스페이스 및 기본 리소스 생성
- [x] `argocd` 네임스페이스 생성 - **이미 존재**
- [ ] 필요한 ServiceAccount 및 RBAC 설정

#### 2.2 ArgoCD Helm 차트 배포
- [ ] Argo Helm repository 추가
- [ ] `helm-values/argocd-values.yaml` 작성
  - HA 구성 (최소 2 replicas)
  - 리소스 제한 설정
  - Redis HA 구성
  - **Ingress 비활성화** (Gateway API 사용)
- [ ] Helm 차트로 ArgoCD 설치

#### 2.3 Gateway API를 통한 ArgoCD 노출
- [ ] Gateway에 `argocd.traffictacos.store` listener 추가 또는
- [ ] 별도 Gateway 생성
- [ ] HTTPRoute 리소스 생성 (`argocd.traffictacos.store`)
  - ArgoCD Server Service 연결
  - TLS 설정
  - Path 라우팅 설정
- [ ] gRPC Route 설정 (ArgoCD CLI 지원)

#### 2.4 ArgoCD 프로젝트 구성
- [ ] `traffic-tacos` AppProject 생성
- [ ] Repository 연결 (GitHub)
- [ ] RBAC 정책 설정

#### 2.5 검증
- [ ] ArgoCD UI 접근 확인 (https://argocd.traffictacos.store)
- [ ] Admin 계정 로그인 확인
- [ ] ArgoCD CLI 연결 확인
- [ ] Health check 통과

---

## 🍕 Phase 3: Application 배포

### 목표
Traffic Tacos 마이크로서비스를 배포하고 3만 RPS 처리, 보안, FinOps 요구사항 충족

### 작업 항목

#### 3.1 네임스페이스 및 기본 리소스
- [ ] `tacos` 네임스페이스 생성
- [ ] ServiceAccount 생성 (IRSA 연동)
- [ ] NetworkPolicy 설정 (마이크로서비스 간 통신)

#### 3.2 공통 CRD 및 정책 정의

##### 3.2.1 3만 RPS 처리 (성능)
- [ ] **HorizontalPodAutoscaler (HPA)**
  - CPU/Memory 기반 스케일링
  - 최소/최대 replicas 설정
  - Target utilization 설정
- [ ] **VerticalPodAutoscaler (VPA)** (선택)
  - 리소스 자동 조정
- [ ] **PodDisruptionBudget (PDB)**
  - 최소 가용 Pod 수 보장
- [ ] **ServiceMonitor** (Prometheus)
  - 메트릭 수집 설정

##### 3.2.2 보안 강화
- [ ] **NetworkPolicy**
  - Ingress: Gateway → API 서비스만 허용
  - Egress: 필요한 서비스만 허용
- [ ] **PodSecurityPolicy** / **Pod Security Standards**
  - Baseline/Restricted 프로필 적용
  - readOnlyRootFilesystem
  - runAsNonRoot
  - capabilities drop
- [ ] **SecurityContext**
  - 각 Pod에 적용
- [ ] **Secrets 관리**
  - AWS Secrets Manager / Parameter Store 연동
  - External Secrets Operator 고려

##### 3.2.3 FinOps 최적화
- [ ] **ResourceQuota**
  - Namespace별 리소스 제한
- [ ] **LimitRange**
  - Pod/Container별 기본 리소스 설정
- [ ] **리소스 requests/limits 최적화**
  - Right-sizing 기반 설정
- [ ] **Cost Allocation Tags**
  - 레이블 전략 정의
- [ ] **Cluster Autoscaler 연동**
  - Node 스케일링 설정

#### 3.3 개별 애플리케이션 배포

각 애플리케이션에 대해 다음을 수행:

##### 3.3.1 gateway-api
- [ ] Helm values 작성: `helm-values/gateway-api-values.yaml`
- [ ] ArgoCD Application: `applications/tacos/gateway-api.yaml`
- [ ] HPA 설정 (목표: 100+ replicas)
- [ ] PDB 설정 (minAvailable: 50%)
- [ ] NetworkPolicy 설정
- [ ] 리소스 최적화

##### 3.3.2 reservation-api
- [ ] Helm values 작성: `helm-values/reservation-api-values.yaml`
- [ ] ArgoCD Application: `applications/tacos/reservation-api.yaml`
- [ ] HPA 설정
- [ ] PDB 설정
- [ ] DB 연결 설정 (RDS)
- [ ] Cache 설정 (Redis/ElastiCache)
- [ ] NetworkPolicy 설정

##### 3.3.3 inventory-api
- [ ] Helm values 작성: `helm-values/inventory-api-values.yaml`
- [ ] ArgoCD Application: `applications/tacos/inventory-api.yaml`
- [ ] HPA 설정
- [ ] PDB 설정
- [ ] DB 연결 설정
- [ ] NetworkPolicy 설정

##### 3.3.4 payment-sim-api
- [ ] Helm values 작성: `helm-values/payment-sim-api-values.yaml`
- [ ] ArgoCD Application: `applications/tacos/payment-sim-api.yaml`
- [ ] HPA 설정
- [ ] PDB 설정
- [ ] NetworkPolicy 설정

##### 3.3.5 reservation-worker
- [ ] Helm values 작성: `helm-values/reservation-worker-values.yaml`
- [ ] ArgoCD Application: `applications/tacos/reservation-worker.yaml`
- [ ] HPA 설정 (Queue 기반)
- [ ] SQS/Kafka 연동 설정
- [ ] NetworkPolicy 설정

#### 3.4 공통 매니페스트 작성
- [ ] `manifests/tacos/namespace.yaml`
- [ ] `manifests/tacos/networkpolicies.yaml`
- [ ] `manifests/tacos/resourcequota.yaml`
- [ ] `manifests/tacos/limitrange.yaml`
- [ ] `manifests/tacos/pod-security-standards.yaml`

#### 3.5 검증
- [ ] 모든 Pod Running 확인
- [ ] Service endpoint 테스트
- [ ] Gateway를 통한 트래픽 라우팅 확인
- [ ] HPA 작동 확인 (부하 테스트)
- [ ] NetworkPolicy 작동 확인
- [ ] 리소스 사용량 모니터링

---

## 📊 Phase 4: 모니터링 및 관측성

### 목표
3만 RPS 처리를 위한 모니터링 및 알림 설정

### 작업 항목

#### 4.1 Prometheus & Grafana 설정
- [ ] `monitoring` 네임스페이스 확인 (이미 존재)
- [ ] Prometheus Operator 배포 확인
- [ ] ServiceMonitor 생성 (각 애플리케이션)
- [ ] Grafana 대시보드 구성
  - RPS 모니터링
  - Latency 모니터링
  - Error rate
  - Resource utilization

#### 4.2 로깅
- [ ] Fluent Bit / Fluentd 설정
- [ ] CloudWatch Logs 연동
- [ ] 로그 수집 정책

#### 4.3 분산 추적
- [ ] Jaeger / AWS X-Ray 설정
- [ ] 트레이싱 에이전트 배포

#### 4.4 알림
- [ ] AlertManager 설정
- [ ] Alert 규칙 정의
  - High error rate
  - High latency
  - Pod failures
  - Resource exhaustion
- [ ] SNS/Slack 연동

---

## 🧪 Phase 5: 성능 테스트 (3만 RPS 검증)

### 목표
실제 3만 RPS 처리 가능 여부 검증

### 작업 항목

#### 5.1 K6 부하 테스트 환경 구성
- [ ] K6 operator 배포 (이미 존재)
- [ ] 테스트 시나리오 작성
  - Ramp-up: 0 → 30,000 RPS (10분)
  - Sustained: 30,000 RPS (30분)
  - Spike: 50,000 RPS (5분)

#### 5.2 부하 테스트 실행
- [ ] Reservation API 테스트
- [ ] Inventory API 테스트
- [ ] Payment API 테스트
- [ ] End-to-end 시나리오 테스트

#### 5.3 결과 분석 및 튜닝
- [ ] P95/P99 latency 확인
- [ ] Error rate 확인
- [ ] HPA 작동 확인
- [ ] 병목 구간 식별
- [ ] 리소스 튜닝

---

## 🔒 Phase 6: 보안 강화 및 컴플라이언스

### 작업 항목

#### 6.1 네트워크 보안
- [ ] NetworkPolicy 감사
- [ ] Egress filtering
- [ ] VPC 보안 그룹 확인

#### 6.2 인증/인가
- [ ] IRSA (IAM Roles for Service Accounts) 설정
- [ ] Pod Identity 설정
- [ ] Secrets 암호화 (KMS)

#### 6.3 취약점 스캔
- [ ] Trivy 스캔 실행
- [ ] 컨테이너 이미지 검증
- [ ] CIS Benchmark 확인

#### 6.4 컴플라이언스
- [ ] Pod Security Standards 적용 확인
- [ ] Audit logging 활성화
- [ ] Access control 검토

---

## 💰 Phase 7: FinOps 최적화

### 작업 항목

#### 7.1 비용 가시성
- [ ] Cost allocation tags 적용
- [ ] Kubecost 설치 (선택)
- [ ] AWS Cost Explorer 태그 확인

#### 7.2 리소스 최적화
- [ ] Right-sizing 분석
- [ ] Spot Instance 활용 검토
- [ ] Reserved Capacity 검토

#### 7.3 자동 스케일링 최적화
- [ ] Cluster Autoscaler 튜닝
- [ ] HPA 임계값 최적화
- [ ] VPA 활용 검토

#### 7.4 비용 알림
- [ ] Budget 설정
- [ ] 비용 초과 알림

---

## 📁 디렉토리 구조

```
deployment-repo/
├── applications/                  # ArgoCD Application CRDs
│   ├── gateway/
│   │   └── gateway-api.yaml
│   └── tacos/
│       ├── gateway-api.yaml
│       ├── reservation-api.yaml
│       ├── inventory-api.yaml
│       ├── payment-sim-api.yaml
│       └── reservation-worker.yaml
├── helm-values/                   # Helm values files
│   ├── argocd-values.yaml
│   ├── gateway-api-values.yaml
│   ├── reservation-api-values.yaml
│   ├── inventory-api-values.yaml
│   ├── payment-sim-api-values.yaml
│   └── reservation-worker-values.yaml
├── manifests/                     # Raw Kubernetes manifests
│   ├── gateway/                   # Gateway API (Phase 1)
│   │   ├── namespace.yaml
│   │   ├── gateway-class.yaml
│   │   ├── gateway.yaml         # Main Gateway resource
│   │   └── certificates.yaml    # ACM certificate reference
│   ├── argocd/                    # ArgoCD (Phase 2)
│   │   ├── namespace.yaml
│   │   ├── httproute.yaml       # ArgoCD HTTPRoute (Gateway 사용)
│   │   └── project.yaml
│   └── tacos/                     # Applications (Phase 3)
│       ├── namespace.yaml
│       ├── httproutes.yaml      # App HTTPRoutes
│       ├── networkpolicies.yaml
│       ├── resourcequota.yaml
│       ├── limitrange.yaml
│       └── pod-security-standards.yaml
├── common/                        # Common resources
│   ├── namespaces/
│   └── crds/
├── k6/                           # K6 load testing
│   ├── k6-scripts/
│   └── k6-deploy-configs/
├── scripts/                      # Deployment scripts
│   ├── deploy-argocd.sh
│   ├── deploy-gateway.sh
│   ├── deploy-applications.sh
│   └── run-load-test.sh
├── docs/                         # Documentation
│   ├── architecture.md
│   ├── scaling-strategy.md
│   └── security-guidelines.md
└── README.md
```

---

## 🚀 실행 순서

### Step 1: AWS 환경 확인
```bash
# AWS 프로필 확인
aws sts get-caller-identity --profile tacos

# EKS 클러스터 접근 확인
aws eks update-kubeconfig --name ticket-cluster --region ap-northeast-2 --profile tacos
kubectl cluster-info

# AWS Load Balancer Controller 확인
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

### Step 2: Gateway API 배포 (기반 인프라)
```bash
# Gateway API CRD 설치
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Gateway 배포
./scripts/deploy-gateway.sh
```

### Step 3: ArgoCD 배포 (GitOps)
```bash
./scripts/deploy-argocd.sh

# ArgoCD UI 접속: https://argocd.traffictacos.store
```

### Step 4: Applications 배포
```bash
# ArgoCD를 통해 GitOps로 배포
./scripts/deploy-applications.sh
```

### Step 5: 검증 및 테스트
```bash
# Health check
kubectl get pods -A

# Gateway 및 HTTPRoute 확인
kubectl get gateway,httproute -A

# Load test
./scripts/run-load-test.sh
```

---

## 📝 참고 사항

### AWS 리소스
- EKS Cluster: `ticket-cluster`
- VPC, Subnets, Security Groups: 기존 IaC에서 관리
- RDS, ElastiCache: 별도 IaC 또는 수동 생성
- Route53 Hosted Zone: `traffictacos.store`
- ACM 인증서: `*.traffictacos.store`

### 3만 RPS 처리 전략
1. **수평 확장**: HPA를 통한 Pod 자동 증가
2. **리소스 최적화**: Right-sizing 기반 requests/limits
3. **캐싱**: Redis/ElastiCache 적극 활용
4. **비동기 처리**: Worker를 통한 부하 분산
5. **Connection Pool**: DB 연결 최적화

### 보안 전략
1. **최소 권한 원칙**: RBAC, NetworkPolicy
2. **런타임 보안**: Pod Security Standards
3. **Secrets 관리**: AWS Secrets Manager
4. **네트워크 격리**: NetworkPolicy, Security Groups

### FinOps 전략
1. **리소스 효율성**: Right-sizing, HPA, VPA
2. **비용 가시성**: Tags, Kubecost
3. **자동 스케일링**: Cluster Autoscaler
4. **Spot Instance**: 비용 절감

---

## ✅ 체크리스트

작업 진행 시 각 항목을 체크하며 진행합니다.

### Gateway API (Phase 1) ✅ **완료**
- [x] Gateway API CRD 설치
- [x] AWS Load Balancer Controller 확인
- [x] Gateway 리소스 생성
- [x] ALB 생성 확인
- [x] Route53 레코드 설정
- [x] TLS 인증서 적용

### 🚨 우선순위 수정 작업
- [ ] AWS Secrets Store CSI Provider 문제 해결
- [ ] gateway-api Redis 연결 문제 해결
- [ ] gateway-api Pod 정상화

### ArgoCD (Phase 2) - **다음 단계**
- [x] argocd 네임스페이스 생성
- [ ] ArgoCD 설치 (Helm)
- [ ] HTTPRoute로 ArgoCD 노출
- [ ] UI 접근 가능 (https://argocd.traffictacos.store)
- [ ] GitHub 연동 완료
- [ ] AppProject 생성 완료

### Applications (Phase 3) - **부분 완료**
- [x] tacos-app 네임스페이스 생성
- [x] 서비스 배포 (5개)
  - [ ] gateway-api (문제 있음)
  - [x] reservation-api
  - [x] inventory-api
  - [x] payment-sim-api
  - [x] reservation-worker
- [ ] HPA 작동 확인
- [ ] NetworkPolicy 적용 확인
- [ ] 리소스 최적화 완료

### 성능
- [ ] 3만 RPS 처리 검증
- [ ] Latency 요구사항 충족
- [ ] Error rate < 0.1%

### 보안
- [ ] Pod Security Standards 적용
- [ ] NetworkPolicy 적용
- [ ] IRSA 설정 완료
- [ ] Secrets 암호화

### FinOps
- [ ] ResourceQuota/LimitRange 설정
- [ ] Cost allocation tags 적용
- [ ] 모니터링 대시보드 구성
- [ ] 비용 알림 설정

---

## 🎯 다음 단계

### 즉시 조치 (긴급)
1. **AWS Secrets Store CSI Provider 문제 해결**
   - DaemonSet nodeSelector/affinity 확인 및 수정
   - 모든 on-demand 노드에 Provider 배포 보장
   
2. **gateway-api 문제 해결**
   - Redis 보안 그룹 설정 확인
   - NetworkPolicy 확인
   - Pod 재배포 및 정상화

### 단기 작업 (이번 주)
3. **ArgoCD 배포**
   - Helm values 작성
   - ArgoCD 설치
   - Gateway HTTPRoute 설정
   - GitHub 연동

4. **애플리케이션 GitOps 전환**
   - ArgoCD Application CRD 작성
   - 기존 배포를 ArgoCD로 관리

### 중기 작업 (다음 주)
5. **3만 RPS 대비 튜닝**
   - HPA 설정 및 테스트
   - 리소스 최적화
   - K6 부하 테스트

6. **보안 강화**
   - NetworkPolicy 전면 적용
   - Pod Security Standards
   - IRSA 설정

---

**최종 업데이트**: 2025-09-30 21:45  
**작성자**: AI Assistant  
**상태**: 
- Phase 1 (Gateway API): ✅ 완료
- Phase 2 (ArgoCD): ⏳ 대기 중
- Phase 3 (Applications): ⚠️ 부분 배포 (수정 필요)
