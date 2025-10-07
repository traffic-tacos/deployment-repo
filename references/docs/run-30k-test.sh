#!/bin/bash
# K6 30k RPS 분산 테스트 실행 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  K6 30k RPS 분산 테스트 실행기${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 사전 확인
echo -e "${YELLOW}📊 1. 사전 확인 중...${NC}"
echo ""

# 노드 확인
echo "loadtest 노드 상태:"
kubectl get nodes -l workload-type=loadtest -o wide || {
    echo -e "${RED}❌ loadtest 노드를 찾을 수 없습니다!${NC}"
    exit 1
}
echo ""

# 리소스 확인
echo "노드 리소스 사용량:"
kubectl top nodes -l workload-type=loadtest || echo -e "${YELLOW}⚠️  Metrics Server가 없거나 데이터가 준비 안됨${NC}"
echo ""

# NodePool 확인
echo "Karpenter NodePool 상태:"
kubectl get nodepool loadtest -o jsonpath='{.status.resources}' 2>/dev/null || echo -e "${YELLOW}⚠️  NodePool 정보 없음${NC}"
echo ""

# 필요 리소스 안내
echo -e "${YELLOW}⚠️  30k RPS 테스트 필요 리소스:${NC}"
echo "  • CPU: 12-18 cores"
echo "  • Memory: 24-36Gi"
echo "  • 노드: 4-6개 (t3a.xlarge 이상)"
echo ""

read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${RED}취소되었습니다.${NC}"
    exit 0
fi
echo ""

# ConfigMap 적용
echo -e "${GREEN}📝 2. ConfigMap 적용 중...${NC}"
kubectl apply -f k6-configmap-30k-distributed.yaml
echo ""

# ConfigMap 확인
echo "생성된 ConfigMap:"
kubectl get cm -n load-test -l test=30k-distributed
echo ""

sleep 2

# Job 실행
echo -e "${GREEN}🚀 3. Job 실행 중 (6개 병렬)...${NC}"
kubectl apply -f k6-job-parallel-30k.yaml
echo ""

sleep 3

# 상태 확인
echo -e "${GREEN}📊 4. 초기 상태 확인...${NC}"
echo ""

echo "Job 상태:"
kubectl get jobs -n load-test -l test=30k-distributed
echo ""

echo "Pod 상태:"
kubectl get pods -n load-test -l test=30k-distributed -o wide
echo ""

# Pending 파드 확인
PENDING_COUNT=$(kubectl get pods -n load-test -l test=30k-distributed --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
if [ "$PENDING_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Pending 파드 ${PENDING_COUNT}개 발견!${NC}"
    echo "Karpenter가 노드를 생성 중일 수 있습니다. 2-5분 대기 후 확인하세요."
    echo ""
    echo "노드 생성 상태 확인:"
    kubectl get nodeclaims -l karpenter.sh/nodepool=loadtest
    echo ""
fi

# 모니터링 명령어 안내
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  모니터링 명령어${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${GREEN}실시간 파드 상태:${NC}"
echo "  watch -n 2 'kubectl get pods -n load-test -l test=30k-distributed -o wide'"
echo ""

echo -e "${GREEN}실시간 로그:${NC}"
echo "  kubectl logs -n load-test -l test=30k-distributed --all-containers=true -f"
echo ""

echo -e "${GREEN}리소스 사용량:${NC}"
echo "  watch -n 5 'kubectl top pods -n load-test -l test=30k-distributed'"
echo ""

echo -e "${GREEN}노드 리소스:${NC}"
echo "  watch -n 5 'kubectl top nodes -l workload-type=loadtest'"
echo ""

echo -e "${GREEN}Grafana 대시보드:${NC}"
echo "  Prometheus 쿼리: sum(rate(http_reqs_total{test=\"30k\"}[1m]))"
echo ""

# 정리 명령어 안내
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  테스트 종료 후 정리${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${GREEN}Job 삭제:${NC}"
echo "  kubectl delete job -n load-test -l test=30k-distributed"
echo ""

echo -e "${GREEN}ConfigMap 삭제:${NC}"
echo "  kubectl delete cm -n load-test -l test=30k-distributed"
echo ""

echo -e "${GREEN}전체 삭제 (한 번에):${NC}"
echo "  ./cleanup-30k-test.sh"
echo ""

echo -e "${GREEN}✅ 30k RPS 테스트가 시작되었습니다!${NC}"
echo -e "${YELLOW}⏱️  테스트는 약 26분간 실행됩니다.${NC}"
echo ""
