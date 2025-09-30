# 3만 RPS 성능 최적화 가이드

## 🎯 목표
- **처리량**: 30,000 RPS
- **지연시간**: P99 < 100ms
- **가용성**: 99.9% uptime

## 📊 최적화 전략

### 1. HPA/PDB 설정

#### Gateway API (Entry Point)
```yaml
minReplicas: 10  # 항상 10개 유지
maxReplicas: 50  # 피크 시 50개까지
minAvailable: 5  # 최소 5개 항상 가용
```

**계산 근거**:
- 목표 RPS: 30,000
- Pod당 처리량: ~1,000 RPS (프록시 역할)
- 필요 Pod: 30,000 / 1,000 = 30
- 여유분 50%: 30 * 1.5 = 45
- Max 50으로 설정

#### Backend APIs (reservation, inventory, payment)
```yaml
minReplicas: 5   # 항상 5개 유지
maxReplicas: 30  # 피크 시 30개까지
minAvailable: 3  # 최소 3개 항상 가용
```

**계산 근거**:
- 목표 RPS: 10,000 (분산 가정)
- Pod당 처리량: ~500 RPS (비즈니스 로직 + DB)
- 필요 Pod: 10,000 / 500 = 20
- 여유분 50%: 20 * 1.5 = 30

### 2. Redis 아키텍처

#### Master-Replica 구성
- **Master**: 1개 (Write)
- **Replica**: 3개 (Read)
- **목적**: Read 부하 분산

#### 설정 최적화
```yaml
maxmemory: 512mb
maxmemory-policy: allkeys-lru  # LRU eviction
save: ""  # Persistence 비활성화 (성능 우선)
appendonly: no  # AOF 비활성화
```

### 3. 애플리케이션 레벨 최적화

#### A. Connection Pooling
**Gateway API 환경변수 추가**:
```yaml
- name: REDIS_POOL_SIZE
  value: "50"  # Connection pool size
- name: REDIS_POOL_TIMEOUT
  value: "3s"
- name: HTTP_MAX_IDLE_CONNS
  value: "100"
- name: HTTP_MAX_IDLE_CONNS_PER_HOST
  value: "50"
- name: HTTP_TIMEOUT
  value: "5s"
```

#### B. Circuit Breaker
```yaml
- name: CIRCUIT_BREAKER_THRESHOLD
  value: "5"  # 5번 실패 후 차단
- name: CIRCUIT_BREAKER_TIMEOUT
  value: "10s"
```

#### C. Rate Limiting (Per Pod)
```yaml
- name: RATE_LIMIT_RPS
  value: "1500"  # Pod당 1500 RPS 제한
- name: RATE_LIMIT_BURST
  value: "2000"
```

### 4. Kubernetes 리소스 최적화

#### Gateway API Resources
```yaml
resources:
  requests:
    cpu: 500m      # 0.5 core
    memory: 512Mi
  limits:
    cpu: 2000m     # 2 cores max
    memory: 1Gi
```

**계산**: 50 Pods * 0.5 CPU = 25 cores 필요

#### Backend API Resources
```yaml
resources:
  requests:
    cpu: 250m      # 0.25 core
    memory: 256Mi
  limits:
    cpu: 1000m     # 1 core max
    memory: 512Mi
```

**계산**: 30 Pods * 3 APIs * 0.25 CPU = 22.5 cores 필요

### 5. Probe 튜닝

#### Readiness Probe (트래픽 수신 준비)
```yaml
readinessProbe:
  httpGet:
    path: /readyz
    port: 8000
  initialDelaySeconds: 5   # 빠른 시작
  periodSeconds: 3         # 자주 체크
  timeoutSeconds: 2
  successThreshold: 1
  failureThreshold: 2      # 2번 실패시 제외
```

#### Liveness Probe (재시작 판단)
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8000
  initialDelaySeconds: 30  # 충분한 시작 시간
  periodSeconds: 10        # 덜 자주 체크
  timeoutSeconds: 5
  failureThreshold: 3      # 3번 실패시 재시작
```

### 6. Network 최적화

#### Service 설정
```yaml
spec:
  type: NodePort
  sessionAffinity: ClientIP  # 세션 고정
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 300
```

#### Pod Anti-Affinity (분산 배치)
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - gateway-api
        topologyKey: kubernetes.io/hostname
```

### 7. 모니터링 지표

#### 추적해야 할 메트릭
1. **RPS**: 요청 처리율
2. **Latency**: P50, P95, P99
3. **Error Rate**: 5xx 에러율
4. **CPU/Memory**: 리소스 사용률
5. **Pod Count**: 현재 실행 중인 Pod 수
6. **Redis**: Hit rate, command latency

#### Alert 기준
```yaml
- RPS > 28,000: Warning (여유 7%)
- RPS > 29,000: Critical (여유 3%)
- P99 Latency > 100ms: Warning
- Error Rate > 1%: Critical
- CPU > 80%: Warning
```

### 8. Karpenter NodePool 조정

#### Node Provisioning
```yaml
# on-demand-critical NodePool
spec:
  limits:
    cpu: "200"      # 최대 200 cores
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 5m  # 5분 후 consolidation
```

### 9. 예상 비용

#### Compute Resources
- **Nodes**: ~15-20 m5.2xlarge (8 vCPU, 32GB)
- **비용**: $0.384/hour * 20 = $7.68/hour = ~$5,600/month

#### Redis
- **ElastiCache 대안**: r6g.xlarge (4 vCPU, 32GB) = ~$250/month
- **현재 K8s**: 무료 (이미 있는 노드 사용)

### 10. 부하 테스트 계획

#### Phase 1: Warm-up
```bash
k6 run --vus 100 --duration 2m script.js
```

#### Phase 2: Ramp-up
```bash
k6 run --vus 500 --duration 5m --rps 10000 script.js
```

#### Phase 3: Peak Load
```bash
k6 run --vus 1000 --duration 10m --rps 30000 script.js
```

#### Phase 4: Stress Test
```bash
k6 run --vus 1500 --duration 5m --rps 40000 script.js
```

### 11. 장애 대응

#### Auto-recovery
- **HPA**: 자동 스케일링
- **Liveness Probe**: 자동 재시작
- **PDB**: Rolling update 시 가용성 보장

#### Manual Intervention
```bash
# 긴급 스케일 업
kubectl scale deployment gateway-api -n tacos-app --replicas=40

# Pod 강제 재시작
kubectl rollout restart deployment gateway-api -n tacos-app
```

## 📝 체크리스트

### Before Load Test
- [ ] HPA minReplicas를 최소 요구사항으로 설정
- [ ] Redis replica 배포
- [ ] Monitoring dashboard 구성
- [ ] Alert 설정
- [ ] Node provisioning 여유 확인

### During Load Test
- [ ] 실시간 모니터링
- [ ] CPU/Memory 사용률 추적
- [ ] Error rate 확인
- [ ] Latency 추적

### After Load Test
- [ ] 결과 분석
- [ ] Bottleneck 식별
- [ ] 최적화 적용
- [ ] 재테스트

## 🎓 Best Practices

1. **점진적 증가**: 갑자기 3만 RPS를 주지 말고 점진적으로
2. **Warm-up**: 애플리케이션이 준비될 시간 제공
3. **Connection Pre-warming**: 미리 connection pool 채우기
4. **Cache Pre-loading**: 자주 사용하는 데이터 사전 로드
5. **Graceful Degradation**: 부하가 과도하면 일부 기능 제한
