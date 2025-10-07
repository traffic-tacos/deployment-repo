# K6 테스트 후 Redis 데이터 정리 가이드

## 개요

K6 부하 테스트 종료 후 Redis에 남아있는 테스트 데이터를 자동으로 정리하는 방법들을 제시합니다.

## 방법 1: K6 teardown() 함수 (권장)

K6 스크립트 내에서 `teardown()` 함수를 사용하여 테스트 종료 시 자동으로 Redis를 정리합니다.

### 장점
- ✅ 테스트 스크립트와 정리 로직이 함께 관리됨
- ✅ 모든 K6 worker가 완료된 후 한 번만 실행
- ✅ 추가 인프라 불필요

### 구현 예시

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';

// ... 기존 테스트 코드 ...

// 테스트 종료 후 실행되는 정리 함수
export function teardown(data) {
    console.log('🧹 Starting Redis cleanup after test completion...');
    
    const redisCleanupUrl = 'http://gateway-api.tacos-app.svc.cluster.local:8000/internal/redis/cleanup';
    
    // Gateway API의 cleanup 엔드포인트 호출
    const response = http.post(redisCleanupUrl, JSON.stringify({
        patterns: [
            'stream:*',           // 대기열 스트림
            'dedupe:*',           // 중복 방지 키
            'waiting_token:*',    // 대기 토큰
            'reservation_token:*',// 예약 토큰
            'idempotency:*',      // 멱등성 키
            'ratelimit:*',        // 레이트 리밋 키
            'queue:*',            // 큐 데이터
        ],
        dryRun: false
    }), {
        headers: {
            'Content-Type': 'application/json',
            'X-Admin-Token': __ENV.ADMIN_TOKEN || 'test-admin-token'
        },
        timeout: '60s'
    });

    if (check(response, {
        'Cleanup successful': (r) => r.status === 200
    })) {
        console.log('✅ Redis cleanup completed successfully');
        console.log(`   Deleted keys: ${response.json('deleted_count')}`);
    } else {
        console.error('❌ Redis cleanup failed:', response.status);
    }
}
```

## 방법 2: Kubernetes Job with Cleanup Sidecar

K6 Job에 cleanup 컨테이너를 추가하여 테스트 완료 후 실행합니다.

### Job 예시

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-loadtest-30k-with-cleanup
  namespace: load-test
spec:
  template:
    spec:
      containers:
      # K6 테스트 컨테이너
      - name: k6
        image: grafana/k6:latest
        command: ["k6", "run", "/scripts/script.js"]
        volumeMounts:
        - name: k6-script
          mountPath: /scripts
      
      # Redis cleanup 컨테이너 (테스트 후 실행)
      - name: redis-cleanup
        image: redis:7-alpine
        command:
        - /bin/sh
        - -c
        - |
          echo "⏳ Waiting for K6 test to complete..."
          # K6 프로세스가 완료될 때까지 대기
          while pgrep -f k6 > /dev/null; do
            sleep 5
          done
          
          echo "🧹 Starting Redis cleanup..."
          
          # Redis 연결 정보
          REDIS_HOST="clustercfg.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com"
          REDIS_PORT="6379"
          REDIS_PASSWORD="${REDIS_PASSWORD}"
          
          # Redis CLI로 패턴별 삭제
          redis-cli \
            --tls \
            --insecure \
            -h ${REDIS_HOST} \
            -p ${REDIS_PORT} \
            -a ${REDIS_PASSWORD} \
            --scan --pattern "stream:*" | xargs -L 1000 redis-cli \
              --tls --insecure \
              -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} DEL
          
          redis-cli \
            --tls --insecure \
            -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} \
            --scan --pattern "dedupe:*" | xargs -L 1000 redis-cli \
              --tls --insecure \
              -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} DEL
          
          redis-cli \
            --tls --insecure \
            -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} \
            --scan --pattern "waiting_token:*" | xargs -L 1000 redis-cli \
              --tls --insecure \
              -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} DEL
          
          echo "✅ Redis cleanup completed"
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-password
              key: password
      
      restartPolicy: Never
      volumes:
      - name: k6-script
        configMap:
          name: k6-script-30k
```

