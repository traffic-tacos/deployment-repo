# ArgoCD 실제 배포 체크리스트

## 🔧 배포 전 필수 확인사항

### 1. 환경 정보 업데이트
실제 배포 전에 다음 값들을 실제 환경에 맞게 수정해야 합니다:

#### A. AWS 계정 및 리전 정보
```bash
# helm-values/argocd-prod-values.yaml에서 업데이트
- AWS_ACCOUNT_ID: 실제 AWS 계정 ID로 변경
- AWS_REGION: ap-northeast-2 (확인)
- CLUSTER_NAME: ticket-cluster (확인)
```

#### B. 도메인 및 인증서 설정
```bash
# 실제 도메인으로 업데이트 (현재: traffictacos.com)
- Route53 Hosted Zone 존재 확인
- ACM 인증서 발급 및 ARN 확인
- DNS 설정 권한 확인
```

#### C. GitHub 리포지터리 접근 설정
```bash
# GitHub Personal Access Token 준비
- GitHub Organizations: traffic-tacos 접근 권한
- Repository 접근 권한 확인
```

### 2. 사전 조건 체크

#### A. 필수 도구 설치 확인
```bash
✓ kubectl (1.28+)
✓ helm (3.12+)
✓ aws cli (2.0+)
✓ yq (4.0+)
```

#### B. 클러스터 접근 권한
```bash
# 다음 명령어들이 성공해야 함
kubectl cluster-info
kubectl get nodes
kubectl auth can-i create namespaces
```

#### C. AWS 권한 확인
```bash
# tacos 프로필로 다음 권한 확인
aws sts get-caller-identity --profile tacos
aws route53 list-hosted-zones --profile tacos
aws acm list-certificates --region ap-northeast-2 --profile tacos
```

## 🚀 단계별 배포 실행

### Phase 1: 검증 및 사전 준비
```bash
# 1. 배포 디렉터리로 이동
cd /path/to/deployment-repo

# 2. 실행 권한 부여
chmod +x deploy-argocd.sh

# 3. 사전 검증 실행
./deploy-argocd.sh validate
```

**예상 출력:**
```
[INFO] Checking prerequisites...
[SUCCESS] All prerequisites met
[INFO] Phase 3.2: Running validation tests...
[SUCCESS] Helm values syntax valid
[SUCCESS] All validations passed
```

### Phase 2: 실제 배포 실행
```bash
# 전체 배포 실행
./deploy-argocd.sh deploy
```

**예상 진행 단계:**
1. ✅ Environment Setup (네임스페이스, AWS 확인, Helm 리포)
2. ✅ Validation Tests (Helm 값, CRD, 매니페스트 검증)
3. ✅ Core Deployment (ArgoCD Helm 차트 배포)
4. ✅ Security Configuration (RBAC, 프로젝트 생성)
5. ✅ Application Setup (마이크로서비스 애플리케이션 등록)

### Phase 3: 배포 확인
```bash
# 헬스 체크 실행
./deploy-argocd.sh health

# 관리자 패스워드 확인
./deploy-argocd.sh password
```

## 🔍 배포 후 확인사항

### 1. Pod 상태 확인
```bash
kubectl get pods -n argocd
```

**예상 출력:**
```
NAME                                               READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                    1/1     Running   0          2m
argocd-server-5b4b7b8b7b-xxxxx                    1/1     Running   0          2m
argocd-server-5b4b7b8b7b-yyyyy                    1/1     Running   0          2m
argocd-repo-server-7b5b7b8b7b-xxxxx               1/1     Running   0          2m
argocd-repo-server-7b5b7b8b7b-yyyyy               1/1     Running   0          2m
argocd-redis-ha-haproxy-xxxxx                     1/1     Running   0          2m
argocd-redis-ha-server-0                          1/1     Running   0          2m
argocd-redis-ha-server-1                          1/1     Running   0          2m
argocd-redis-ha-server-2                          1/1     Running   0          2m
```

### 2. 서비스 및 Ingress 확인
```bash
kubectl get svc,ing -n argocd
```

### 3. ArgoCD UI 접근 확인
```bash
# 관리자 패스워드 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# UI 접근: https://argocd.traffictacos.com
# 사용자명: admin
# 패스워드: (위 명령어 출력값)
```

### 4. ArgoCD 프로젝트 및 애플리케이션 확인
```bash
# ArgoCD CLI를 통한 확인 (선택사항)
argocd login argocd.traffictacos.com --username admin
argocd proj list
argocd app list
```

## ⚠️ 문제 해결

### 일반적인 문제들:

#### 1. Ingress ALB가 생성되지 않는 경우
```bash
# AWS Load Balancer Controller 확인
kubectl get pods -n kube-system | grep aws-load-balancer-controller

# 로그 확인
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

#### 2. 인증서 문제
```bash
# ACM 인증서 상태 확인
aws acm describe-certificate --certificate-arn YOUR_CERT_ARN --region ap-northeast-2 --profile tacos
```

#### 3. DNS 해결 안됨
```bash
# Route53 레코드 확인
aws route53 list-resource-record-sets --hosted-zone-id YOUR_ZONE_ID --profile tacos
```

#### 4. Pod가 시작되지 않는 경우
```bash
# Pod 로그 확인
kubectl describe pod -n argocd POD_NAME
kubectl logs -n argocd POD_NAME
```

## 🎯 성공 기준

배포가 성공했다고 판단할 수 있는 기준:

- [ ] 모든 ArgoCD Pod가 Running 상태
- [ ] Ingress에서 ALB 주소 할당됨
- [ ] https://argocd.traffictacos.com 접근 가능
- [ ] admin 계정으로 로그인 성공
- [ ] traffic-tacos 프로젝트 생성 확인
- [ ] GitHub 리포지터리 연결 확인

## 📚 다음 단계

ArgoCD 배포가 완료되면:

1. **OIDC 인증 설정** (선택사항)
2. **GitHub 리포지터리 연결** 및 애플리케이션 배포
3. **모니터링 및 알림 설정**
4. **백업 전략 구현**
5. **Gateway API 및 나머지 애플리케이션 배포**

---

**💡 팁:** 처음 배포 시에는 `validate` 명령어로 검증을 먼저 실행해서 문제를 미리 파악하는 것을 권장합니다.