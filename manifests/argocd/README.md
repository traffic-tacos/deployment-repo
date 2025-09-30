# ArgoCD 배포

## 📊 배포 상태

✅ **배포 완료** (2025-09-30)

### 배포된 컴포넌트
- ✅ ArgoCD Server (2 replicas)
- ✅ ArgoCD Application Controller (1 replica)
- ✅ ArgoCD Repo Server (2 replicas)
- ✅ ArgoCD ApplicationSet Controller (1 replica)
- ✅ ArgoCD Notifications Controller (1 replica)
- ✅ Redis (1 replica)

### Gateway API
- ✅ Gateway: `argocd-gateway`
- ✅ HTTPRoute: `argocd-server-route`
- ✅ HTTPRoute: `argocd-http-redirect` (HTTP → HTTPS)
- 🔄 ALB 프로비저닝 중

### AppProject
- ✅ `traffic-tacos` 프로젝트 생성

---

## 🔐 접속 정보

### ArgoCD UI
- **URL**: https://argocd.traffictacos.store (ALB 프로비저닝 완료 후)
- **ALB 주소**: `k8s-gateway-argocdga-db2deeb09e-971975766.ap-northeast-2.elb.amazonaws.com`
- **Username**: `admin`
- **Password**: `Le-l3nekqLi35-GD`

### Port Forward (임시)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# 접속: http://localhost:8080
```

---

## 📁 파일 구조

```
manifests/argocd/
├── README.md           # 이 파일
├── gateway.yaml        # ArgoCD Gateway
├── httproute.yaml      # HTTPRoute 설정
└── project.yaml        # traffic-tacos AppProject

helm-values/
└── argocd-values.yaml  # ArgoCD Helm values
```

---

## 🚀 다음 단계

### 1. DNS 레코드 확인
External DNS가 Route53 레코드를 자동 생성합니다:
```bash
# Route53 레코드 확인
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --profile tacos \
  --query "ResourceRecordSets[?Name=='argocd.traffictacos.store.']"
```

### 2. Gateway 상태 확인
```bash
kubectl get gateway argocd-gateway -n gateway
kubectl describe gateway argocd-gateway -n gateway
```

Gateway가 `PROGRAMMED=True` 상태가 되어야 합니다.

### 3. ArgoCD UI 접속
https://argocd.traffictacos.store 에 접속하여 로그인

### 4. GitHub 연동
ArgoCD에서 GitHub repository 연결:
```bash
# ArgoCD CLI 설치 (선택사항)
brew install argocd

# 로그인
argocd login argocd.traffictacos.store --username admin

# Repository 추가
argocd repo add https://github.com/traffic-tacos/<repo-name> \
  --type git \
  --name traffic-tacos \
  --project traffic-tacos
```

또는 UI에서:
1. Settings → Repositories → Connect Repo
2. GitHub Personal Access Token 입력

### 5. 애플리케이션 GitOps 전환
기존 배포된 애플리케이션을 ArgoCD로 관리:
```bash
# Application CRD 작성
cd applications/tacos/

# 각 애플리케이션별 Application 생성
kubectl apply -f gateway-api.yaml
kubectl apply -f reservation-api.yaml
# ...
```

---

## 🛠️ 유용한 명령어

### ArgoCD Pod 상태
```bash
kubectl get pods -n argocd
kubectl logs -f <pod-name> -n argocd
```

### Gateway 디버깅
```bash
kubectl describe gateway argocd-gateway -n gateway
kubectl describe httproute argocd-server-route -n argocd
kubectl get events -n gateway --sort-by='.lastTimestamp'
```

### ArgoCD 비밀번호 확인
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### ArgoCD 비밀번호 변경
```bash
# ArgoCD CLI로 비밀번호 변경
argocd account update-password
```

초기 secret은 보안상 삭제하는 것이 좋습니다:
```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

---

## 🔧 문제 해결

### Gateway PROGRAMMED=Unknown
ALB 프로비저닝은 2-5분 정도 소요됩니다. 기다려주세요.

### HTTPRoute가 작동하지 않음
```bash
# HTTPRoute 상태 확인
kubectl describe httproute argocd-server-route -n argocd

# Gateway와 HTTPRoute 연결 확인
kubectl get httproute argocd-server-route -n argocd -o yaml
```

### ArgoCD UI 접속 안됨
1. Port forward로 서버 작동 확인
2. Gateway ALB 주소 확인
3. Route53 레코드 확인
4. 보안 그룹 확인

---

## 📚 참고 문서

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [Gateway API 문서](https://gateway-api.sigs.k8s.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

---

**배포일**: 2025-09-30  
**ArgoCD 버전**: v3.1.7  
**Helm Chart 버전**: 8.5.7
