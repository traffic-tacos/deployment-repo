#!/bin/bash
#
# K6 테스트 후 Redis 데이터 정리 스크립트
# Usage: ./cleanup-redis-after-test.sh [--dry-run]
#

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Redis 연결 정보
REDIS_HOST="clustercfg.traffic-tacos-redis.w6eqga.apn2.cache.amazonaws.com"
REDIS_PORT="6379"
NAMESPACE="tacos-app"

# DryRun 모드
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🧹 K6 Test Redis Cleanup Script${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Redis 비밀번호 가져오기
echo -e "${YELLOW}🔑 Fetching Redis password from Kubernetes Secret...${NC}"
REDIS_PASSWORD=$(kubectl get secret redis-password -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$REDIS_PASSWORD" ]; then
    echo -e "${RED}❌ Failed to retrieve Redis password${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Redis password retrieved${NC}"
echo ""

# 정리할 패턴 목록
PATTERNS=(
    "stream:event:*"
    "dedupe:*"
    "waiting_token:*"
    "reservation_token:*"
    "idempotency:*"
    "ratelimit:*"
    "queue:*"
)

TOTAL_KEYS=0

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}📊 DRY RUN MODE - No keys will be deleted${NC}"
    echo ""
fi

echo -e "${BLUE}🔍 Scanning Redis for test data patterns...${NC}"
echo ""

# 임시 Pod 생성하여 Redis 정리
CLEANUP_POD="redis-cleanup-$(date +%s)"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${CLEANUP_POD}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
  - name: redis-cli
    image: redis:7-alpine
    command:
    - /bin/sh
    - -c
    - |
      set -e
      
      REDIS_HOST="${REDIS_HOST}"
      REDIS_PORT="${REDIS_PORT}"
      REDIS_PASSWORD="${REDIS_PASSWORD}"
      DRY_RUN="${DRY_RUN}"
      
      PATTERNS=(
        "stream:event:*"
        "dedupe:*"
        "waiting_token:*"
        "reservation_token:*"
        "idempotency:*"
        "ratelimit:*"
        "queue:*"
      )
      
      TOTAL_DELETED=0
      
      echo "🧹 Starting Redis cleanup..."
      echo ""
      
      for pattern in "\${PATTERNS[@]}"; do
        echo "🔍 Scanning pattern: \$pattern"
        
        # SCAN 명령으로 키 개수 확인
        KEYS=\$(redis-cli \
          --tls --insecure \
          -h \${REDIS_HOST} -p \${REDIS_PORT} -a \${REDIS_PASSWORD} \
          --scan --pattern "\$pattern" 2>/dev/null)
        
        COUNT=\$(echo "\$KEYS" | wc -l)
        
        if [ "\$COUNT" -gt 0 ] && [ -n "\$KEYS" ]; then
          echo "   Found \$COUNT keys"
          
          if [ "\$DRY_RUN" = "false" ]; then
            # 실제 삭제 수행 (batch로 1000개씩)
            echo "\$KEYS" | xargs -r -n 1000 redis-cli \
              --tls --insecure \
              -h \${REDIS_HOST} -p \${REDIS_PORT} -a \${REDIS_PASSWORD} \
              DEL > /dev/null 2>&1
            
            echo "   ✅ Deleted \$COUNT keys"
            TOTAL_DELETED=\$((TOTAL_DELETED + COUNT))
          else
            echo "   ℹ️  Would delete \$COUNT keys (DRY RUN)"
            TOTAL_DELETED=\$((TOTAL_DELETED + COUNT))
          fi
        else
          echo "   ℹ️  No keys found"
        fi
        echo ""
      done
      
      echo "════════════════════════════════════════════════════════════"
      if [ "\$DRY_RUN" = "false" ]; then
        echo "✅ Redis cleanup completed!"
        echo "   Total keys deleted: \$TOTAL_DELETED"
      else
        echo "📊 DRY RUN completed"
        echo "   Total keys that would be deleted: \$TOTAL_DELETED"
      fi
      echo "════════════════════════════════════════════════════════════"
      
      sleep 2
EOF

echo -e "${YELLOW}⏳ Waiting for cleanup pod to be ready...${NC}"
kubectl wait --for=condition=Ready pod/${CLEANUP_POD} -n ${NAMESPACE} --timeout=60s > /dev/null 2>&1 || true

echo ""
echo -e "${BLUE}📋 Cleanup logs:${NC}"
echo ""

# 로그 스트리밍
kubectl logs -f ${CLEANUP_POD} -n ${NAMESPACE}

# Pod 정리
echo ""
echo -e "${YELLOW}🧹 Cleaning up temporary pod...${NC}"
kubectl delete pod ${CLEANUP_POD} -n ${NAMESPACE} --wait=false > /dev/null 2>&1

echo ""
echo -e "${GREEN}✅ Cleanup process completed${NC}"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${YELLOW}💡 To actually delete the keys, run:${NC}"
    echo -e "${YELLOW}   $0${NC}"
fi