## 방법 3: 별도의 Cleanup Job

테스트 완료 후 수동으로 실행하는 별도의 cleanup Job을 생성합니다.

### Cleanup Job 생성

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: redis-cleanup-job
  namespace: load-test
spec:
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app: redis-cleanup
    spec:
      serviceAccountName: k6-sa
      containers:
      - name: redis-cleanup
        image: redis:7-alpine
        command:
        - /bin/sh
        - -c
        - |
          echo "🧹 Starting Redis cleanup for K6 test data..."
          
          REDIS_HOST="clustercfg.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com"
          REDIS_PORT="6379"
          
          # 패턴별로 키 삭제
          PATTERNS=(
            "stream:*"
            "dedupe:*"
            "waiting_token:*"
            "reservation_token:*"
            "idempotency:*"
            "ratelimit:*"
            "queue:*"
          )
          
          TOTAL_DELETED=0
          
          for pattern in "${PATTERNS[@]}"; do
            echo "🔍 Cleaning pattern: $pattern"
            
            COUNT=$(redis-cli \
              --tls --insecure \
              -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} \
              --scan --pattern "$pattern" | wc -l)
            
            if [ "$COUNT" -gt 0 ]; then
              redis-cli \
                --tls --insecure \
                -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} \
                --scan --pattern "$pattern" | \
                xargs -r -L 1000 redis-cli \
                  --tls --insecure \
                  -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} DEL
              
              echo "   ✅ Deleted $COUNT keys for pattern: $pattern"
              TOTAL_DELETED=$((TOTAL_DELETED + COUNT))
            else
              echo "   ℹ️  No keys found for pattern: $pattern"
            fi
          done
          
          echo ""
          echo "✅ Redis cleanup completed!"
          echo "   Total keys deleted: $TOTAL_DELETED"
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-password
              key: password
      restartPolicy: Never
  backoffLimit: 3
```

### Cleanup Job 실행

```bash
# Cleanup Job 적용
kubectl apply -f redis-cleanup-job.yaml

# 실행 상태 확인
kubectl get job redis-cleanup-job -n load-test -w

# 로그 확인
kubectl logs -n load-test -l app=redis-cleanup --tail=50
```

## 방법 4: Gateway API Cleanup 엔드포인트 추가 (최고 권장)

Gateway API에 관리자 전용 cleanup 엔드포인트를 추가하여 테스트 후 호출합니다.

### Gateway API 코드 예시 (Go)

```go
// internal/admin/redis_cleanup.go
package admin

import (
    "context"
    "fmt"
    "github.com/gofiber/fiber/v2"
    "github.com/redis/go-redis/v9"
)

type CleanupRequest struct {
    Patterns []string `json:"patterns"`
    DryRun   bool     `json:"dry_run"`
}

type CleanupResponse struct {
    DeletedCount int      `json:"deleted_count"`
    Patterns     []string `json:"patterns"`
    DryRun       bool     `json:"dry_run"`
}

