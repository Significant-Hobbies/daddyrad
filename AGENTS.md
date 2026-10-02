# DaddyRad agent instructions

DaddyRad is the umbrella site for the daddy series of native macOS utilities.
`mcp/` owns the single local read-only stdio server across the four native cores.
Build it with SwiftPM from sibling app checkouts; see `mcp/README.md`. It does
not expose a network endpoint or access the GUI apps' live state. Keep file
access startup-selected, resource use bounded and process identities opt-in.
`site/` is a small Cloudflare Worker (`daddyrad`) that serves a static landing
on `daddyrad.com` and redirects `www.daddyrad.com`. ContextDaddy now owns its
public site at `context.daddyrad.com`.

Boundaries:

- The apex is the series landing only; each app owns its own subdomain and
  repository (`performance.`, `browser.`, `storage.` on daddyrad.com).
- `context.daddyrad.com` is served by ContextDaddy's own repository and Worker.
- Keep copy honest: no download links for apps without public releases.
- Deploy with `npm run deploy` from `site/` (wrangler). Do not commit, push,
  or release without explicit owner approval.
