# K6 Distributed Load Test - 30k RPS 🚀

## 📊 개요

**30k RPS**는 매우 큰 부하이므로 **6개의 병렬 Job**으로 분산하여 각각 5k RPS씩 처리합니다.

### 부하 분산 전략
- **Part 1-6**: 각각 5k RPS
- **합계**: 30k RPS (목표 RPS!)

### 단계별 부하 패턴 (총 26분)
```
0-3분:   0 → 2k RPS (Warm-up)
3-8분:   2k → 5k RPS (Ramp-up)
8-23분:  5k RPS 유지 (Peak load - 15분간!)
23-26분: 5k → 0 RPS (Ramp-down)
```

**각 Part가 위 패턴을 동시에 실행하여 총 30k RPS 달성!**

## ⚠️ 주의사항

### 리소스 요구사항이 매우 큽니다!

#### 각 Job Pod
- **CPU**: 2 cores (request), 3 cores (limit)
- **Memory**: 4Gi (request), 6Gi (limit)
- **maxVUs**: 2500 VUs per job

#### 전체 (6 Jobs)
- **총 CPU**: **12 cores** (request), **18 cores** (limit)
- **총 Memory**: **24Gi** (request), **36Gi** (limit)
- **총 VUs**: 최대 **15,000 VUs**

#### 필요 노드
- **최소**: t3a.xlarge (4 cores, 16GB) × 3-4개
- **권장**: t3a.2xlarge (8 cores, 32GB) × 2-3개
- **Karpenter**: loadtest nodepool에 충분한 노드 확보 필요

## 🚀 실행 방법

### 0. 사전 확인 (필수!)

```bash
# loadtest 노드 상태 확인
kubectl get nodes -l workload-type=loadtest -o wide

# 현재 리소스 사용량
kubectl top nodes -l workload-type=loadtest

# Karpenter가 노드를 추가로 생성할 수 있는지 확인
kubectl get nodepools loadtest -o yaml | grep -A 5 limits

# ⚠️ 만약 노드가 부족하면 Karpenter가 자동으로 생성하지만
# 6개 파드를 동시에 스케줄하려면 충분한 용량이 필요합니다!
```

### 1. ConfigMap 적용
```bash
kubectl apply -f manifests/k6/job/k6-configmap-30k-distributed.yaml
```

**확인:**
```bash
kubectl get cm -n load-test -l test=30k-distributed
# 6개의 ConfigMap이 생성되어야 함
```

### 2. Job 실행 (병렬 6개)
```bash
kubectl apply -f manifests/k6/job/k6-job-parallel-30k.yaml
```

**확인:**
```bash
# Job 상태
kubectl get jobs -n load-test -l test=30k-distributed

# Pod 상태
kubectl get pods -n load-test -l test=30k-distributed -o wide

# 모든 파드가 Pending이 아닌 Running 상태인지 확인!
```

### 3. 실시간 모니터링

#### 파드 상태 Watch
```bash
watch -n 2 'kubectl get pods -n load-test -l test=30k-distributed -o wide'
```

#### 로그 확인
```bash
# 모든 Part 로그 동시에 보기
kubectl logs -n load-test -l test=30k-distributed --all-containers=true -f

# 특정 Part만 보기
kubectl logs -n load-test -l part=1 -f
```

#### 리소스 사용량 모니터링
```bash
# 실시간 리소스 모니터링
watch -n 5 'kubectl top pods -n load-test -l test=30k-distributed'

# 노드 리소스
watch -n 5 'kubectl top nodes -l workload-type=loadtest'
```

## 📈 결과 확인

### Grafana Dashboard

**Prometheus 쿼리:**

```promql
# 전체 RPS (30k 목표)
sum(rate(http_reqs_total{test="30k"}[1m]))

# Part별 RPS (각 5k 목표)
sum(rate(http_reqs_total{test="30k",part="1"}[1m]))
sum(rate(http_reqs_total{test="30k",part="2"}[1m]))
sum(rate(http_reqs_total{test="30k",part="3"}[1m]))
sum(rate(http_reqs_total{test="30k",part="4"}[1m]))
sum(rate(http_reqs_total{test="30k",part="5"}[1m]))
sum(rate(http_reqs_total{test="30k",part="6"}[1m]))

# P95 Latency
histogram_quantile(0.95, sum(rate(http_req_duration_bucket{test="30k"}[1m])) by (le))

# P99 Latency
histogram_quantile(0.99, sum(rate(http_req_duration_bucket{test="30k"}[1m])) by (le))

# 실패율
rate(http_req_failed_total{test="30k"}[1m]) / rate(http_reqs_total{test="30k"}[1m])

# 완료된 플로우
sum(rate(completed_flows_total{test="30k"}[1m]))
```

### 예상 결과

**성공 시나리오:**
- ✅ 전체 RPS: 28k-30k (목표 달성!)
- ✅ P95 Latency: < 5초
- ✅ P99 Latency: < 8초
- ✅ 실패율: < 15%