func RedisCleanupHandler(rdb *redis.ClusterClient) fiber.Handler {
    return func(c *fiber.Ctx) error {
        // 관리자 토큰 검증
        token := c.Get("X-Admin-Token")
        if token != getAdminToken() {
            return c.Status(403).JSON(fiber.Map{
                "error": "Unauthorized"
            })
        }
        
        var req CleanupRequest
        if err := c.BodyParser(&req); err != nil {
            return c.Status(400).JSON(fiber.Map{"error": err.Error()})
        }
        
        if len(req.Patterns) == 0 {
            req.Patterns = []string{
                "stream:*",
                "dedupe:*",
                "waiting_token:*",
                "reservation_token:*",
                "idempotency:*",
                "ratelimit:*",
            }
        }
        
        ctx := context.Background()
        totalDeleted := 0
        
        for _, pattern := range req.Patterns {
            var cursor uint64
            for {
                keys, nextCursor, err := rdb.Scan(ctx, cursor, pattern, 1000).Result()
                if err != nil {
                    return c.Status(500).JSON(fiber.Map{"error": err.Error()})
                }
                
                if len(keys) > 0 {
                    if !req.DryRun {
                        deleted, err := rdb.Del(ctx, keys...).Result()
                        if err != nil {
                            return c.Status(500).JSON(fiber.Map{"error": err.Error()})
                        }
                        totalDeleted += int(deleted)
                    } else {
                        totalDeleted += len(keys)
                    }
                }
                
                cursor = nextCursor
                if cursor == 0 {
                    break
                }
            }
        }
        
        return c.JSON(CleanupResponse{
            DeletedCount: totalDeleted,
            Patterns:     req.Patterns,
            DryRun:       req.DryRun,
        })
    }
}
```

### Gateway API 라우트 등록

```go
// cmd/main.go
adminGroup := app.Group("/internal/admin")
adminGroup.Post("/redis/cleanup", admin.RedisCleanupHandler(redisClient))
```

### 호출 방법

```bash
# K6 테스트 후 수동 실행
kubectl run redis-cleanup-curl --rm -it --restart=Never \
  --image=curlimages/curl:latest \
  -n load-test \
  -- curl -X POST \
    -H "Content-Type: application/json" \
    -H "X-Admin-Token: your-admin-token" \
    -d '{"patterns":["stream:*","dedupe:*","waiting_token:*"],"dry_run":false}' \
    http://gateway-api.tacos-app.svc.cluster.local:8000/internal/admin/redis/cleanup
```

## 비교 및 권장사항

| 방법 | 자동화 | 복잡도 | 유지보수 | 권장도 |
|------|--------|--------|----------|--------|
| K6 teardown() | ✅ 자동 | 🟢 낮음 | 🟢 쉬움 | ⭐⭐⭐⭐ |
| Job Sidecar | ✅ 자동 | 🟡 중간 | 🟡 보통 | ⭐⭐⭐ |
| 별도 Cleanup Job | ❌ 수동 | 🟡 중간 | 🟢 쉬움 | ⭐⭐ |
| Gateway API 엔드포인트 | ✅ 호출 필요 | 🟢 낮음 | 🟢 쉬움 | ⭐⭐⭐⭐⭐ |

### 추천 조합

**개발/테스트 환경:**
- K6 teardown() + Gateway API 엔드포인트

**프로덕션/스테이징:**
- Gateway API 엔드포인트 + 수동 트리거

**CI/CD 파이프라인:**
- K6 teardown() (자동화)

## 주의사항

⚠️ **프로덕션 데이터 보호:**
- Cleanup은 **반드시 테스트 네임스페이스**에서만 실행
- 패턴 매칭을 정확하게 설정하여 실제 사용자 데이터 삭제 방지
- DryRun 옵션으로 먼저 테스트

⚠️ **Cluster Mode Redis:**
- `SCAN` 명령은 각 샤드를 순회하므로 시간이 걸릴 수 있음
- 대량 삭제 시 `DEL`을 batch로 처리 (1000개씩)

⚠️ **타임아웃:**
- Cleanup에 충분한 타임아웃 설정 (60s 이상 권장)

## 구현 순서

1. **Phase 1**: Gateway API에 cleanup 엔드포인트 추가
2. **Phase 2**: K6 스크립트에 teardown() 함수 추가
3. **Phase 3**: 별도 Cleanup Job 생성 (백업용)
4. **Phase 4**: 모니터링 및 로깅 추가

---

**작성일**: 2025-10-07  
**업데이트**: ElastiCache Cluster Mode 적용 후
