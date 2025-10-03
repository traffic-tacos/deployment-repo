import http from 'k6/http';
import { check, sleep } from 'k6';

// Runtime Parameter
const CONCURRENT_USERS = 30000
// 전체 목표 RPS (모든 worker 합)
const RPS_TOTAL = Number(__ENV.RPS_TOTAL || CONCURRENT_USERS);
// 동시에 돌리 worker pod 수 = k6 Operator parallelism (조정 필요)
const WORKERS = Number(__ENV.WORKERS || 10);
// 해당 worker가 책임질 RPS
const RPS_PER_WORKER = Math.ceil(RPS_TOTAL / WORKERS);

// target, endpoint
const TARGET_BASE = __ENV.TARGET_URL || 'https://quickpizza.grafana.com/';
const HEALTH_PATH = __ENV.HEALTH_PATH || '/health';
const MAIN_PATH = __ENV.MAIN_PATH || '/api/purchase';

// 사용자가 머무는 시간 (조정 필요)
const THINK = Number(__ENV.THINK || 0); // seconds

// 비율(읽기/쓰기 조합) (조정 필요)
const RATIO_HEALTH = Number(__ENV.RATIO_HEALTH || 0.05);  // 5%
const RATIO_MAIN   = 1 - RATIO_HEALTH;                    // 95%

// Ramp & Steady 구간 (조정 필요)
const WARMUP_MIN = Number(__ENV.WARMUP_MIN || 1);
const RAMP_MIN   = Number(__ENV.RAMP_MIN   || 2);
const STEADY_MIN = Number(__ENV.STEADY_MIN || 5);
const COOLDOWN_MIN = Number(__ENV.COOLDOWN_MIN || 1);

// 예상 P95 latency/error 임계치(조정 필요)
export const options = {
  // rush traffic: 초당 일정 도착률(Iterations Per Second)을 강제
  scenarios: {
    warmup: {
      executor: 'constant-arrival-rate',
      exec: 'scenario_warmup',
      rate: Math.max(1, Math.floor(RPS_PER_WORKER * 0.1)), // 총 목표의 10%
      timeUnit: '1s',
      duration: `${WARMUP_MIN}m`,
      preAllocatedVUs: 200,
      maxVUs: 2000,
      startTime: '0s',
      gracefulStop: '0s',
    },
    ramp: {
      executor: 'ramping-arrival-rate',
      exec: 'scenario_main',
      startRate: Math.max(1, Math.floor(RPS_PER_WORKER * 0.1)),
      timeUnit: '1s',
      stages: [
        { target: Math.floor(RPS_PER_WORKER * 0.5), duration: `${Math.max(1, Math.floor(RAMP_MIN/2))}m` },
        { target: Math.floor(RPS_PER_WORKER),       duration: `${Math.max(1, Math.ceil(RAMP_MIN/2))}m` },
      ],
      preAllocatedVUs: 1000,
      maxVUs: 5000,
      startTime: `${WARMUP_MIN}m`,
      gracefulStop: '0s',
    },
    steady: {
      executor: 'constant-arrival-rate',
      exec: 'scenario_main',
      rate: RPS_PER_WORKER,
      timeUnit: '1s',
      duration: `${STEADY_MIN}m`,
      preAllocatedVUs: 2000,   // 필요 VU ≈ RPS * 평균 RTT(초). RTT 200ms면 RPS 3k에 VU ~600
      maxVUs: 10000,
      startTime: `${WARMUP_MIN + RAMP_MIN}m`,
      gracefulStop: '30s',
    },
    cooldown: {
      executor: 'constant-arrival-rate',
      exec: 'scenario_cooldown',
      rate: Math.max(1, Math.floor(RPS_PER_WORKER * 0.2)),
      timeUnit: '1s',
      duration: `${COOLDOWN_MIN}m`,
      preAllocatedVUs: 500,
      maxVUs: 2000,
      startTime: `${WARMUP_MIN + RAMP_MIN + STEADY_MIN}m`,
      gracefulStop: '30s',
    },
  },

  // SLA/Error 등 Budget 관점 임계값 (Grafana에서 바로 보려고 흔히 쓰는 것들)
  thresholds: {
    http_req_failed: ['rate<0.01'],             // 전체 에러율 < 1%
    http_req_duration: ['p(95)<400', 'p(99)<800'], // p95 < 400ms, p99 < 800ms
    'checks{type:health}': ['rate==1.0'],       // 헬스체크는 100% 성공
  },

  // 클라이언트 튜닝 (기본 keepalive on)
  // userAgent, dns, batch 등 고급옵션이 필요하면 여기 추가
};

// 공통 Headers (캐시 우회/트래픽 구분을 위한 태그)
const COMMON_HEADERS = {
  'User-Agent': `k6-30k-rps/1.0`,
  'X-Test-Run': `${__ENV.RUN_ID || 'local'}`
};

// 테스트 시나리오

// 1) 워밍업: 캐시 예열/DB 커넥션 풀 안정화
export function scenario_warmup() {
  const url = `${TARGET_BASE}${HEALTH_PATH}`;
  const res = http.get(url, { headers: COMMON_HEADERS, tags: { type: 'health' } });
  check(res, { '200': r => r.status === 200 });
  if (THINK) sleep(THINK);
}

// 2) 메인 부하: 읽기 5% + 핵심 API 95% 
export function scenario_main() {
  // 간단한 가중치 기반 라우팅
  const r = Math.random();
  if (r < RATIO_HEALTH) {
    const res = http.get(`${TARGET_BASE}${HEALTH_PATH}`, { headers: COMMON_HEADERS, tags: { type: 'health' } });
    check(res, { '200': r => r.status === 200 });
  } else {
    const payload = JSON.stringify({
      itemId: __ENV.ITEM_ID || 'concert-2025-09-30',
      quantity: 1,
      // 토큰/세션이 필요하면 __ENV.AUTH_HEADER 등으로 주입
    });
    const headers = { ...COMMON_HEADERS, 'Content-Type': 'application/json' };
    const res = http.post(`${TARGET_BASE}${MAIN_PATH}`, payload, { headers, tags: { type: 'main' } });
    check(res, {
      '2xx/3xx': r => r.status >= 200 && r.status < 400,
    });
  }
  if (THINK) sleep(THINK);
}

// 3) 쿨다운: 시스템 회복국면 관찰 (스파이크 후 안정화 확인)
export function scenario_cooldown() {
  const res = http.get(`${TARGET_BASE}${HEALTH_PATH}`, { headers: COMMON_HEADERS, tags: { type: 'health' } });
  check(res, { '200': r => r.status === 200 });
  if (THINK) sleep(THINK);
}