# Future Agent Notes

## Environment Creation (Generic)

- Always verify actual display resolution in-VM before clicking (`xdpyinfo`), then scale VLM coordinates accordingly (many tools normalize to `1280x720`).
- Prefer focus-safe UI control: activate target window first, then type/click. If actions seem ignored, treat focus/window targeting as the first suspect.
- For Docker-based environments, support optional authenticated pulls to avoid Docker Hub rate limits (read credentials from a mounted env file; never hardcode secrets in scripts). pat and username are in .env file.
- Use explicit readiness checks (health endpoints/container health/HTTP polling) instead of fixed sleeps.
- Keep task start state deterministic: close stale app instances, relaunch cleanly, and land on the exact required screen.
- Capture evidence from real runs: screenshots, setup logs, and minimal runtime diagnostics.
