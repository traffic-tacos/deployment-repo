# ElastiCache Redis 사용 서비스 목록 및 설정

## 📊 개요

ElastiCache (Redis)를 사용하는 서비스: **3개**

| 서비스 | 네임스페이스 | Redis 설정 복잡도 | Secret 사용 | ConfigMap 사용 |
|--------|-------------|------------------|------------|---------------|
| **gateway-api** | tacos-app | 🔴 높음 | ✅ Yes | ❌ No |
| **reservation-api** | tacos-app | 🟡 중간 | ❌ No | ❌ No |
| **reservation-worker** | tacos-app | 🟢 낮음 | ❌ No | ❌ No |

## 🔍 서비스별 상세 설정

### 1. gateway-api (가장 복잡)

**현재 설정 (Standalone Mode):**
```yaml
env:
  - name: REDIS_ADDRESS
    value: master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379
  
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: redis-password  # Secret 사용!
        key: password
        optional: true
  
  - name: REDIS_TLS_ENABLED
    value: "true"
  
  - name: REDIS_TLS_INSECURE_SKIP_VERIFY
    value: "true"
  
  - name: REDIS_POOL_SIZE
    value: "50"
  
  - name: REDIS_POOL_TIMEOUT
    value: "3s"
```

**⚠️ Cluster Mode 변경 필요:**
- ✅ `REDIS_ADDRESS` → Cluster configuration endpoint로 변경
- ✅ `REDIS_CLUSTER_MODE` 환경변수 추가 필요 (애플리케이션 지원 시)
- ✅ Connection pool 설정 재검토

### 2. reservation-api

**현재 설정:**
```yaml
env:
  - name: REDIS_ADDRESS
    value: master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379
  
  - name: REDIS_TLS_ENABLED
    value: "true"
  
  - name: REDIS_TLS_INSECURE_SKIP_VERIFY
    value: "true"
```

**⚠️ Cluster Mode 변경 필요:**
- ✅ `REDIS_ADDRESS` → Cluster configuration endpoint로 변경
- ❓ Redis 클라이언트가 Cluster mode 지원하는지 확인 필요

### 3. reservation-worker

**현재 설정:**
```yaml
env:
  - name: REDIS_ADDRESS
    value: master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379
```

**⚠️ Cluster Mode 변경 필요:**
- ✅ `REDIS_ADDRESS` → Cluster configuration endpoint로 변경

## 🔑 Secret 및 ConfigMap

### Secret: redis-password

**위치:** `tacos-app` namespace  
**키:** `password`  
**사용 서비스:** gateway-api만 사용

```bash
# Secret 확인
kubectl get secret redis-password -n tacos-app
kubectl get secret redis-password -n tacos-app -o jsonpath='{.data.password}' | base64 -d
```

### ConfigMap: 없음

현재 Redis 관련 ConfigMap은 없으며, 모든 설정은 **Deployment에 하드코딩** 되어 있습니다.

## 🎯 Cluster Mode 전환 체크리스트

### 1. 새 ElastiCache Cluster 정보 확인

```bash
# IaC에서 확인
cd ../traffic-tacos-infra-iac
terraform output | grep redis

# 또는 AWS CLI
aws elasticache describe-replication-groups \
  --replication-group-id traffic-tacos-redis \
  --region ap-northeast-2 \
  --profile tacos \
  --query 'ReplicationGroups[0].ConfigurationEndpoint'
```

**필요한 정보:**
- ✅ Configuration Endpoint (Cluster mode)
- ✅ Port (기본 6379)
- ✅ AUTH token (Secrets Manager)

### 2. 애플리케이션 Redis 클라이언트 확인

각 서비스의 Redis 클라이언트 라이브러리가 **Cluster mode를 지원**하는지 확인:

**gateway-api (Go):**
- 예상 라이브러리: `github.com/go-redis/redis/v8` 또는 `github.com/redis/go-redis/v9`
- Cluster 지원: ✅ `redis.NewClusterClient()`

