# Traffic Tacos Deployment Repository

Traffic Tacos 애플리케이션을 EKS 클러스터에 배포하는 GitOps 레포지토리입니다.

## 📚 주요 문서

- **[PLAN.md](./PLAN.md)**: 전체 배포 플랜 및 Phase별 작업 항목
- **[STATUS.md](./STATUS.md)**: 현재 배포 현황 및 문제 상황
- **[requirements.md](./requirements.md)**: 배포 요구사항
- **[DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)**: ArgoCD 배포 체크리스트

## 🚀 빠른 시작

### 1. 클러스터 접속
```bash
aws eks update-kubeconfig --name ticket-cluster --region ap-northeast-2 --profile tacos
kubectl cluster-info
```

### 2. 현재 상태 확인
```bash
# Gateway 확인
kubectl get gateway -n gateway
kubectl get httproute -A

# Applications 확인
kubectl get deploy -n tacos-app
kubectl get pods -n tacos-app
```

## 📊 현재 배포 상태 (2025-09-30)

- ✅ **Phase 1: Gateway API** - 완료
- ⏳ **Phase 2: ArgoCD** - 대기 중
- ⚠️ **Phase 3: Applications** - 부분 배포 (수정 필요)

자세한 내용은 [STATUS.md](./STATUS.md)를 참조하세요.

## 🏗️ 아키텍처

```
외부 트래픽
    ↓
Gateway (ALB) - api.traffictacos.store
    ↓
HTTPRoute
    ↓
┌─────────────────────────────────────┐
│  Kubernetes Cluster (EKS)           │
│                                      │
│  ┌──────────────┐   ┌─────────────┐ │
│  │  gateway-api │   │ ArgoCD      │ │
│  └──────┬───────┘   │ (예정)      │ │
│         │           └─────────────┘ │
│         ↓                            │
│  ┌──────────────────────────────┐   │
│  │  Backend Services            │   │
│  │  - reservation-api           │   │
│  │  - inventory-api             │   │
│  │  - payment-sim-api           │   │
│  │  - reservation-worker        │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## 📁 디렉토리 구조

```
deployment-repo/
├── PLAN.md                    # 전체 배포 플랜
├── STATUS.md                  # 현재 상태
├── requirements.md            # 요구사항
├── applications/              # ArgoCD Application CRDs
├── helm-values/              # Helm values files
├── manifests/                # Kubernetes manifests
│   ├── gateway/             # Gateway API 리소스
│   ├── argocd/              # ArgoCD 리소스
│   └── tacos/               # Application 리소스
├── common/                   # 공통 리소스
├── k6/                      # K6 부하 테스트
└── scripts/                 # 배포 스크립트
```

## 🎯 다음 단계

### 긴급 조치
1. AWS Secrets Store CSI Provider 문제 해결
2. gateway-api Redis 연결 문제 해결

### 단기 작업
3. ArgoCD 배포
4. 애플리케이션 GitOps 전환

자세한 내용은 [PLAN.md](./PLAN.md)의 "다음 단계" 섹션을 참조하세요.

## 🛠️ 유용한 명령어

```bash
# 전체 Pod 상태
kubectl get pods -A | grep -E 'gateway|argocd|tacos'

# Gateway 상태
kubectl get gateway,httproute -A

# 특정 Pod 로그
kubectl logs -f <pod-name> -n <namespace>

# 특정 Pod 디버깅
kubectl describe pod <pod-name> -n <namespace>
kubectl exec -it <pod-name> -n <namespace> -- sh
```

## 📞 연락처 및 참고

- **AWS Account**: 137406935518
- **Region**: ap-northeast-2
- **Cluster**: ticket-cluster
- **도메인**: traffictacos.store

---

**최종 업데이트**: 2025-09-30
