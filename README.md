# DaddyRad

> **Moved — this repository is retired (2026-10-09).**
>
> - The daddyrad.com site (Worker `daddyrad`) now lives in [Significant-Hobbies/ios-landings `sites/daddyrad/`](https://github.com/Significant-Hobbies/ios-landings/tree/main/sites/daddyrad) and deploys from there with `pnpm run deploy:daddyrad`. Do not deploy `site/` from this repo.
> - The Swift MCP source preview (`mcp/`) and its macOS CI moved to [Significant-Hobbies/chatgpt-memory-insights `mcp/`](https://github.com/Significant-Hobbies/chatgpt-memory-insights/tree/main/mcp).
>
> This repo is kept for history only (site source at `bfdd8a8`, tracked in Significant-Hobbies/ios-landings#42).

Umbrella home for four independent, local-first Mac utilities. The apex static Worker serves the landing and redirects www to daddyrad.com; each app owns its site and repository.

Unknown routes keep HTTP 404 and render the owner-selected A route guide, with a home link and all four known app destinations. The Worker preserves existing security headers, supports body-free HEAD, and falls back to its original 404 when the guide asset is unavailable.

From site/: `node --test worker.test.mjs app-health-events.test.mjs` for focused checks. Public deployment requires explicit owner approval.
