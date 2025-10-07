# ElastiCache Redis 용량 계획 - 30k RPS 대응

## 📊 현재 상태 분석 (10k RPS 부하 중)

### 🔴 **현재 구성** - **매우 부족!**

| 항목 | 현재 값 | 상태 |
|-----|--------|------|
| **노드 타입** | `cache.t3.micro` | 🔴 **매우 작음** |
| **노드 수** | 2개 (Primary + Replica) | 🟡 **보통** |
| **메모리** | 512MB × 2 = 1GB | 🔴 **매우 부족** |
| **vCPU** | 2 cores × 2 = 4 cores | 🔴 **매우 부족** |
| **네트워크** | 최대 5 Gbps | 🟡 **보통** |
| **최대 연결 수** | ~65,000 | 🟢 **충분** |

### 📈 **실시간 메트릭 (10k RPS 부하 중)**

```
시간: 2025-10-07 04:15~04:20 (KST 13:15~13:20)

CPU 사용률:
  • 평균: 53-54%
  • 최대: 54%
  • 🔴 상태: 높음 (t3.micro는 50% 이상이면 위험)

현재 연결 수:
  • 초기: 585개
  • 현재: 958개 (계속 증가 중!)
  • 🔴 상태: 급증 중 (connection pool timeout 발생)

캐시 히트 (Operations):
  • 분당: 226,000 ~ 256,000 hits
  • 초당: 약 4,000 ops
  • 🔴 상태: t3.micro 한계 (5,000 ops/sec) 근접

메모리 사용률:
  • 78% → 90% (5분간 12% 증가!)
  • 🔴 상태: 매우 위험 (90% 이상이면 eviction 시작)
```

### 🚨 **심각한 문제점**

1. **메모리 고갈 임박**
   - 90% 사용률 → Eviction 발생 가능
   - 512MB는 queue 데이터 + Lua script + 연결 상태 저장하기에 부족

2. **CPU 병목**
   - t3.micro의 2 vCPU로는 4,000 ops/sec 처리 한계
   - Lua script 실행으로 CPU 사용률 급증

3. **연결 수 폭증**
   - gateway-api 16개 파드 × ~60 연결/파드 = ~960 연결
   - Connection pool timeout 발생 중

4. **네트워크 대역폭**
   - Queue 데이터 + Stream + Heartbeat → 높은 네트워크 사용

## 🎯 30k RPS 대응 플랜

### 계산 기반

**10k RPS 기준:**
- CPU: 54%
- 메모리: 90%
- 연결: 958개
- Operations: 4,000 ops/sec

**30k RPS 예상 (3배 증가):**
- CPU: 162% (t3.micro로는 불가능)
- 메모리: 270% (1.5GB+ 필요)
- 연결: 2,874개
- Operations: 12,000 ops/sec

### 📋 권장 구성

#### ✅ **Option 1: cache.r7g.large** (권장!)

| 항목 | 스펙 | 30k RPS 대응 |
|-----|------|------------|
| **타입** | cache.r7g.large (ARM64) | ✅ |
| **vCPU** | 2 cores (Graviton3) | ✅ **고성능** |
| **메모리** | 13.07 GB | ✅ **26배 증가** |
| **네트워크** | 최대 12.5 Gbps | ✅ **충분** |
| **최대 연결** | ~65,000 | ✅ **충분** |
| **예상 성능** | ~25,000 ops/sec | ✅ **충분** |
| **가격** | ~$0.158/hour (~$115/month) | 💰 **합리적** |

**예상 사용률 (30k RPS):**
- CPU: 40-50% ✅
- 메모리: 10-15% ✅
- Operations: 12,000 ops/sec (50% 여유) ✅

#### 🟡 **Option 2: cache.m7g.large** (대안)

| 항목 | 스펙 | 30k RPS 대응 |
|-----|------|------------|
| **타입** | cache.m7g.large (ARM64) | ✅ |
| **vCPU** | 2 cores (Graviton3) | ✅ **고성능** |
| **메모리** | 6.38 GB | 🟡 **12배 증가** |
| **네트워크** | 최대 12.5 Gbps | ✅ **충분** |
| **최대 연결** | ~65,000 | ✅ **충분** |
| **예상 성능** | ~20,000 ops/sec | ✅ **충분** |
| **가격** | ~$0.126/hour (~$92/month) | 💰 **저렴** |

