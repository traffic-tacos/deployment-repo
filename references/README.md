# References - K6 Load Test Templates

이 디렉토리는 **참고용 K6 로드 테스트 템플릿**을 보관합니다.

⚠️ **주의:** 이 디렉토리의 파일들은 **ArgoCD 자동 배포 대상이 아닙니다**.  
실제 테스트 실행은 담당자가 필요할 때 **수동으로** 적용해야 합니다.

## 📂 디렉토리 구조

```
references/
├── k6-load-tests/
│   ├── 10k/                    # 10k RPS 분산 테스트
│   │   ├── k6-configmap-10k-distributed.yaml
│   │   └── k6-job-parallel-10k.yaml
│   └── 30k/                    # 30k RPS 분산 테스트
│       ├── k6-configmap-30k-distributed.yaml
│       └── k6-job-parallel-30k.yaml
└── docs/                       # 상세 문서
    ├── README-DISTRIBUTED-10K.md
    ├── README-DISTRIBUTED-30K.md
    ├── LOAD-TEST-COMPARISON.md
    ├── run-30k-test.sh
    └── cleanup-30k-test.sh
```

## 🚀 사용 방법

### 1. 10k RPS 테스트 실행

```bash
# 1. ConfigMap 적용
kubectl apply -f references/k6-load-tests/10k/k6-configmap-10k-distributed.yaml

# 2. Job 실행
kubectl apply -f references/k6-load-tests/10k/k6-job-parallel-10k.yaml

# 3. 상태 확인
kubectl get pods -n load-test -l test=10k-distributed -o wide

# 4. 정리
kubectl delete job -n load-test -l test=10k-distributed
kubectl delete cm -n load-test -l test=10k-distributed
```

### 2. 30k RPS 테스트 실행

```bash
# 빠른 실행 (스크립트 사용)
cd references/docs
./run-30k-test.sh

# 또는 수동 실행
kubectl apply -f references/k6-load-tests/30k/k6-configmap-30k-distributed.yaml
kubectl apply -f references/k6-load-tests/30k/k6-job-parallel-30k.yaml

# 정리
./cleanup-30k-test.sh
```

## 📋 테스트 전 필수 확인사항

### ElastiCache 업그레이드 (필수!)

현재 `cache.t3.micro`는 10k RPS도 버거운 상태입니다.  
30k RPS 테스트 전에 **반드시** `cache.r7g.large`로 업그레이드하세요!

```bash
# 1. IaC 저장소로 이동
cd ../traffic-tacos-infra-iac

# 2. Terraform 변경사항 확인
terraform plan

# 3. 업그레이드 실행 (15-30분 소요)
terraform apply

# 4. 확인
cd ../deployment-repo
./check-redis-status.sh
```

상세 가이드: [`../traffic-tacos-infra-iac/ELASTICACHE-UPGRADE-GUIDE.md`](../../traffic-tacos-infra-iac/ELASTICACHE-UPGRADE-GUIDE.md)

### 리소스 확인

```bash
# 노드 상태
kubectl get nodes -l workload-type=loadtest

# 리소스 여유
kubectl top nodes -l workload-type=loadtest
```

## 📊 테스트 비교

| 테스트 | 파드 수 | 파드당 RPS | 총 RPS | 필요 CPU | 필요 Memory |
|--------|---------|-----------|--------|----------|------------|
| 10k | 3개 | 3.3k | 10,000 | 4.5-6 cores | 9-12Gi |
| 30k | 6개 | 5k | 30,000 | 12-18 cores | 24-36Gi |

## 🔗 관련 문서

- **10k 가이드**: [`docs/README-DISTRIBUTED-10K.md`](docs/README-DISTRIBUTED-10K.md)
- **30k 가이드**: [`docs/README-DISTRIBUTED-30K.md`](docs/README-DISTRIBUTED-30K.md)
- **비교표**: [`docs/LOAD-TEST-COMPARISON.md`](docs/LOAD-TEST-COMPARISON.md)
- **ElastiCache 분석**: [`../docs/ELASTICACHE-CAPACITY-PLANNING.md`](../docs/ELASTICACHE-CAPACITY-PLANNING.md)
- **Redis 모니터링**: [`../check-redis-status.sh`](../check-redis-status.sh)

## ⚠️ 주의사항

1. **ArgoCD 자동 배포 방지**
   - 이 디렉토리는 ArgoCD가 감시하지 않습니다
   - `manifests/k6/job/`으로 복사하면 **자동 실행됨!**

2. **프로덕션 환경**
   - 테스트 시간대 조정 필요 (트래픽 낮은 시간)
   - 사전 공지 권장

3. **ElastiCache 업그레이드**
   - 10k 테스트도 현재 `t3.micro`로는 불안정
   - 30k 테스트는 `r7g.large` 필수

4. **모니터링**
   - Grafana 대시보드 확인
   - CloudWatch 메트릭 모니터링
   - 실시간 Pod 상태 확인

## 📞 문의

테스트 실행 관련 문의는 DevOps 팀 담당자에게 문의하세요.

---

**마지막 업데이트**: 2025-10-07  
**작성자**: DevOps Team
