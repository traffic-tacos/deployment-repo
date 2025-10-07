#!/bin/bash
# K6 30k RPS 테스트 정리 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  K6 30k RPS 테스트 정리${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 현재 상태 확인
echo -e "${YELLOW}📊 현재 상태:${NC}"
echo ""

echo "실행 중인 Job:"
kubectl get jobs -n load-test -l test=30k-distributed 2>/dev/null || echo "  없음"
echo ""

echo "실행 중인 Pod:"
kubectl get pods -n load-test -l test=30k-distributed 2>/dev/null || echo "  없음"
echo ""

echo "생성된 ConfigMap:"
kubectl get cm -n load-test -l test=30k-distributed 2>/dev/null || echo "  없음"
echo ""

read -p "모든 30k 테스트 리소스를 삭제하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${RED}취소되었습니다.${NC}"
    exit 0
fi
echo ""

# Job 삭제
echo -e "${GREEN}🗑️  Job 삭제 중...${NC}"
kubectl delete job -n load-test -l test=30k-distributed --ignore-not-found=true
echo ""

# ConfigMap 삭제
echo -e "${GREEN}🗑️  ConfigMap 삭제 중...${NC}"
kubectl delete cm -n load-test -l test=30k-distributed --ignore-not-found=true
echo ""

# 완료 확인
echo -e "${GREEN}✅ 정리 완료!${NC}"
echo ""

# 최종 상태 확인
echo -e "${YELLOW}📊 최종 상태:${NC}"
echo ""

REMAINING_JOBS=$(kubectl get jobs -n load-test -l test=30k-distributed --no-headers 2>/dev/null | wc -l)
REMAINING_PODS=$(kubectl get pods -n load-test -l test=30k-distributed --no-headers 2>/dev/null | wc -l)
REMAINING_CMS=$(kubectl get cm -n load-test -l test=30k-distributed --no-headers 2>/dev/null | wc -l)

if [ "$REMAINING_JOBS" -eq 0 ] && [ "$REMAINING_PODS" -eq 0 ] && [ "$REMAINING_CMS" -eq 0 ]; then
    echo -e "${GREEN}✅ 모든 리소스가 정리되었습니다.${NC}"
else
    echo -e "${YELLOW}⚠️  일부 리소스가 남아있습니다:${NC}"
    echo "  Jobs: $REMAINING_JOBS"
    echo "  Pods: $REMAINING_PODS"
    echo "  ConfigMaps: $REMAINING_CMS"
    echo ""
    echo "Pod가 Terminating 상태일 수 있습니다. 잠시 후 다시 확인하세요."
fi
echo ""