**예상 사용률 (30k RPS):**
- CPU: 45-55% ✅
- 메모리: 25-30% 🟡
- Operations: 12,000 ops/sec (40% 여유) ✅

#### ⚡ **Option 3: cache.r7g.xlarge** (고성능)

| 항목 | 스펙 | 50k+ RPS 대응 |
|-----|------|------------|
| **타입** | cache.r7g.xlarge (ARM64) | ✅ |
| **vCPU** | 4 cores (Graviton3) | ✅ **매우 고성능** |
| **메모리** | 26.32 GB | ✅ **52배 증가** |
| **네트워크** | 최대 12.5 Gbps | ✅ **충분** |
| **최대 연결** | ~65,000 | ✅ **충분** |
| **예상 성능** | ~50,000 ops/sec | ✅ **여유 충분** |
| **가격** | ~$0.316/hour (~$230/month) | 💰 **고가** |

**예상 사용률 (30k RPS):**
- CPU: 25-30% ✅
- 메모리: 8-10% ✅
- Operations: 12,000 ops/sec (75% 여유) ✅

### 🏆 **최종 권장: cache.r7g.large**

**이유:**
1. ✅ **메모리 충분**: 13GB로 queue + stream + script 데이터 여유
2. ✅ **성능 충분**: Graviton3 2 cores로 30k RPS 처리 가능
3. ✅ **가격 합리적**: t3.micro ($9/month) → r7g.large ($115/month)
4. ✅ **확장 여유**: 40k RPS까지 대응 가능
5. ✅ **ARM64 최적화**: 20-40% 성능 향상

## 📋 마이그레이션 계획

### Phase 1: 긴급 조치 (10k RPS 안정화)

**즉시 실행:**

```bash
# 1. gateway-api replica 축소 (연결 수 감소)
kubectl scale deployment gateway-api -n tacos-app --replicas=8

# 2. Redis connection pool 최적화 (gateway-api 코드)
# MaxIdle: 10 → 5
# MaxActive: 100 → 50
# IdleTimeout: 240s → 120s
```

### Phase 2: ElastiCache 업그레이드 (30k RPS 대비)

**Step 1: 백업 생성**
```bash
aws elasticache create-snapshot \
  --replication-group-id traffic-tacos-redis \
  --snapshot-name traffic-tacos-redis-backup-$(date +%Y%m%d) \
  --region ap-northeast-2 \
  --profile tacos
```

**Step 2: 인스턴스 타입 변경**
```bash
aws elasticache modify-replication-group \
  --replication-group-id traffic-tacos-redis \
  --cache-node-type cache.r7g.large \
  --apply-immediately \
  --region ap-northeast-2 \
  --profile tacos
```

**소요 시간:** 약 15-30분 (Multi-AZ 환경에서는 downtime 최소화)

**Step 3: 변경 확인**
```bash
aws elasticache describe-replication-groups \
  --replication-group-id traffic-tacos-redis \
  --region ap-northeast-2 \
  --profile tacos \
  --query 'ReplicationGroups[0].[CacheNodeType,Status]'
```

### Phase 3: 모니터링 및 검증

**CloudWatch 메트릭 확인:**
```bash
# CPU 사용률
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name CPUUtilization \
  --dimensions Name=CacheClusterId,Value=traffic-tacos-redis-001 \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 300 \
  --statistics Average Maximum \
  --region ap-northeast-2 \
  --profile tacos

# 메모리 사용률
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=CacheClusterId,Value=traffic-tacos-redis-001 \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 300 \
  --statistics Average Maximum \
  --region ap-northeast-2 \
  --profile tacos
```

## 💰 비용 비교

| 타입 | 월 비용 (On-Demand) | 월 비용 (Reserved 1yr) | 30k RPS 대응 |
|-----|-------------------|---------------------|------------|
| **cache.t3.micro** (현재) | ~$9 | ~$6 | ❌ **불가능** |
| **cache.m7g.large** | ~$92 | ~$60 | 🟡 **가능 (타이트)** |
| **cache.r7g.large** | ~$115 | ~$75 | ✅ **충분** |
| **cache.r7g.xlarge** | ~$230 | ~$150 | ✅ **여유 충분** |

**권장:** cache.r7g.large (Reserved Instance 1년 약정 시 $75/month)

