# 배포 현황 (2025-09-30 21:45)

## 🔍 빠른 상태 확인

```bash
# 클러스터 접속
aws eks update-kubeconfig --name ticket-cluster --region ap-northeast-2 --profile tacos

# Gateway 확인
kubectl get gateway -n gateway
kubectl get httproute -n tacos-app

# ArgoCD 확인
kubectl get pods -n argocd

# Applications 확인
kubectl get deploy -n tacos-app
kubectl get pods -n tacos-app
```

---

## ✅ 완료된 작업

### Phase 1: Gateway API ✅
- **Gateway**: `api-traffictacos-gateway` (정상 작동)
- **도메인**: `api.traffictacos.store`
- **ALB**: `k8s-gateway-apitraff-bd9ec75eb6-309235565.ap-northeast-2.elb.amazonaws.com`
- **HTTPRoute**: 2개 설정됨
- **상태**: **완전히 작동 중**

---

## ⚠️ 진행 중 / 문제 있는 작업

### Phase 2: ArgoCD ⏳
- **네임스페이스**: ✅ 생성됨
- **Pods**: ❌ 배포 안됨
- **상태**: **배포 대기 중**

### Phase 3: Applications ⚠️

#### 정상 작동 서비스 ✅
1. **reservation-api** (정상)
2. **inventory-api** (정상)
3. **payment-sim-api** (정상)
4. **reservation-worker** (정상)

#### 문제 있는 서비스 ❌
5. **gateway-api** (0/2 Ready)

**문제 원인:**
1. AWS Secrets Store CSI Provider Pod가 해당 노드에 없음
2. Redis 연결 실패 (타임아웃)

---

## 🚨 해결 필요한 문제

### 1. AWS Secrets Store CSI Provider 배포 불완전

**현황:**
```bash
# Provider Pod 위치
ip-10-180-7-201: ✅ Provider 있음
ip-10-180-9-3:   ✅ Provider 있음
ip-10-180-8-31:  ❌ Provider 없음 (gateway-api Pod 위치)
```

**확인 명령어:**
```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws -o wide
kubectl get daemonset csi-secrets-provider-aws-secrets-store-csi-driver-provider-aws -n kube-system
```

**해결 방법:**
- Option 1: DaemonSet nodeSelector 수정
- Option 2: gateway-api nodeAffinity 추가

### 2. gateway-api Redis 연결 실패

**에러:**
```
failed to connect to Redis: i/o timeout
```

**Redis 엔드포인트:**
```
master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379
```

**확인 필요:**
1. ElastiCache 보안 그룹 설정
2. NetworkPolicy 설정
3. VPC 라우팅

**확인 명령어:**
```bash
# ElastiCache 정보
aws elasticache describe-cache-clusters \
  --cache-cluster-id traffic-tacos-redis \
  --region ap-northeast-2 \
  --profile tacos \
  --show-cache-node-info

# 보안 그룹
aws elasticache describe-cache-clusters \
  --cache-cluster-id traffic-tacos-redis \
  --region ap-northeast-2 \
  --profile tacos \
  --query 'CacheClusters[0].SecurityGroups'

# NetworkPolicy 확인
kubectl get networkpolicy -n tacos-app
```

### 3. SecretProviderClass 설정 (수정 완료) ✅

**수정 내역:**
- jmesPath 필드 제거
- objectAlias 설정 유지

---

## 📊 클러스터 리소스

### 네임스페이스
```
gateway      (5일 23시간 전)
tacos-app    (7일 10시간 전)
argocd       (존재하지만 Pod 없음)
monitoring   (존재)
```

### Gateway API 리소스
```
GatewayClass:
- aws-alb-gateway-class (AWS ALB Controller)
- istio (Istio)
- istio-remote (Istio)
- istio-waypoint (Istio)

Gateway:
- api-traffictacos-gateway (gateway namespace)
  - Listeners: HTTP (80), HTTPS (443)
  - TLS: ACM 인증서 적용
  - Status: PROGRAMMED=True

HTTPRoute:
- api-traffictacos-route (tacos-app namespace)
- http-redirect-route (tacos-app namespace)
```

### 주요 CRD
```
- Gateway API v1
- AWS Gateway API Extensions
- Istio Gateway
- Secrets Store CSI Driver
```

---

## 🎯 다음 액션

### 🚨 긴급 (오늘)
1. [ ] AWS Secrets Store CSI Provider 문제 해결
2. [ ] gateway-api Redis 연결 문제 해결
3. [ ] gateway-api Pod 정상화 확인

### 📅 단기 (이번 주)
4. [ ] ArgoCD 배포
5. [ ] ArgoCD HTTPRoute 설정
6. [ ] GitHub 연동
7. [ ] 기존 애플리케이션 GitOps 전환

### 📅 중기 (다음 주)
8. [ ] HPA 설정 및 테스트
9. [ ] K6 부하 테스트 (3만 RPS)
10. [ ] NetworkPolicy 적용
11. [ ] 모니터링 구성

---

## 🔧 유용한 명령어

### Gateway 확인
```bash
kubectl get gateway -A
kubectl get httproute -A
kubectl describe gateway api-traffictacos-gateway -n gateway
```

### Pod 상태 확인
```bash
kubectl get pods -n tacos-app
kubectl describe pod <pod-name> -n tacos-app
kubectl logs <pod-name> -n tacos-app
```

### Secrets Store CSI
```bash
kubectl get secretproviderclass -n tacos-app
kubectl get pods -n kube-system | grep secrets
kubectl describe pod <gateway-api-pod> -n tacos-app
```

### Redis 연결 테스트
```bash
# Pod 내에서
kubectl exec -it <gateway-api-pod> -n tacos-app -- sh
nc -zv master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com 6379
```

---

**마지막 업데이트**: 2025-09-30 21:45  
**다음 체크포인트**: 문제 해결 후