**부분 성공:**
- ⚠️ 전체 RPS: 20k-28k (부하 분산 효과는 있음)
- ⚠️ 일부 Pod OOMKilled (메모리 증가 필요)

**실패 시나리오:**
- ❌ Pod 대부분 Pending (노드 리소스 부족)
- ❌ Pod OOMKilled 반복 (메모리 한계)
- ❌ P99 Latency > 10초 (백엔드 병목)

## 🧹 정리

### 실행 중인 Job 확인
```bash
kubectl get jobs -n load-test -l test=30k-distributed
```

### Job 삭제
```bash
kubectl delete job -n load-test -l test=30k-distributed
```

### ConfigMap 삭제
```bash
kubectl delete cm -n load-test -l test=30k-distributed
```

### 한 번에 전체 삭제
```bash
kubectl delete -f manifests/k6/job/k6-job-parallel-30k.yaml
kubectl delete -f manifests/k6/job/k6-configmap-30k-distributed.yaml
```

## 🔧 Troubleshooting

### 1. Pod가 Pending 상태로 멈춤

**원인:** 노드 리소스 부족

**해결:**
```bash
# Karpenter가 노드를 생성하는지 확인
kubectl get nodeclaims -l karpenter.sh/nodepool=loadtest

# 수동으로 NodePool 스케일 확인
kubectl describe nodepool loadtest

# 임시 해결: 일부 Job만 실행
kubectl apply -f manifests/k6/job/k6-job-parallel-30k.yaml
# 그런 다음 일부 Job 삭제
kubectl delete job k6-loadtest-30k-part5 k6-loadtest-30k-part6 -n load-test
```

### 2. Pod가 OOMKilled

**원인:** 메모리 부족

**해결:** Job YAML에서 메모리 증가
```yaml
resources:
  requests:
    memory: "6Gi"  # 4Gi → 6Gi
  limits:
    memory: "8Gi"  # 6Gi → 8Gi
```

### 3. RPS가 목표에 크게 못 미침

**원인:** 
- 백엔드 병목
- K6 파드 CPU 제한
- 네트워크 대역폭 부족

**확인:**
```bash
# K6 파드 CPU 사용률
kubectl top pods -n load-test -l test=30k-distributed

# 백엔드 API 파드 상태
kubectl get pods -n tacos-app -l app=gateway-api
kubectl top pods -n tacos-app -l app=gateway-api
```

**해결:**
- CPU limit 증가
- maxVUs 증가
- 백엔드 스케일 아웃

### 4. 일부 Part만 실행되고 나머지는 Pending

**원인:** 순차적 스케줄링

**대기:** Karpenter가 노드를 추가로 생성할 때까지 2-5분 대기

**확인:**
```bash
# 새 노드가 생성되는지 확인
watch -n 5 'kubectl get nodes -l workload-type=loadtest'
```

## 📊 비교: 10k vs 30k

| 항목 | 10k RPS | 30k RPS |
|---|---|---|
| **파드 수** | 3개 | 6개 |
| **파드당 부하** | 3.3k RPS | 5k RPS |
| **총 CPU** | 4.5-6 cores | 12-18 cores |
| **총 Memory** | 9-12Gi | 24-36Gi |
| **maxVUs** | 4,500 | 15,000 |
| **테스트 시간** | 20분 | 26분 |
| **필요 노드** | 2-3개 | 4-6개 |

## 🎯 성공 체크리스트

실행 전 확인:
- [ ] loadtest 노드 최소 3개 이상
- [ ] 총 CPU 여유: 18 cores 이상
- [ ] 총 Memory 여유: 40Gi 이상
- [ ] Karpenter nodepool 정상 작동
- [ ] 백엔드 API 정상 상태

실행 중 모니터링:
- [ ] 6개 파드 모두 Running 상태
- [ ] OOMKilled 없음
- [ ] 각 Part가 5k RPS 달성
- [ ] P95 Latency < 5초
- [ ] 실패율 < 15%

## 🚀 다음 단계

### 30k 성공 후

1. **결과 분석**
   - Grafana 대시보드 스크린샷
   - 병목 구간 식별
   - 리소스 사용 패턴 분석

2. **최적화**
   - 백엔드 API HPA 튜닝
   - Database connection pool 조정
   - Redis 캐시 히트율 개선

3. **K6 Operator로 전환**
   - 더 쉬운 관리
   - 자동 부하 분산
   - 통합된 결과 수집

### 50k RPS 도전?

30k가 안정적이면:
- 10개 파드로 확장 (각 5k RPS)
- 또는 6개 파드 + 각 8-9k RPS

## 📝 참고

- **10k 테스트**: `README-DISTRIBUTED-10K.md`
- **K6 공식 문서**: https://k6.io/docs/
- **K6 Operator**: https://github.com/grafana/k6-operator

---

**Good luck with 30k RPS! 🎉**
