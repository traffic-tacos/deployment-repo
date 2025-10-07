#!/bin/bash
# ElastiCache Redis 실시간 상태 확인 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REGION="ap-northeast-2"
PROFILE="tacos"
REPLICATION_GROUP_ID="traffic-tacos-redis"
CACHE_CLUSTER_ID="traffic-tacos-redis-001"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  ElastiCache Redis 상태 모니터링${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 클러스터 기본 정보
echo -e "${GREEN}📊 1. 클러스터 정보${NC}"
echo ""

CLUSTER_INFO=$(aws elasticache describe-replication-groups \
  --replication-group-id $REPLICATION_GROUP_ID \
  --region $REGION \
  --profile $PROFILE \
  --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    NODE_TYPE=$(echo "$CLUSTER_INFO" | jq -r '.ReplicationGroups[0].CacheNodeType')
    STATUS=$(echo "$CLUSTER_INFO" | jq -r '.ReplicationGroups[0].Status')
    MULTI_AZ=$(echo "$CLUSTER_INFO" | jq -r '.ReplicationGroups[0].MultiAZ')
    
    echo "  노드 타입: $NODE_TYPE"
    echo "  상태: $STATUS"
    echo "  Multi-AZ: $MULTI_AZ"
    
    # t3.micro 경고
    if [[ "$NODE_TYPE" == "cache.t3.micro" ]]; then
        echo -e "${RED}  ⚠️  경고: t3.micro는 30k RPS에 부족합니다!${NC}"
    fi
else
    echo -e "${RED}  ❌ 클러스터 정보 조회 실패${NC}"
fi
echo ""

# 2. 실시간 메트릭
echo -e "${GREEN}📈 2. 실시간 메트릭 (최근 5분)${NC}"
echo ""

START_TIME=$(date -u -v-5M '+%Y-%m-%dT%H:%M:%S')
END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%S')

# CPU 사용률
echo -n "  CPU 사용률: "
CPU_DATA=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name CPUUtilization \
  --dimensions Name=CacheClusterId,Value=$CACHE_CLUSTER_ID \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 300 \
  --statistics Average \
  --region $REGION \
  --profile $PROFILE \
  --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    CPU_AVG=$(echo "$CPU_DATA" | jq -r '.Datapoints[0].Average // 0' | awk '{printf "%.1f", $1}')
    if (( $(echo "$CPU_AVG > 70" | bc -l) )); then
        echo -e "${RED}$CPU_AVG% (높음!)${NC}"
    elif (( $(echo "$CPU_AVG > 50" | bc -l) )); then
        echo -e "${YELLOW}$CPU_AVG% (주의)${NC}"
    else
        echo -e "${GREEN}$CPU_AVG%${NC}"
    fi
else
    echo -e "${YELLOW}조회 실패${NC}"
fi

# 메모리 사용률
echo -n "  메모리 사용률: "
MEM_DATA=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=CacheClusterId,Value=$CACHE_CLUSTER_ID \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 300 \
  --statistics Average \
  --region $REGION \
  --profile $PROFILE \
  --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    MEM_AVG=$(echo "$MEM_DATA" | jq -r '.Datapoints[0].Average // 0' | awk '{printf "%.1f", $1}')
    if (( $(echo "$MEM_AVG > 85" | bc -l) )); then
        echo -e "${RED}$MEM_AVG% (매우 높음!)${NC}"
    elif (( $(echo "$MEM_AVG > 70" | bc -l) )); then
        echo -e "${YELLOW}$MEM_AVG% (높음)${NC}"
    else
        echo -e "${GREEN}$MEM_AVG%${NC}"
    fi
else
    echo -e "${YELLOW}조회 실패${NC}"
fi

# 현재 연결 수
echo -n "  현재 연결 수: "
CONN_DATA=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name CurrConnections \
  --dimensions Name=CacheClusterId,Value=$CACHE_CLUSTER_ID \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 300 \
  --statistics Average \
  --region $REGION \
  --profile $PROFILE \
  --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    CONN_AVG=$(echo "$CONN_DATA" | jq -r '.Datapoints[0].Average // 0' | awk '{printf "%.0f", $1}')
    if (( CONN_AVG > 5000 )); then
        echo -e "${RED}$CONN_AVG개 (매우 높음!)${NC}"
    elif (( CONN_AVG > 1000 )); then
        echo -e "${YELLOW}$CONN_AVG개 (높음)${NC}"
    else
        echo -e "${GREEN}$CONN_AVG개${NC}"
    fi
else
    echo -e "${YELLOW}조회 실패${NC}"
fi

# 캐시 히트율
echo -n "  캐시 히트 (분당): "
HITS_DATA=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name CacheHits \
  --dimensions Name=CacheClusterId,Value=$CACHE_CLUSTER_ID \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 300 \
  --statistics Sum \
  --region $REGION \
  --profile $PROFILE \
  --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    HITS_SUM=$(echo "$HITS_DATA" | jq -r '.Datapoints[0].Sum // 0' | awk '{printf "%.0f", $1}')
    HITS_PER_SEC=$(echo "$HITS_SUM / 300" | bc)
    echo -e "${GREEN}$HITS_SUM (초당 ~${HITS_PER_SEC} ops)${NC}"
else
    echo -e "${YELLOW}조회 실패${NC}"
fi

echo ""

# 3. 권장 사항
echo -e "${GREEN}💡 3. 권장 사항${NC}"
echo ""

if [[ "$NODE_TYPE" == "cache.t3.micro" ]]; then
    echo -e "${YELLOW}  ⚠️  현재 cache.t3.micro는 30k RPS에 부족합니다!${NC}"
    echo ""
    echo "  권장 업그레이드:"
    echo "    • cache.r7g.large (13GB 메모리, ~$115/month)"
    echo "    • cache.m7g.large (6GB 메모리, ~$92/month)"
    echo ""
    echo "  업그레이드 명령어:"
    echo "    aws elasticache modify-replication-group \\"
    echo "      --replication-group-id $REPLICATION_GROUP_ID \\"
    echo "      --cache-node-type cache.r7g.large \\"
    echo "      --apply-immediately \\"
    echo "      --region $REGION \\"
    echo "      --profile $PROFILE"
    echo ""
fi

# CPU가 높으면
if [ -n "$CPU_AVG" ] && (( $(echo "$CPU_AVG > 50" | bc -l) )); then
    echo -e "${YELLOW}  ⚠️  CPU 사용률이 높습니다!${NC}"
    echo "    • gateway-api replica 축소 고려"
    echo "    • 더 큰 인스턴스 타입으로 업그레이드"
    echo ""
fi

# 메모리가 높으면
if [ -n "$MEM_AVG" ] && (( $(echo "$MEM_AVG > 70" | bc -l) )); then
    echo -e "${YELLOW}  ⚠️  메모리 사용률이 높습니다!${NC}"
    echo "    • eviction 발생 가능"
    echo "    • 더 큰 메모리의 인스턴스 타입으로 업그레이드"
    echo ""
fi

# 연결 수가 높으면
if [ -n "$CONN_AVG" ] && (( CONN_AVG > 1000 )); then
    echo -e "${YELLOW}  ⚠️  연결 수가 많습니다!${NC}"
    echo "    • gateway-api replica 축소: kubectl scale deployment gateway-api -n tacos-app --replicas=8"
    echo "    • Connection pool 튜닝 (MaxIdle, MaxActive 조정)"
    echo ""
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  상세 분석: docs/ELASTICACHE-CAPACITY-PLANNING.md${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
