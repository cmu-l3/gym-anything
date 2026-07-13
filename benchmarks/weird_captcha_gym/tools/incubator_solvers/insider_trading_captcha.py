from __future__ import annotations

import json
import time
from pathlib import Path


MECHANIC_ID = "insider_trading_captcha"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new_challenge(state_dir: Path, old_challenge: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != old_challenge:
            return
        time.sleep(0.05)
    raise AssertionError("insider trading challenge did not regenerate after failure")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".market-start").click()
    page.wait_for_function("() => window.insiderTradingCaptchaModel?.tick === 0")
    _screenshot(page, out_dir, mechanic, "active-open")
    page.locator(".market-force-close").click()
    _wait_new_challenge(state_dir, before)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')", timeout=8_000)
    page.wait_for_selector('.insider-market-captcha[data-fresh-failure="true"]')
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    actions = [str(action) for action in truth["solver_actions"]]
    page.locator(".market-start").click()
    count = len(actions)
    captured = False
    for tick, side in enumerate(actions):
        page.wait_for_function(
            "tick => window.insiderTradingCaptchaModel?.tick === tick && window.insiderTradingCaptchaModel?.running === true",
            arg=tick,
            timeout=5_000,
        )
        if tick < count - int(truth["order_delay_ticks"]):
            button = page.locator(f'.market-order-button[data-side="{side}"]')
            if button.is_disabled():
                raise AssertionError(f"solver action {side} was disabled at tick {tick}")
            button.click()
        if not captured and tick >= max(4, count // 3) and page.locator(".market-ledger-list li[data-side]").count() >= 2:
            _screenshot(page, out_dir, mechanic, "active-delayed-ledger")
            captured = True
        if tick < count - 1:
            page.wait_for_function(
                "tick => window.insiderTradingCaptchaModel?.tick > tick || window.insiderTradingCaptchaModel?.submitting === true",
                arg=tick,
                timeout=5_000,
            )
    _screenshot(page, out_dir, mechanic, "solved-final-settlement")
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.startsWith('PASS')", timeout=8_000)
    result = _read(state_dir / "result.json")
    if result.get("orders") != [{"tick": index, "side": side} for index, side in enumerate(actions)]:
        raise AssertionError("browser order tape differs from the generated solver strategy")
    if int((result.get("final") or {}).get("position", -1)) != 0:
        raise AssertionError("market solver did not close flat")