## 🔧 추가 최적화 사항

### 1. Connection Pool 튜닝 (gateway-api)

**현재 (예상):**
```go
MaxIdle: 10
MaxActive: 100
IdleTimeout: 240s
```

**권장 (30k RPS):**
```go
MaxIdle: 20
MaxActive: 200
IdleTimeout: 180s
ConnectTimeout: 5s
ReadTimeout: 3s
WriteTimeout: 3s
```

### 2. Redis 설정 최적화

**maxmemory-policy:**
```
allkeys-lru  # 메모리 부족 시 LRU 방식으로 eviction
```

**timeout:**
```
300  # 5분 idle connection 자동 종료
```

### 3. 읽기 분산 (Reader Endpoint 활용)

**현재:** Primary만 사용
```
REDIS_ADDRESS=master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379
```

**최적화:** Reader Endpoint 추가 활용
```go
// 읽기 전용 작업은 Replica로 분산
primaryClient := redis.NewClient(&redis.Options{
    Addr: "master.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379",
})

replicaClient := redis.NewClient(&redis.Options{
    Addr: "replica.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com:6379",
})

// queue/status 조회 → Replica
// queue/join, queue/enter → Primary
```

### 4. 모니터링 알람 설정

**CloudWatch 알람:**

```bash
# CPU 알람 (70% 이상)
aws cloudwatch put-metric-alarm \
  --alarm-name traffic-tacos-redis-high-cpu \
  --alarm-description "Redis CPU > 70%" \
  --metric-name CPUUtilization \
  --namespace AWS/ElastiCache \
  --statistic Average \
  --period 300 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=CacheClusterId,Value=traffic-tacos-redis-001 \
  --evaluation-periods 2 \
  --region ap-northeast-2 \
  --profile tacos

# 메모리 알람 (80% 이상)
aws cloudwatch put-metric-alarm \
  --alarm-name traffic-tacos-redis-high-memory \
  --alarm-description "Redis Memory > 80%" \
  --metric-name DatabaseMemoryUsagePercentage \
  --namespace AWS/ElastiCache \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=CacheClusterId,Value=traffic-tacos-redis-001 \
  --evaluation-periods 2 \
  --region ap-northeast-2 \
  --profile tacos

# 연결 수 알람 (5,000개 이상)
aws cloudwatch put-metric-alarm \
  --alarm-name traffic-tacos-redis-high-connections \
  --alarm-description "Redis Connections > 5000" \
  --metric-name CurrConnections \
  --namespace AWS/ElastiCache \
  --statistic Average \
  --period 300 \
  --threshold 5000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=CacheClusterId,Value=traffic-tacos-redis-001 \
  --evaluation-periods 2 \
  --region ap-northeast-2 \
  --profile tacos
```

## 📈 예상 성능 개선

### 업그레이드 후 (cache.r7g.large)

**10k RPS:**
- CPU: 54% → **15-20%** (2.7배 개선)
- 메모리: 90% → **8-10%** (26배 여유)
- 연결 타임아웃: **없음**
- 응답 시간: **50% 개선**

**30k RPS:**
- CPU: **40-50%** ✅
- 메모리: **15-20%** ✅
- 연결 수: 2,874개 ✅
- Operations: 12,000 ops/sec ✅

## 🎯 실행 체크리스트

### 즉시 실행 (10k RPS 안정화)
- [ ] gateway-api replica 8개로 축소
- [ ] Redis connection pool 튜닝 (코드 수정 필요)
- [ ] 현재 메트릭 baseline 수집

### 1주일 내 실행 (30k RPS 대비)
- [ ] ElastiCache 백업 생성
- [ ] cache.r7g.large로 업그레이드
- [ ] Reader Endpoint 활용 (코드 수정)
- [ ] CloudWatch 알람 설정
- [ ] 10k RPS 재테스트 (성능 개선 확인)

### 업그레이드 후 (검증)
- [ ] 30k RPS 로드 테스트 실행
- [ ] 메트릭 모니터링 (24시간)
- [ ] 비용 분석 및 Reserved Instance 전환 검토

---

**생성일:** 2025-10-07
**분석 기간:** 2025-10-07 04:15~04:20 (KST 13:15~13:20)
**현재 부하:** 10k RPS
**목표 부하:** 30k RPS
