# K6 Load Test 전략 비교표

## 📊 테스트 시나리오 비교

| 항목 | 10k RPS | 30k RPS (목표!) |
|-----|---------|-----------------|
| **파드 수** | 3개 | 6개 |
| **파드당 RPS** | 3.3k | 5k |
| **총 목표 RPS** | 10,000 | 30,000 |
| **테스트 시간** | 20분 | 26분 |
| **Peak 지속** | 10분 | 15분 |

## 💻 리소스 요구사항

### 각 파드 리소스

| 리소스 | 10k (각 파드) | 30k (각 파드) |
|--------|--------------|--------------|
| **CPU Request** | 1.5 cores | 2 cores |
| **CPU Limit** | 2 cores | 3 cores |
| **Memory Request** | 3Gi | 4Gi |
| **Memory Limit** | 4Gi | 6Gi |
| **maxVUs** | 1,500 | 2,500 |

### 전체 클러스터 리소스

| 리소스 | 10k RPS (3 pods) | 30k RPS (6 pods) |
|--------|------------------|------------------|
| **총 CPU Request** | 4.5 cores | **12 cores** |
| **총 CPU Limit** | 6 cores | **18 cores** |
| **총 Memory Request** | 9Gi | **24Gi** |
| **총 Memory Limit** | 12Gi | **36Gi** |
| **총 maxVUs** | 4,500 | **15,000** |

## 🖥️ 필요 노드 수

| 노드 타입 | 10k RPS | 30k RPS |
|-----------|---------|---------|
| **t3a.large** (2c/8GB) | 3-4개 | ❌ 부족 |
| **t3a.xlarge** (4c/16GB) | 2-3개 | 4-5개 |
| **t3a.2xlarge** (8c/32GB) | 1-2개 | 2-3개 ✅ 권장 |

## 📈 부하 패턴

### 10k RPS 패턴
```
0-2분:   0 → 1k
2-7분:   1k → 3.3k
7-17분:  3.3k (hold 10분)
17-20분: 3.3k → 0
```

### 30k RPS 패턴
```
0-3분:   0 → 2k
3-8분:   2k → 5k
8-23분:  5k (hold 15분!) ⭐
23-26분: 5k → 0
```

## 🚀 실행 가이드

### 10k RPS 테스트

```bash
# 1. ConfigMap 생성
kubectl apply -f manifests/k6/job/k6-configmap-10k-distributed.yaml

# 2. Job 실행
kubectl apply -f manifests/k6/job/k6-job-parallel-10k.yaml

# 3. 모니터링
kubectl get pods -n load-test -l test=10k-distributed -o wide

# 4. 정리
kubectl delete job -n load-test -l test=10k-distributed
kubectl delete cm -n load-test -l test=10k-distributed
```

### 30k RPS 테스트

```bash
# 빠른 실행 (스크립트 사용)
cd manifests/k6/job
./run-30k-test.sh

# 또는 수동 실행
kubectl apply -f k6-configmap-30k-distributed.yaml
kubectl apply -f k6-job-parallel-30k.yaml

# 정리 (스크립트)
./cleanup-30k-test.sh

# 또는 수동 정리
kubectl delete job -n load-test -l test=30k-distributed
kubectl delete cm -n load-test -l test=30k-distributed
```

## 📁 파일 목록

### 10k RPS
- `k6-configmap-10k-distributed.yaml` - ConfigMap (3개)
- `k6-job-parallel-10k.yaml` - Job 정의 (3개)
- `README-DISTRIBUTED-10K.md` - 상세 가이드

### 30k RPS
- `k6-configmap-30k-distributed.yaml` - ConfigMap (6개)
- `k6-job-parallel-30k.yaml` - Job 정의 (6개)
- `README-DISTRIBUTED-30K.md` - 상세 가이드
- `run-30k-test.sh` - 실행 스크립트 ⭐
- `cleanup-30k-test.sh` - 정리 스크립트 ⭐

## 🎯 성공 기준

### 10k RPS
- ✅ 총 RPS: 9k-10k
- ✅ P95 Latency: < 5초
- ✅ P99 Latency: < 7초
- ✅ 실패율: < 10%

### 30k RPS
- ✅ 총 RPS: 28k-30k
- ✅ P95 Latency: < 5초
- ✅ P99 Latency: < 8초
- ✅ 실패율: < 15%

## 📊 Prometheus 쿼리

### 10k RPS
```promql
# 전체 RPS
sum(rate(http_reqs_total{test="10k"}[1m]))

# Part별 RPS
sum by(part) (rate(http_reqs_total{test="10k"}[1m]))

# P95 Latency
histogram_quantile(0.95, sum(rate(http_req_duration_bucket{test="10k"}[1m])) by (le))
```

### 30k RPS
```promql
# 전체 RPS
sum(rate(http_reqs_total{test="30k"}[1m]))

# Part별 RPS
sum by(part) (rate(http_reqs_total{test="30k"}[1m]))

# P95 Latency
histogram_quantile(0.95, sum(rate(http_req_duration_bucket{test="30k"}[1m])) by (le))

# P99 Latency
histogram_quantile(0.99, sum(rate(http_req_duration_bucket{test="30k"}[1m])) by (le))
```

## ⚠️ 주의사항

### 10k RPS
- 🟢 **난이도**: 중간
- 🟢 **노드 요구사항**: 보통
- 🟢 **실패 위험**: 낮음

### 30k RPS
- 🔴 **난이도**: 높음
- 🔴 **노드 요구사항**: 매우 높음 (12+ cores, 24Gi+ memory)
- 🔴 **실패 위험**: 높음 (리소스 부족, 백엔드 병목 가능)
- ⚠️ **사전 확인 필수**: 충분한 노드 리소스 확보

## 🔄 진행 순서 권장

1. ✅ **10k RPS 성공** (먼저 검증)
   - 시스템 안정성 확인
   - 병목 구간 파악
   - 리소스 사용 패턴 분석

2. 🔧 **최적화**
   - HPA 튜닝
   - Connection pool 조정
   - 캐시 전략 개선

3. 🚀 **30k RPS 도전**
   - 노드 리소스 충분히 확보
   - Karpenter 동작 확인
   - 단계적 실행 (처음엔 3-4개 파드부터)

## 💡 팁

### 단계적 30k 접근

**Step 1**: 15k RPS (3개 파드)
```bash
# 30k ConfigMap 사용하지만 Job은 Part 1-3만 실행
kubectl apply -f k6-configmap-30k-distributed.yaml
kubectl apply -f k6-job-parallel-30k.yaml
kubectl delete job k6-loadtest-30k-part4 k6-loadtest-30k-part5 k6-loadtest-30k-part6 -n load-test
```

**Step 2**: 20k RPS (4개 파드)
```bash
# Part 1-4만 실행
```

**Step 3**: 30k RPS (전체 6개)
```bash
# 전체 실행
./run-30k-test.sh
```

## 📚 추가 리소스

- **K6 공식 문서**: https://k6.io/docs/
- **Distributed Testing**: https://k6.io/docs/testing-guides/running-distributed-tests/
- **K6 Operator**: https://github.com/grafana/k6-operator

---

**준비되셨나요? 10k로 시작해서 30k까지 정복해보세요! 🚀**
