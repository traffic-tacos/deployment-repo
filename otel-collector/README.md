# OpenTelemetry Collector 설정

이 디렉토리는 Kubernetes 클러스터에서 OpenTelemetry Collector를 배포하고 관리하기 위한 매니페스트 파일들을 포함합니다.

## 📋 목차

- [개요](#개요)
- [아키텍처](#아키텍처)
- [구성 요소](#구성-요소)
- [배포 모드](#배포-모드)
- [파일 설명](#파일-설명)
- [배포 방법](#배포-방법)
- [주요 기능](#주요-기능)
- [AWS 통합](#aws-통합)

## 개요

OpenTelemetry Collector는 관측성 데이터(메트릭, 로그, 트레이스)를 수집, 처리 및 내보내기 위한 벤더 중립적인 에이전트입니다. 이 설정은 EKS 클러스터에서 애플리케이션 및 인프라 메트릭을 수집하고 AWS 서비스로 전송합니다.

### 주요 목적
- **트레이스 수집**: OTLP 프로토콜을 통해 애플리케이션 트레이스를 수집하여 AWS X-Ray로 전송
- **메트릭 수집**: Kubernetes 클러스터 메트릭 및 애플리케이션 메트릭을 수집하여 Amazon Managed Prometheus (AMP)로 전송
- **로그 수집**: 애플리케이션 로그를 수집하여 Amazon CloudWatch Logs로 전송

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  Applications    │         │   Node Exporter  │         │
│  │  (OTLP Export)   │         │   (Metrics)      │         │
│  └────────┬─────────┘         └────────┬─────────┘         │
│           │                            │                    │
│           │  OTLP (gRPC/HTTP)          │ Prometheus         │
│           ▼                            ▼                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  OTel Collector (DaemonSet)                          │  │
│  │  - kubeletstats receiver                             │  │
│  │  - OTLP receiver (4317/4318)                         │  │
│  │  - k8sattributes processor                           │  │
│  └────────┬────────────────────────────────┬────────────┘  │
│           │                                 │               │
│           │                                 │               │
│  ┌────────▼─────────────────────────────────▼───────────┐  │
│  │  OTel Collector (StatefulSet)                        │  │
│  │  - prometheus receiver (with TargetAllocator)        │  │
│  │  - k8s_cluster receiver                              │  │
│  └────────┬─────────────────────────────────────────────┘  │
│           │                                                 │
└───────────┼─────────────────────────────────────────────────┘
            │
            │ AWS IAM Roles for Service Accounts (IRSA)
            │
            ▼
┌───────────────────────────────────────────────────────┐
│                    AWS Services                       │
│  ┌──────────────┐  ┌───────────┐  ┌───────────────┐ │
│  │  AWS X-Ray   │  │    AMP    │  │  CloudWatch   │ │
│  │  (Traces)    │  │ (Metrics) │  │  (Logs)       │ │
│  └──────────────┘  └───────────┘  └───────────────┘ │
└───────────────────────────────────────────────────────┘
```

## 구성 요소

### 1. 메인 Collector (DaemonSet)
**파일**: `otel-collector-daemonset.yaml`

각 노드에서 실행되며 로컬 메트릭과 트레이스를 수집합니다.

**수집 데이터**:
- Node/Pod/Container 메트릭 (kubeletstats receiver)
- 애플리케이션 트레이스 (OTLP receiver)
- 애플리케이션 로그 (OTLP receiver)
- 애플리케이션 커스텀 메트릭 (OTLP receiver)

**처리 기능**:
- Kubernetes 속성 추가 (k8sattributes processor)
- Health check 엔드포인트 필터링 (filter/healthcheck processor)
- 배치 처리 (batch processor)

**전송 대상**:
- AWS X-Ray (트레이스)
- Amazon Managed Prometheus (메트릭)
- Amazon CloudWatch Logs (로그)

### 2. 모니터링 Collector (StatefulSet)
**파일**: `otel-collector-statefulset-with-ta.yaml`

중앙 집중식으로 Prometheus 메트릭과 클러스터 메트릭을 수집합니다.

**수집 데이터**:
- Kubernetes 클러스터 리소스 메트릭 (k8s_cluster receiver)
- Prometheus 스타일 메트릭 (prometheus receiver)
- Node Exporter 메트릭
- OpenTelemetry Collector 자체 메트릭

**특징**:
- **Target Allocator**: Prometheus 스크레이핑 타겟을 자동으로 분배
- **Pod Anti-Affinity**: 고가용성을 위한 분산 배치
- **Monitoring Node 전용**: Tolerations를 통해 모니터링 노드에 배포

## 배포 모드

### DaemonSet 모드
- 모든 노드에 하나의 Collector 인스턴스 실행
- 노드 레벨 메트릭 수집에 적합
- 낮은 네트워크 오버헤드

### StatefulSet 모드
- 고정된 수의 Collector 인스턴스 실행
- 중앙 집중식 데이터 수집
- Target Allocator와 함께 사용하여 Prometheus 스크레이핑 부하 분산

## 파일 설명

| 파일명 | 용도 | 설명 |
|--------|------|------|
| `otel-collector-daemonset.yaml` | 메인 Collector | DaemonSet 모드로 각 노드에서 실행되는 Collector |
| `otel-collector-statefulset-with-ta.yaml` | 모니터링 Collector | StatefulSet 모드로 실행되며 Target Allocator 포함 |
| `otel-collector-serviceaccount.yaml` | 서비스 계정 | AWS IAM Role 연결을 위한 ServiceAccount |
| `otel-collector-clusterrole.yaml` | 권한 정의 | Kubernetes 리소스 접근 권한 정의 |
| `otel-collector-clusterrolebinding.yaml` | 권한 바인딩 | ServiceAccount와 ClusterRole 연결 |

## 배포 방법

### 전제 조건
1. **OpenTelemetry Operator 설치**
   ```bash
   kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
   ```

2. **네임스페이스 생성**
   ```bash
   kubectl create namespace otel-collector
   ```

3. **AWS IAM Role 설정**
   - IAM Role ARN: `arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/<YOUR_OTEL_COLLECTOR_ROLE_NAME>`
   - 필요한 권한:
     - AMP Remote Write 권한
     - X-Ray Write 권한
     - CloudWatch Logs Write 권한

### 배포 순서

```bash
# 1. ServiceAccount 생성
kubectl apply -f otel-collector-serviceaccount.yaml

# 2. RBAC 설정
kubectl apply -f otel-collector-clusterrole.yaml
kubectl apply -f otel-collector-clusterrolebinding.yaml

# 3. DaemonSet Collector 배포
kubectl apply -f otel-collector-daemonset.yaml

# 4. StatefulSet Collector 배포 (Target Allocator 포함)
kubectl apply -f otel-collector-statefulset-with-ta.yaml
```

### 배포 확인

```bash
# Collector Pod 상태 확인
kubectl get pods -n otel-collector

# DaemonSet 확인
kubectl get daemonset -n otel-collector

# StatefulSet 확인
kubectl get statefulset -n otel-collector

# 로그 확인
kubectl logs -n otel-collector -l app.kubernetes.io/name=otel-collector -f

# Target Allocator 확인
kubectl get pods -n otel-collector -l app.kubernetes.io/component=opentelemetry-targetallocator
```

## 주요 기능

### 1. Health Check 필터링
actuator health check 엔드포인트는 트레이스와 로그에서 자동으로 필터링됩니다:
- `/actuator/health/liveness`
- `/actuator/health/readiness`

### 2. Kubernetes 속성 추가
모든 텔레메트리 데이터에 자동으로 Kubernetes 메타데이터가 추가됩니다:
- Pod 이름, UID
- Deployment 이름
- Namespace
- Node 이름
- Service 정보
- 커스텀 레이블 (예: `app.kubernetes.io/component`)

### 3. 메모리 제한
메모리 사용량을 제어하여 안정적인 운영을 보장합니다:
- Hard Limit: 80% (1Gi 환경에서 800Mi)
- Soft Limit: 500Mi (Spike 방지)

### 4. Batch 처리
효율적인 데이터 전송을 위한 배치 처리:
- Batch Size: 10,000개
- Timeout: 5-10초

### 5. 롤링 업데이트 전략
무중단 배포를 위한 업데이트 전략:
- MaxUnavailable: 25%

## AWS 통합

### IRSA (IAM Roles for Service Accounts)
ServiceAccount에 AWS IAM Role이 연결되어 있어 안전한 AWS 서비스 접근이 가능합니다.

**설정 정보**:
- **Role ARN**: `arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/<YOUR_OTEL_COLLECTOR_ROLE_NAME>`
- **Region**: `ap-northeast-2` (서울 리전)
- **Token Expiration**: 86400초 (24시간)

### Amazon Managed Prometheus (AMP)
**Workspace ID**: `<YOUR_AMP_WORKSPACE_ID>`

**Endpoint**:
```
https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/<YOUR_AMP_WORKSPACE_ID>/api/v1/remote_write
```

### AWS X-Ray
**Endpoint**:
```
https://xray.ap-northeast-2.amazonaws.com
```

트레이스 데이터는 X-Ray 형식으로 변환되어 전송됩니다.

### Amazon CloudWatch Logs
**Log Group**: `/aws/otel/tacos-logs`
**Log Stream**: `otel-logs`
**Retention**: 365일

## 수집되는 메트릭

### kubeletstats 메트릭
- **Node 메트릭**: CPU, Memory, Filesystem, Network
- **Pod 메트릭**: CPU, Memory, Network, Volume
- **Container 메트릭**: CPU, Memory, Filesystem

### k8s_cluster 메트릭
- Node 상태 (Ready, MemoryPressure)
- Allocatable 리소스 (CPU, Memory, Storage, Pods)
- Deployment/ReplicaSet 상태
- Service/Endpoint 정보

### Prometheus 메트릭
- OpenTelemetry Collector 자체 메트릭
- Node Exporter 메트릭 (node_*)
- 커스텀 애플리케이션 메트릭

## 트러블슈팅

### Collector Pod가 시작하지 않는 경우
```bash
# Pod 이벤트 확인
kubectl describe pod -n otel-collector <pod-name>

# ServiceAccount 확인
kubectl get sa otel-collector-sa -n otel-collector -o yaml

# IAM Role 연결 확인
kubectl get sa otel-collector-sa -n otel-collector -o jsonpath='{.metadata.annotations}'
```

### 메트릭이 AMP로 전송되지 않는 경우
```bash
# Collector 로그 확인
kubectl logs -n otel-collector -l app.kubernetes.io/name=otel-collector | grep -i error

# AWS 인증 확인
kubectl logs -n otel-collector <pod-name> | grep -i "sigv4\|auth\|credential"

# Prometheus Remote Write 엔드포인트 확인
kubectl logs -n otel-collector <pod-name> | grep -i "prometheusremotewrite"
```

### Target Allocator 문제
```bash
# Target Allocator Pod 확인
kubectl get pods -n otel-collector -l app.kubernetes.io/component=opentelemetry-targetallocator

# Target Allocator 로그 확인
kubectl logs -n otel-collector -l app.kubernetes.io/component=opentelemetry-targetallocator

# Target 할당 상태 확인 (TargetAllocator Service Port-forward)
kubectl port-forward -n otel-collector svc/otel-collector-with-ta-targetallocator 8080:80
curl http://localhost:8080/jobs
```

### 메모리 부족 문제
```bash
# 메모리 사용량 확인
kubectl top pods -n otel-collector

# Memory Limiter 로그 확인
kubectl logs -n otel-collector <pod-name> | grep -i "memory_limiter"

# 리소스 제한 확인
kubectl get pods -n otel-collector <pod-name> -o jsonpath='{.spec.containers[0].resources}'
```

## 설정 변경 시 주의사항

### 1. AWS 리전 변경
다음 항목들을 일관되게 변경해야 합니다:
- `awsxray.region`
- `awscloudwatchlogs.region`
- `prometheusremotewrite.endpoint`
- `sigv4auth.assume_role.sts_region`

### 2. IAM Role ARN 변경
다음 항목들을 변경해야 합니다:
- `otel-collector-serviceaccount.yaml`의 annotation
- `otel-collector-daemonset.yaml`의 `AWS_ROLE_ARN` 환경 변수
- `otel-collector-daemonset.yaml`의 `sigv4auth.assume_role.arn`

### 3. AMP Workspace 변경
`prometheusremotewrite.endpoint`의 Workspace ID를 변경해야 합니다.

## 참고 자료

- [OpenTelemetry Collector 공식 문서](https://opentelemetry.io/docs/collector/)
- [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator)
- [AWS Distro for OpenTelemetry](https://aws-otel.github.io/)
- [Amazon Managed Prometheus](https://aws.amazon.com/prometheus/)
- [AWS X-Ray](https://aws.amazon.com/xray/)

## 라이센스

이 프로젝트는 조직의 내부 사용을 위한 것입니다.
