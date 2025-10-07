# K6 Distributed Load Test - 10k RPS

## 📊 개요

단일 파드로 10k RPS를 감당하기 어려워 **3개의 병렬 Job**으로 부하를 분산합니다.

### 부하 분산 전략
- **Part 1**: 3.3k RPS
- **Part 2**: 3.3k RPS  
- **Part 3**: 3.4k RPS
- **합계**: 10k RPS

### 단계별 부하 패턴
```
0-2분:  0 → 1k RPS (Warm-up)
2-7분:  1k → 3.3k/3.4k RPS (Ramp-up)
7-17분: 3.3k/3.4k RPS 유지 (Peak load)
17-20분: 3.3k/3.4k → 0 RPS (Ramp-down)
```

## 🚀 실행 방법

### 1. ConfigMap 적용
```bash
kubectl apply -f manifests/k6/job/k6-configmap-10k-distributed.yaml
```

### 2. Job 실행 (병렬 3개)
```bash
kubectl apply -f manifests/k6/job/k6-job-parallel-10k.yaml
```

### 3. 상태 확인
```bash
# Job 상태
kubectl get jobs -n load-test -l test=10k-distributed

# Pod 상태
kubectl get pods -n load-test -l test=10k-distributed -o wide

# 실시간 로그 (Part 1)
kubectl logs -n load-test -l part=1 -f

# 모든 Part 로그 동시에 보기
kubectl logs -n load-test -l test=10k-distributed --all-containers=true -f
```

### 4. 리소스 사용량 모니터링
```bash
# CPU/Memory 사용량
kubectl top pods -n load-test -l test=10k-distributed

# 노드별 리소스
kubectl get nodes -l workload-type=loadtest -o wide
```

## 📈 결과 확인

### Prometheus/Grafana
- Workspace: `ws-ec1155d6-1ea8-4822-b9e9-fdec9424dcb9`
- Metrics tags: `part=1`, `part=2`, `part=3`으로 구분 가능

### 주요 메트릭
```promql
# 전체 RPS
sum(rate(http_reqs_total[1m]))

# Part별 RPS
sum(rate(http_reqs_total{part="1"}[1m]))
sum(rate(http_reqs_total{part="2"}[1m]))
sum(rate(http_reqs_total{part="3"}[1m]))

# P95 Latency
histogram_quantile(0.95, sum(rate(http_req_duration_bucket[1m])) by (le))

# 실패율
rate(http_req_failed_total[1m]) / rate(http_reqs_total[1m])
```

## 🧹 정리

### Job 삭제
```bash
kubectl delete job -n load-test -l test=10k-distributed
```

### ConfigMap 삭제
```bash
kubectl delete configmap -n load-test k6-script-10k-part1 k6-script-10k-part2 k6-script-10k-part3
```

### 전체 삭제
```bash
kubectl delete -f manifests/k6/job/k6-job-parallel-10k.yaml
kubectl delete -f manifests/k6/job/k6-configmap-10k-distributed.yaml
```

## ⚙️ 리소스 요구사항

### 각 Job Pod
- **CPU**: 1.5 cores (request), 2 cores (limit)
- **Memory**: 3Gi (request), 4Gi (limit)
- **maxVUs**: 1500 VUs per job

### 전체 (3 Jobs)
- **총 CPU**: 4.5 cores (request), 6 cores (limit)
- **총 Memory**: 9Gi (request), 12Gi (limit)
- **총 VUs**: 최대 4500 VUs

### 필요 노드
- **최소**: t3a.large (2 core, 8GB) 노드 3개
- **권장**: loadtest nodepool에 3개 이상의 노드

## 🔧 Troubleshooting

### Job이 Pending 상태
```bash
# 이벤트 확인
kubectl describe job k6-loadtest-10k-part1 -n load-test

# 노드 리소스 확인
kubectl get nodes -l workload-type=loadtest
kubectl top nodes -l workload-type=loadtest
```

### Pod가 OOMKilled
```bash
# 메모리 제한 증가 (Job YAML 수정)
resources:
  limits:
    memory: "6Gi"  # 4Gi → 6Gi
```

### RPS가 목표에 못 미침
```bash
# CPU 제한 증가 또는 Part 4 추가
# maxVUs 증가
```

## 🎯 다음 단계: K6 Operator Distributed Mode

현재 방식의 한계:
- 수동 Job 관리
- 부하 분산 수동 계산
- 결과 수집 복잡

**K6 Operator 사용 시**:
```yaml
apiVersion: k6.io/v1alpha1
kind: TestRun
metadata:
  name: k6-test-10k
spec:
  parallelism: 3       # 자동 분산
  script:
    configMap:
      name: k6-script
  runner:
    resources:
      limits:
        cpu: 2
        memory: 4Gi
```

자동으로 3개의 runner가 부하를 균등 분산! 🚀