**reservation-api (Kotlin/Spring):**
- 예상 라이브러리: `spring-boot-starter-data-redis` + `lettuce-core`
- Cluster 지원: ✅ `spring.redis.cluster.nodes`

**reservation-worker (Go/Kotlin):**
- 확인 필요

### 3. 변경이 필요한 파일

```
deployment-repo/manifests/
├── gateway-api/
│   └── deployment.yaml           # REDIS_ADDRESS 변경
├── reservation-api/
│   └── deployment.yaml           # REDIS_ADDRESS 변경
└── reservation-worker/
    └── deployment.yaml           # REDIS_ADDRESS 변경
```

### 4. 변경 내용 (예시)

#### Standalone → Cluster Mode

**Before (Standalone):**
```yaml
- name: REDIS_ADDRESS
  value: master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379
```

**After (Cluster Mode):**
```yaml
# Option 1: Single configuration endpoint
- name: REDIS_CLUSTER_NODES
  value: traffic-tacos-redis.w6eqga.clustercfg.apn2.cache.amazonaws.com:6379

# Option 2: Multiple node endpoints (for discovery)
- name: REDIS_CLUSTER_NODES
  value: node1.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379,node2...,node3...

# Cluster mode flag (애플리케이션이 지원하는 경우)
- name: REDIS_CLUSTER_ENABLED
  value: "true"
```

## 📝 추가 고려사항

### Connection Pool 설정 재검토

**Cluster Mode에서는:**
- 각 샤드마다 별도 연결 풀 필요
- 기존 `REDIS_POOL_SIZE: 50`이 충분한지 재검토

**권장 설정:**
```yaml
# gateway-api
- name: REDIS_POOL_SIZE
  value: "100"  # Cluster mode에서는 더 많은 연결 필요
  
- name: REDIS_MAX_REDIRECTS
  value: "3"    # Cluster redirect 재시도 횟수
  
- name: REDIS_READ_ONLY
  value: "false" # Replica에서 읽기 허용 여부
```

### TLS 설정

Cluster mode에서도 TLS 유지:
```yaml
- name: REDIS_TLS_ENABLED
  value: "true"
  
- name: REDIS_TLS_INSECURE_SKIP_VERIFY
  value: "true"  # 프로덕션에서는 "false" 권장
```

### AUTH Token

gateway-api만 Secret 사용:
```yaml
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-password
      key: password
```

**다른 서비스도 AUTH token 필요 시:**
1. 동일한 `redis-password` Secret 사용
2. 또는 각 서비스별 Secret 생성

## 🚀 마이그레이션 순서

### Phase 1: 준비 (현재)
- [x] ElastiCache Cluster mode 생성 완료
- [ ] Configuration endpoint 확인
- [ ] 각 서비스의 Redis 클라이언트 Cluster 지원 확인

### Phase 2: 코드 검증
- [ ] 로컬/개발 환경에서 Cluster mode 테스트
- [ ] Connection pool 설정 최적화

### Phase 3: Deployment 변경
- [ ] `manifests/gateway-api/deployment.yaml` 수정
- [ ] `manifests/reservation-api/deployment.yaml` 수정
- [ ] `manifests/reservation-worker/deployment.yaml` 수정

### Phase 4: 배포 및 검증
- [ ] ArgoCD sync (또는 kubectl apply)
- [ ] Pod restart 확인
- [ ] Redis 연결 로그 확인
- [ ] 기능 테스트 (queue, reservation, etc.)

### Phase 5: 모니터링
- [ ] CloudWatch 메트릭 확인
- [ ] 애플리케이션 로그 모니터링 (24시간)
- [ ] 성능 비교 (Standalone vs Cluster)

## 🔗 관련 문서

- **ElastiCache 업그레이드 가이드**: `../traffic-tacos-infra-iac/ELASTICACHE-UPGRADE-GUIDE.md`
- **용량 계획**: `docs/ELASTICACHE-CAPACITY-PLANNING.md`
- **모니터링 스크립트**: `check-redis-status.sh`

---

**작성일**: 2025-10-07  
**상태**: ElastiCache Cluster mode 생성 완료, Deployment 변경 대기중
