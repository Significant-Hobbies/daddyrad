// DaddyRad umbrella worker: serves the daddy-series landing on the apex and
// redirects www to the apex. Each app's subdomain is owned by its own worker.
const APEX = 'daddyrad.com';
const CANONICAL = `https://${APEX}`;

/** @param {Response} response */
function secure(response) {
  const result = new Response(response.body, response);
  result.headers.set('X-Content-Type-Options', 'nosniff');
  result.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  result.headers.set('Content-Security-Policy', "default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' https://sassmaker.com https://health.sassmaker.com; connect-src 'self' https://sassmaker.com https://api.sassmaker.com https://ingest.sassmaker.com; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  return result;
}
export default {
  /** @param {Request} request @param {Env} env */
  async fetch(request, env) {
    if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    const url = new URL(request.url);
    if (url.hostname === `www.${APEX}`) return Response.redirect(CANONICAL + url.pathname + url.search, 301);
    if (url.hostname !== APEX) return new Response('Not found', { status: 404 });
    const response = await env.ASSETS.fetch(request);
    return secure(response);
  },
};
