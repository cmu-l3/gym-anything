#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import socket
import time
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


BENCHMARK_ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the dashboard's real VNC launch and teardown lifecycle.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8767")
    parser.add_argument("--environment", default="domino_autopsy_env")
    parser.add_argument("--out-dir", default=str(BENCHMARK_ROOT / "dashboard" / "evidence"))
    parser.add_argument("--timeout-seconds", type=int, default=180)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output = Path(args.out_dir)
    output.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    result: dict[str, object] = {"ok": False, "environment": args.environment}

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.goto(f"{args.base_url}/#/environment/{args.environment}", wait_until="networkidle")
        expect(page.locator(".detail-title")).to_be_visible()
        page.locator(f'[data-quick-launch="{args.environment}"]').click()

        expect(page.locator(".sessions-page")).to_be_visible()
        card = page.locator(".session-card").first
        expect(card).to_be_visible()
        expect(card).to_have_attribute("data-status", "running", timeout=args.timeout_seconds * 1000)

        payload = page.evaluate("async () => await (await fetch('/api/sessions')).json()")
        session = next(item for item in payload["sessions"] if item["environment_id"] == args.environment)
        port = int(session["session"]["vnc_port"])
        password = str(session["session"]["vnc_password"])
        if not session.get("viewer_opened"):
            raise AssertionError("dashboard reached VNC ready state but did not invoke the viewer")
        with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
            banner = connection.recv(12)
        if not banner.startswith(b"RFB "):
            raise AssertionError(f"port {port} did not answer as VNC: {banner!r}")

        # Let the normal dashboard poll ingest the viewer-opened state before
        # attaching the node-identity probe used to detect destructive refreshes.
        page.wait_for_timeout(1800)
        expect(card).to_have_attribute("data-status", "running")
        card.evaluate("node => { node.dataset.stabilityProbe = 'live-poll'; }")
        page.locator(".sessions-page").evaluate("node => { node.dataset.stabilityProbe = 'live-page'; }")
        uptime_before = card.locator("[data-session-uptime]").text_content()
        page.wait_for_timeout(3400)
        expect(card).to_have_attribute("data-stability-probe", "live-poll")
        expect(page.locator(".sessions-page")).to_have_attribute("data-stability-probe", "live-page")
        uptime_after = card.locator("[data-session-uptime]").text_content()
        if uptime_before == uptime_after:
            raise AssertionError("session uptime did not advance while preserving the live card")
        result["poll_stable_during_uptime"] = True

        page.screenshot(path=str(output / "live-session-running.png"), full_page=True)
        result.update(
            {
                "session_id": session["id"],
                "vnc_address": f"localhost::{port}",
                "vnc_password": password,
                "vnc_banner": banner.decode("ascii", errors="replace").strip(),
                "viewer_opened": True,
            }
        )

        card.locator("[data-stop-session]").click()
        expect(card).to_have_attribute("data-status", "stopped", timeout=60_000)
        page.screenshot(path=str(output / "live-session-stopped.png"), full_page=True)

        deadline = time.monotonic() + 15
        port_closed = False
        while time.monotonic() < deadline:
            try:
                probe = socket.create_connection(("127.0.0.1", port), timeout=1)
                probe.close()
            except OSError:
                port_closed = True
                break
            time.sleep(0.5)
        if not port_closed:
            raise AssertionError(f"VNC port {port} remained open after dashboard teardown")
        result["port_closed_after_stop"] = True
        result["ok"] = True
        browser.close()

    if errors:
        raise AssertionError(f"dashboard browser errors: {errors}")
    (output / "live-vnc-summary.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
