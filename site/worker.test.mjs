import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.mjs';

const env = { ASSETS: { fetch: (request) => Promise.resolve(new Response('asset', { status: 200 })) } };

test('apex serves assets', async () => {
  const res = await worker.fetch(new Request('https://daddyrad.com/'), env);
  assert.equal(res.status, 200);
  const csp = res.headers.get('Content-Security-Policy');
  assert.match(csp, /https:\/\/health\.sassmaker\.com/);
  assert.match(csp, /https:\/\/api\.sassmaker\.com/);
  assert.match(csp, /https:\/\/ingest\.sassmaker\.com/);
});

test('www redirects to apex preserving path', async () => {
  const res = await worker.fetch(new Request('https://www.daddyrad.com/foo?x=1'), env);
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), 'https://daddyrad.com/foo?x=1');
});

test('unknown hosts 404', async () => {
  const res = await worker.fetch(new Request('https://daddyrad.workers.dev/'), env);
  assert.equal(res.status, 404);
});

test('non-GET methods rejected', async () => {
  const res = await worker.fetch(new Request('https://daddyrad.com/', { method: 'POST' }), env);
  assert.equal(res.status, 405);
});


test('missing routes serve the branded guide with genuine 404 status', async () => {
  const { readFile } = await import('node:fs/promises');
  const html = await readFile(new URL('./public/404.html', import.meta.url), 'utf8');
  const missingEnv = { ASSETS: { fetch: async request => new URL(request.url).pathname === '/404.html'
    ? new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } })
    : new Response(null, { status: 404 }) } };
  const response = await worker.fetch(new Request('https://daddyrad.com/missing'), missingEnv);
  assert.equal(response.status, 404);
  assert.match(response.headers.get('Content-Type'), /text\/html/);
  assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
  const body = await response.text();
  assert.match(body, /Return home/);
  for (const app of ['storage', 'performance', 'browser', 'context']) assert.ok(body.includes(`https://${app}.daddyrad.com`));
  const head = await worker.fetch(new Request('https://daddyrad.com/missing', { method: 'HEAD' }), missingEnv);
  assert.equal(head.status, 404);
  assert.equal(await head.text(), '');
});

test('missing guide asset preserves a 404 without recursion', async () => {
  let requests = 0;
  const response = await worker.fetch(new Request('https://daddyrad.com/missing'), {
    ASSETS: { fetch: async () => { requests++; return new Response(null, { status: 404 }); } },
  });
  assert.equal(response.status, 404);
  assert.equal(requests, 2);
});

test('guide resolves the static assets HTML redirect without redirecting the visitor', async () => {
  const paths = [];
  const response = await worker.fetch(new Request('https://daddyrad.com/missing'), {
    ASSETS: { fetch: async request => {
      const path = new URL(request.url).pathname;
      paths.push(path);
      if (path === '/404.html') return Response.redirect('https://daddyrad.com/404', 307);
      if (path === '/404') return new Response('<h1>Return home</h1>', { headers: { 'Content-Type': 'text/html' } });
      return new Response(null, { status: 404 });
    } },
  });
  assert.equal(response.status, 404);
  assert.equal(response.headers.has('Location'), false);
  assert.match(await response.text(), /Return home/);
  assert.deepEqual(paths, ['/missing', '/404.html', '/404']);
});

test('guide does not follow unrelated or external redirects', async () => {
  for (const location of ['https://example.com/404', 'https://daddyrad.com/', 'https://daddyrad.com/404?redirect=1']) {
    let requests = 0;
    const response = await worker.fetch(new Request('https://daddyrad.com/missing'), {
      ASSETS: { fetch: async () => ++requests === 1 ? new Response(null, { status: 404 }) : Response.redirect(location, 307) },
    });
    assert.equal(response.status, 404);
    assert.equal(requests, 2);
  }
});


test('approved local fonts are permitted without broadening other resource origins', async () => {
  const response = await worker.fetch(new Request('https://daddyrad.com/fonts/fleet-footer-precise-v1/geist.woff2'), env);
  const directives = Object.fromEntries(response.headers.get('Content-Security-Policy').split(';').filter(x => x.trim()).map(x => { const [name, ...values] = x.trim().split(/\s+/); return [name, values]; }));
  assert.deepEqual(directives['font-src'], ["'self'"]);
  assert.deepEqual(directives['img-src'], ["'self'", 'data:']);
  assert.deepEqual(directives['default-src'], ["'none'"]);
  assert.deepEqual(directives['script-src'], ["'self'", 'https://sassmaker.com', 'https://health.sassmaker.com']);
  assert.deepEqual(directives['connect-src'], ["'self'", 'https://sassmaker.com', 'https://api.sassmaker.com', 'https://ingest.sassmaker.com']);
  for (const name of ['base-uri', 'form-action', 'frame-ancestors']) assert.deepEqual(directives[name], ["'none'"]);
});
