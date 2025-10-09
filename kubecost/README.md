# Kubecost Deployment on AWS EKS

Kubernetes 클러스터의 비용을 실시간으로 모니터링하고 분석하기 위한 Kubecost 배포 설정입니다. Amazon Managed Prometheus(AMP)와 Amazon Managed Grafana(AMG)를 활용하여 완전 관리형 모니터링 환경을 구성합니다.

## 📋 목차

- [아키텍처 개요](#아키텍처-개요)
- [사전 요구사항](#사전-요구사항)
- [설치 방법](#설치-방법)
- [설정 파일 상세 설명](#설정-파일-상세-설명)
- [접속 방법](#접속-방법)
- [트러블슈팅](#트러블슈팅)

## 🏗️ 아키텍처 개요

이 배포 구성은 다음과 같은 AWS 서비스들과 통합됩니다:

- **Amazon EKS**: Kubernetes 클러스터 (ticket-cluster)
- **Amazon Managed Prometheus (AMP)**: 메트릭 데이터 저장소
- **Amazon Managed Grafana (AMG)**: 데이터 시각화
- **AWS Application Load Balancer**: 외부 접근을 위한 인그레스
- **AWS IAM**: IRSA를 통한 권한 관리

```
┌─────────────────────────────────────────────────────┐
│                    EKS Cluster                      │
│  ┌──────────────┐         ┌──────────────┐         │
│  │  Kubecost    │────────▶│ Prometheus   │         │
│  │ Cost Analyzer│         │   Server     │         │
│  └──────┬───────┘         └──────┬───────┘         │
│         │                        │                  │
│         │                        │ Remote Write     │
└─────────┼────────────────────────┼──────────────────┘
          │                        │
          │                        ▼
          │              ┌──────────────────┐
          │              │ Amazon Managed   │
          │              │   Prometheus     │
          │              └────────┬─────────┘
          │                       │
          ▼                       ▼
   ┌────────────┐        ┌──────────────────┐
   │    ALB     │        │ Amazon Managed   │
   │  Ingress   │        │    Grafana       │
   └────────────┘        └──────────────────┘
```

## 📦 사전 요구사항

### AWS 리소스

1. **EKS 클러스터**
   - 클러스터명: `ticket-cluster`
   - 리전: `ap-northeast-2`

2. **Amazon Managed Prometheus Workspace**
   - Workspace ID: `ws-ec1155d6-1ea8-4822-b9e9-fdec9424dcb9`
   - Remote Write 엔드포인트 설정 완료

3. **Amazon Managed Grafana Workspace**
   - 도메인: `g-0bbf7d3778.grafana-workspace.ap-northeast-2.amazonaws.com`
   - AMP 데이터 소스 연동 완료

4. **IAM Role (IRSA)**
   - Role ARN: `arn:aws:iam::137406935518:role/KubecostPrometheusRole`
   - 필요 정책:
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": [
             "aps:RemoteWrite",
             "aps:QueryMetrics",
             "aps:GetSeries",
             "aps:GetLabels",
             "aps:GetMetricMetadata"
           ],
           "Resource": "arn:aws:aps:ap-northeast-2:137406935518:workspace/ws-ec1155d6-1ea8-4822-b9e9-fdec9424dcb9"
         }
       ]
     }
     ```

5. **ACM 인증서**
   - 도메인: `kubecost.traffictacos.store`

6. **AWS Load Balancer Controller**
   - EKS 클러스터에 설치 완료
   - IngressClass `alb` 사용 가능

### Kubernetes 구성

- kubectl 설치 및 클러스터 접근 설정 완료
- Helm 3.x 설치
- 노드에 다음 Taint 설정:
  - `workload=monitoring:NoSchedule`


## 🚀 설치 방법

### 1. Helm Repository 추가

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update
```

### 2. Namespace 생성

```bash
kubectl create namespace kubecost
```

### 3. ServiceAccount 생성

IRSA(IAM Roles for Service Accounts)를 위한 ServiceAccount를 먼저 생성합니다:

```bash
kubectl apply -f serviceaccount.yaml
```

**serviceaccount.yaml 상세 설명:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubecost-prometheus-server
  namespace: kubecost
  annotations:
    # IRSA를 통해 Prometheus가 AMP에 메트릭을 전송할 수 있는 권한 부여
    eks.amazonaws.com/role-arn: arn:aws:iam::137406935518:role/KubecostPrometheusRole
```

### 4. Kubecost 설치

```bash
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --values values.yaml
```

### 5. Ingress 생성

ALB를 통한 외부 접근을 위한 Ingress 리소스를 생성합니다:

```bash
kubectl apply -f ingress.yaml
```

### 6. 설치 확인

```bash
# Pod 상태 확인
kubectl get pods -n kubecost

# Ingress 상태 및 ALB 주소 확인
kubectl get ingress -n kubecost

# ServiceAccount 확인
kubectl get sa kubecost-prometheus-server -n kubecost -o yaml
```

## ⚙️ 설정 파일 상세 설명

### values.yaml

#### Global 설정
```yaml
global:
  grafana:
    enabled: false  # Kubecost 내장 Grafana 비활성화 (AMG 사용)
    domainName: "https://g-0bbf7d3778.grafana-workspace.ap-northeast-2.amazonaws.com/"
    proxy: false    # Grafana를 프록시로 사용하지 않음
```

#### Prometheus Server 설정
```yaml
prometheus:
  server:
    # AMP 엔드포인트 설정
    prometheusServerEndpoint: "https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/ws-ec1155d6-1ea8-4822-b9e9-fdec9424dcb9/api/v1"
    
    global:
      external_labels:
        cluster_id: "ticket-cluster"  # 멀티 클러스터 구분을 위한 라벨
    
    # AMP로 메트릭 전송 설정
    remoteWrite:
      - url: https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/ws-ec1155d6-1ea8-4822-b9e9-fdec9424dcb9/api/v1/remote_write
        sigv4:
          region: ap-northeast-2  # AWS SigV4 인증 사용
        queue_config:
          max_samples_per_send: 1000  # 전송당 최대 샘플 수
          max_shards: 200             # 최대 병렬 전송 수
          capacity: 2500              # 큐 용량
    
    # 영구 볼륨 설정 (메트릭 로컬 저장용)
    persistentVolume:
      size: 32Gi
      storageClass: "gp2"  
    
    # 특정 노드에 스케줄링하기 위한 Toleration
    tolerations:
      - key: "workload"
        operator: "Equal"
        value: "monitoring"
        effect: "NoSchedule"
  
  # Node Exporter 비활성화 (별도 설치 또는 불필요한 경우)
  nodeExporter:
    enabled: false
  
  # 기존 ServiceAccount 사용 (IRSA 설정된 SA)
  serviceAccounts:
    server:
      create: false
      name: kubecost-prometheus-server
```

#### Kubecost 설정
```yaml
kubecostProductConfigs:
  clusterName: "ticket-cluster"  # Kubecost UI에 표시될 클러스터명
```

#### Service 설정
```yaml
service:
  type: ClusterIP  # 내부 접근만 허용 (Ingress를 통한 외부 접근)
  port: 9090
```

#### Ingress 설정
```yaml
ingress:
  enabled: false  # values.yaml에서는 비활성화 (별도 매니페스트로 관리)
```

#### 스토리지 설정
```yaml
persistentVolume:
  storageClass: "gp2"
  size: 32Gi  # Kubecost 데이터 저장용
```

#### Pod 스케줄링 설정
```yaml
# 여러 Taint를 가진 노드에서도 실행 가능하도록 설정
tolerations:
  - key: "workload"
    operator: "Equal"
    value: "monitoring"
    effect: "NoSchedule"

```

#### 리소스 제한
```yaml
resources:
  requests:
    cpu: "200m"      # 최소 보장 CPU
    memory: "512Mi"  # 최소 보장 메모리
  limits:
    cpu: "1000m"     # 최대 CPU 사용량
    memory: "2Gi"    #