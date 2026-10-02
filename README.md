# DaddyRad

Umbrella home for four independent, local-first Mac utilities. The apex static Worker serves the landing and redirects www to daddyrad.com; each app owns its site and repository.

Unknown routes keep HTTP 404 and render the owner-selected A route guide, with a home link and all four known app destinations. The Worker preserves existing security headers, supports body-free HEAD, and falls back to its original 404 when the guide asset is unavailable.

From site/: `node --test worker.test.mjs app-health-events.test.mjs` for focused checks. Public deployment requires explicit owner approval.
