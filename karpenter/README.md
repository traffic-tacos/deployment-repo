# Karpenter Auto-Scaling Configuration

AWS EKS 클러스터에서 Karpenter를 활용한 지능형 노드 프로비저닝 설정입니다.
On-Demand와 Spot 인스턴스를 효율적으로 조합하여 비용 최적화와 안정성을 동시에 달성합니다.

## 📋 목차

- [아키텍처 개요](#아키텍처-개요)
- [NodePool 전략](#nodepool-전략)
- [사전 요구사항](#사전-요구사항)
- [설치 방법](#설치-방법)

## 🏗️ 아키텍처 개요

### Karpenter 동작 방식

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                               │
│  ┌──────────────┐        ┌──────────────────────┐           │
│  │  Pod (Pending)│───────▶│   Karpenter          │           │
│  │  with specific│        │   Controller         │           │
│  │  requirements │        └──────────┬───────────┘           │
│  └──────────────┘                    │                       │
│                                      │ Provisions            │
│                                      ▼                        │
│                        ┌─────────────────────────┐           │
│                        │    EC2 Instance         │           │
│                        │  (Based on NodePool &   │           │
│                        │   EC2NodeClass)         │           │
│                        └─────────────────────────┘           │
└───────────────────────────────────────────────────────────────┘
                                     │
                                     │ AWS API
                                     ▼
                         ┌──────────────────────┐
                         │    AWS EC2 Service   │
                         │  • Launch Instance   │
                         │  • Apply Tags        │
                         │  • Attach IAM Role   │
                         └──────────────────────┘
```

### NodePool 구성

이 설정은 3개의 NodePool로 워크로드를 분리합니다:

| NodePool | 용도 | 인스턴스 타입 | 비용 전략 |
|----------|------|--------------|----------|---------|
| **on-demand-critical** | 프로덕션 핵심 워크로드 | On-Demand | 안정성 우선 |
| **mixed-workload** | 일반 워크로드 | Spot | 비용 최적화 |
| **loadtest** | 부하 테스트 | Spot | 비용 최소화 |

## 🎯 NodePool 전략

### 1. on-demand-critical 
**목적**: 중단되면 안 되는 중요한 워크로드를 위한 안정적인 노드 제공

**특징**:
- ✅ On-Demand 인스턴스만 사용 (중단 없음)
- ✅ 점진적 통합 (2분 대기 후)

### 2. mixed-workload (일반 워크로드)
**목적**: 비용 효율적인 Spot 인스턴스로 일반 워크로드 처리

**특징**:
- 💰 Spot 인스턴스 사용 (최대 90% 비용 절감)
- 💰 빠른 통합 (30초 대기 후)

### 3. loadtest (부하 테스트 전용)
**목적**: 부하 테스트를 위한 격리된 환경

**특징**:
- 🧪 Spot 인스턴스만 사용
- 🧪 Taint 적용으로 일반 워크로드와 격리

## 📦 사전 요구사항

### 1. EKS 클러스터 설정

```bash
# 클러스터 정보
CLUSTER_NAME=ticket-cluster
REGION=ap-northeast-2
```

### 2. IAM Role 생성

Karpenter가 EC2 인스턴스를 관리하고 노드를 프로비저닝하기 위한 IAM 역할이 필요합니다.

#### Karpenter Controller IAM Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateLaunchTemplate",
        "ec2:CreateFleet",
        "ec2:RunInstances",
        "ec2:CreateTags",
        "ec2:TerminateInstances",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeSpotPriceHistory",
        "pricing:GetProducts",
        "ssm:GetParameter"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ticket-cluster-eks-worker-role"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster"
      ],
      "Resource": "arn:aws:eks:${REGION}:${AWS_ACCOUNT_ID}:cluster/ticket-cluster"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ],
      "Resource": "arn:aws:sqs:${REGION}:${AWS_ACCOUNT_ID}:${CLUSTER_NAME}"
    }
  ]
}
```

#### EC2 Worker Node IAM Role (ticket-cluster-eks-worker-role)

이미 존재하는 역할에 다음 정책들이 연결되어 있어야 합니다:
- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly
- AmazonSSMManagedInstanceCore (SSM Agent용)

### 3. 네트워크 리소스 태깅

Karpenter가 올바른 서브넷과 보안 그룹을 찾을 수 있도록 태그를 추가합니다:

```bash
# 서브넷 태깅
aws ec2 create-tags \
  --resources subnet-xxxxx subnet-yyyyy \
  --tags Key=karpenter.sh/discovery,Value=ticket-cluster

# 보안 그룹 태깅  
aws ec2 create-tags \
  --resources sg-xxxxx \
  --tags Key=karpenter.sh/discovery,Value=ticket-cluster
```

### 4. Karpenter 설치

```bash
# Helm으로 Karpenter 설치
export KARPENTER_VERSION=1.0.0

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace karpenter \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole" \
  --set settings.clusterName="${CLUSTER_NAME}" \
  --set settings.interruptionQueue="${CLUSTER_NAME}" \
  --wait
```

## 🚀 설치 방법

### 1. EC2NodeClass 생성

```bash
kubectl apply -f ec2nodeclass.yaml
```

### 2. NodePool 생성

```bash
# On-Demand 중요 워크로드용
kubectl apply -f nodepool-ondemand-critical.yaml

# Spot 일반 워크로드용
kubectl apply -f nodepool-mixed-workload.yaml

# 부하 테스트용
kubectl apply -f nodepool-loadtest.yaml
```

### 3. 설치 확인

```bash
# Karpenter Pod 상태 확인
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# NodeClass 확인
kubectl get ec2nodeclass

# NodePool 확인
kubectl get nodepool

# Karpenter 로그 확인
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```