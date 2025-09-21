import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '1m30s', target: 10 },
    { duration: '20s', target: 0 },
  ],
};

#--vus=10 (virtual users) --duration=10s 와 동일한 효과
#export const options = {
#  vus: 10,
#  duration: '10s',
#};

export default function () {
  http.get('<https://test.k6.io>');
  sleep(1);
}