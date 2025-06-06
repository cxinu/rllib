import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    vus: 100,
    duration: '30s',
};

export default function() {
    let res = http.get('http://localhost:8080/test');
    check(res, {
        'status is 200': (r) => r.status === 200,
    });
    sleep(0.1);
}
