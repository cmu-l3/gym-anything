#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


BENCHMARK_ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise and capture the CAPTCHA Bench visual dashboard.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8767")
    parser.add_argument("--out-dir", default=str(BENCHMARK_ROOT / "dashboard" / "evidence"))
    parser.add_argument("--exercise-reviews", action="store_true", help="Mutate the connected review ledger to test approve/revision persistence; use only with an isolated review path")
    return parser.parse_args()


def capture(page, output: Path, name: str, *, full_page: bool = True) -> None:
    page.screenshot(path=str(output / f"{name}.png"), full_page=full_page)


def main() -> None:
    args = parse_args()
    output = Path(args.out_dir)
    output.mkdir(parents=True, exist_ok=True)
    for name in (
        "observatory.png",
        "environment-search.png",
        "environment-detail.png",
        "review-queue.png",
        "environment-review-revision.png",
        "environment-review-approved.png",
        "mobile-review-queue.png",
        "mobile-review-desk.png",
        "evaluation-preview.png",
        "live-sessions-empty.png",
        "interaction-five-built.png",
        "interaction-five-detail.png",
        "interaction-six-built.png",
        "interaction-six-detail.png",
        "roadmap-concepts.png",  # stale pre-promotion captures
        "roadmap-detail.png",
        "interaction-six-roadmap.png",
        "incubator-candidates.png",
        "incubator-detail.png",
        "incubator-built.png",
        "incubator-built-detail.png",
        "atlas-overview.png",
        "atlas-specimen.png",  # legacy flat-Atlas evidence name
        "atlas-item.png",
        "atlas-instances.png",
        "atlas-instance.png",
        "atlas-source.png",
        "atlas-compare.png",
        "mobile-environments.png",
        "mobile-atlas.png",
        "summary.json",
    ):
        (output / name).unlink(missing_ok=True)
    errors: list[str] = []

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        page.goto(args.base_url, wait_until="networkidle")
        expect(page.locator(".display-title")).to_contain_text("screenshot")
        expect(page.locator("#nav-environment-count")).to_have_text("65")
        expect(page.locator('[data-nav="atlas"]')).to_have_count(0)
        expect(page.locator('[data-nav="reviews"]')).to_be_visible()
        expect(page.locator(".specimen-card")).to_have_count(3)
        expect(page.locator(".atlas-home-portal")).to_have_count(0)
        expect(page.locator('[data-open-env="shadow_crime_lab_env"]')).to_have_count(1)
        expect(page.locator('[data-open-env="robot_art_critic_env"]')).to_have_count(1)
        capture(page, output, "observatory")

        if args.exercise_reviews:
            expect(page.locator("#nav-review-count")).to_have_text("63")
            page.locator('[data-nav="reviews"]').click()
            expect(page.locator(".reviews-page")).to_be_visible()
            expect(page.locator(".review-ledger-stamp")).to_contain_text("0 / 63")
            expect(page.locator(".review-grid .environment-card")).to_have_count(63)
            expect(page.locator('.review-summary [data-review-filter="pending"] b')).to_have_text("63")
            capture(page, output, "review-queue")

            page.locator("#review-search").fill("domino")
            expect(page.locator(".review-grid .environment-card")).to_have_count(1)
            page.locator('.review-grid [data-open-env="domino_autopsy_env"] .card-media').click()
            expect(page.locator(".detail-title")).to_have_text("Domino Autopsy")
            expect(page.locator('[data-action="open-review-desk"]')).to_contain_text("Review · Pending")
            page.locator('[data-action="open-review-desk"]').click()
            expect(page.locator("#review-desk")).to_have_attribute("data-review-status", "pending")
            page.locator('[data-review-choice="looks_good"]').click()
            page.locator('#environment-review-form [name="note"]').fill("AUTOMATED UI FIXTURE — solution-film screening only; hands-on acceptance remains pending.")
            page.locator('#environment-review-form [type="submit"]').click()
            expect(page.locator("#review-desk")).to_have_attribute("data-review-status", "looks_good")
            expect(page.locator("#detail-review-state")).to_have_text("Looks good · hands-on pending")
            expect(page.locator("#nav-review-count")).to_have_text("63")
            page.locator('[data-review-choice="revision_requested"]').click()
            page.locator('#environment-review-form [name="note"]').fill("AUTOMATED UI FIXTURE — exercises revision feedback; this is not a human verdict.")
            page.locator(".detail-page").evaluate("node => { node.dataset.stabilityProbe = 'review-save'; }")
            page.locator('#environment-review-form [type="submit"]').click()
            expect(page.locator("#review-desk")).to_have_attribute("data-review-status", "revision_requested")
            expect(page.locator("#detail-review-state")).to_have_text("Needs revision")
            expect(page.locator(".detail-page")).to_have_attribute("data-stability-probe", "review-save")
            expect(page.locator(".review-history-wrap summary")).to_contain_text("2")
            page.locator("#review-desk").evaluate("node => node.scrollIntoView({block: 'start'})")
            page.wait_for_timeout(120)
            capture(page, output, "environment-review-revision", full_page=False)

            page.locator('[data-review-choice="approved"]').click()
            page.locator('#environment-review-form [name="note"]').fill("AUTOMATED UI FIXTURE — exercises approval persistence; this is not human evidence.")
            page.locator('#environment-review-form [type="submit"]').click()
            expect(page.locator("#review-desk")).to_have_attribute("data-review-status", "approved")
            expect(page.locator("#detail-review-state")).to_have_text("Approved")
            expect(page.locator('[data-action="open-review-desk"]')).to_contain_text("Review · Approved")
            expect(page.locator(".review-history-wrap summary")).to_contain_text("3")
            expect(page.locator("#nav-review-count")).to_have_text("62")
            page.locator("#review-desk").evaluate("node => node.scrollIntoView({block: 'start'})")
            page.wait_for_timeout(120)
            capture(page, output, "environment-review-approved", full_page=False)

            persisted = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
            persisted.on("pageerror", lambda exc: errors.append(f"review persistence: {exc}"))
            persisted.goto(f"{args.base_url}/#/environment/domino_autopsy_env", wait_until="networkidle")
            expect(persisted.locator("#review-desk")).to_have_attribute("data-review-status", "approved")
            expect(persisted.locator('#environment-review-form [name="note"]')).to_have_value("AUTOMATED UI FIXTURE — exercises approval persistence; this is not human evidence.")
            persisted.close()

            page.locator('[data-action="back-to-reviews"]').click()
            page.locator('[data-review-filter="approved"]').last.click()
            expect(page.locator(".review-grid .environment-card")).to_have_count(1)
            expect(page.locator('.review-grid .card-review[data-review-status="approved"]')).to_have_count(1)

        page.locator('[data-nav="environments"]').click()
        expect(page.locator("#environment-search")).to_be_visible()
        expect(page.locator("#review-filter")).to_be_visible()
        expect(page.locator(".environment-card")).to_have_count(63)
        expect(page.locator('#stage-filter option[value="concept"]')).to_have_count(0)
        expect(page.locator('#stage-filter option[value="scaffold"]')).to_have_count(0)
        page.locator(".environments-page").evaluate("node => { node.dataset.stabilityProbe = 'catalog'; }")
        page.locator("#environment-search").fill("domino")
        expect(page.locator(".environment-card")).to_have_count(1)
        expect(page.locator(".environment-card h3")).to_have_text("Domino Autopsy")
        expect(page.locator(".environments-page")).to_have_attribute("data-stability-probe", "catalog")
        if args.exercise_reviews:
            page.locator("#review-filter").select_option("approved")
            expect(page.locator(".environment-card")).to_have_count(1)
            expect(page.locator('.card-review[data-review-status="approved"]')).to_have_count(1)
            page.locator("#review-filter").select_option("revision_requested")
            expect(page.locator(".environment-card")).to_have_count(0)
            page.locator("#review-filter").select_option("all")
            expect(page.locator(".environment-card")).to_have_count(1)
        page.locator('[data-view="compact"]').click()
        expect(page.locator("#environment-grid")).to_have_class("environment-grid is-compact")
        expect(page.locator(".environments-page")).to_have_attribute("data-stability-probe", "catalog")
        capture(page, output, "environment-search")

        page.locator('.environment-card[data-open-env="domino_autopsy_env"] .card-media').click()
        expect(page.locator(".detail-title")).to_have_text("Domino Autopsy")
        expect(page.locator(".filmstrip button")).to_have_count(5)
        expect(page.locator(".launch-console")).to_contain_text("One-click browser play")
        page.locator(".detail-page").evaluate("node => { node.dataset.stabilityProbe = 'gallery'; }")
        page.locator(".filmstrip button").nth(1).click()
        expect(page.locator(".hero-frame-label")).to_contain_text("EVIDENCE FRAME 02")
        expect(page.locator("#modal-root")).to_be_empty()
        expect(page.locator(".detail-page")).to_have_attribute("data-stability-probe", "gallery")
        capture(page, output, "environment-detail")

        page.locator('[data-config-launch="domino_autopsy_env"]').first.click()
        expect(page.locator("#launch-mode")).to_have_value("browser")
        expect(page.locator('#launch-mode option[value="vnc"]')).to_have_count(1)
        expect(page.locator("#launch-form")).to_contain_text("real local UI and grader")
        page.locator(".modal-close").click()

        solution = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        solution.on("pageerror", lambda exc: errors.append(f"solution video: {exc}"))
        solution.goto(f"{args.base_url}/#/environment/semantic_drag_drop_absurdity_env", wait_until="networkidle")
        expect(solution.locator('[data-solution-video="semantic_drag_drop_absurdity"]')).to_be_visible()
        expect(solution.locator('.solution-reel source[type="video/mp4"]')).to_have_attribute(
            "src", "/media/evidence/reviewed_overhaul_v1/semantic_drag_drop_absurdity-walkthrough.mp4"
        )
        solution.locator(".solution-reel > summary").click()
        expect(solution.locator(".solution-reel")).to_have_attribute("open", "")
        solution.wait_for_function("document.querySelector('.solution-reel video').readyState >= 1")
        expect(solution.locator(".solution-reel video")).to_have_js_property("videoWidth", 1280)
        expect(solution.locator(".solution-reel video")).to_have_js_property("videoHeight", 720)
        solution.close()

        page.locator('[data-open-eval="domino_autopsy_env"]').first.click()
        expect(page.locator("#eval-form")).to_be_visible()
        expect(page.locator('[name="preview_only"]')).to_be_checked()
        page.locator("#eval-model").fill("Qwen/Qwen3-VL-4B-Thinking")
        page.locator("#eval-form [type=submit]").click()
        expect(page.locator(".evaluations-page")).to_be_visible()
        expect(page.locator(".status-pill").filter(has_text="preview").first).to_be_visible()
        expect(page.locator(".eval-command").first).to_contain_text("weird_captcha_gym")
        page.locator(".evaluations-page").evaluate("node => { node.dataset.stabilityProbe = 'evaluation-poll'; }")
        eval_details = page.locator("[data-toggle-eval]").first
        eval_details.focus()
        page.wait_for_timeout(2100)
        expect(page.locator(".evaluations-page")).to_have_attribute("data-stability-probe", "evaluation-poll")
        expect(eval_details).to_be_focused()
        capture(page, output, "evaluation-preview")

        page.locator('[data-nav="sessions"]').click()
        expect(page.locator(".sessions-page")).to_be_visible()
        expect(page.locator(".empty-state")).to_contain_text("No specimens are awake")
        page.locator(".sessions-page").evaluate("node => { node.dataset.stabilityProbe = 'session-poll'; }")
        empty_launch = page.locator(".empty-state [data-action='open-launch-picker']")
        empty_launch.focus()
        page.wait_for_timeout(2100)
        expect(page.locator(".sessions-page")).to_have_attribute("data-stability-probe", "session-poll")
        expect(empty_launch).to_be_focused()
        capture(page, output, "live-sessions-empty")

        page.keyboard.press("Meta+k")
        expect(page.locator("#palette-input")).to_be_focused()
        page.locator("#palette-input").fill("funeral")
        expect(page.locator(".palette-item")).to_have_count(1)
        page.keyboard.press("Escape")

        interaction_five = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        interaction_five.on("pageerror", lambda exc: errors.append(f"interaction five: {exc}"))
        interaction_five.goto(f"{args.base_url}/#/environments", wait_until="networkidle")
        interaction_five.locator('[data-filter-group="Interaction V"]').click()
        expect(interaction_five.locator(".environment-card")).to_have_count(5)
        expect(interaction_five.locator(".quick-launch")).to_have_count(5)
        expect(interaction_five.locator('[data-open-env="photograph_eats_the_room_env"]')).to_have_count(1)
        expect(interaction_five.locator('[data-open-env="forced_perspective_moving_day_env"]')).to_have_count(1)
        capture(interaction_five, output, "interaction-five-built")
        interaction_five.locator('[data-open-env="photograph_eats_the_room_env"] .card-media').click()
        expect(interaction_five.locator(".detail-title")).to_have_text("The Photograph Eats the Room")
        expect(interaction_five.locator(".launch-console")).to_contain_text("WIRING REPLAY PASSED · HUMAN REVIEW PENDING")
        expect(interaction_five.locator("[data-config-launch]")).to_have_count(2)
        expect(interaction_five.locator(".archive-chip")).to_have_count(0)
        capture(interaction_five, output, "interaction-five-detail")
        interaction_five.close()

        interaction_six = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        interaction_six.on("pageerror", lambda exc: errors.append(f"interaction six: {exc}"))
        interaction_six.goto(f"{args.base_url}/#/environments", wait_until="networkidle")
        interaction_six.locator('[data-filter-group="Interaction VI"]').click()
        expect(interaction_six.locator(".environment-card")).to_have_count(5)
        expect(interaction_six.locator(".quick-launch")).to_have_count(5)
        expect(interaction_six.locator('[data-open-env="lidar_blacksite_env"]')).to_have_count(1)
        expect(interaction_six.locator('[data-open-env="portal_freight_oversized_parcel_env"]')).to_have_count(1)
        capture(interaction_six, output, "interaction-six-built")
        interaction_six.locator('[data-open-env="tomographic_baggage_surgery_env"] .card-media').click()
        expect(interaction_six.locator(".detail-title")).to_have_text("Tomographic Baggage Surgery")
        expect(interaction_six.locator(".launch-console")).to_contain_text("WIRING REPLAY PASSED · HUMAN REVIEW PENDING")
        expect(interaction_six.locator("[data-config-launch]")).to_have_count(2)
        expect(interaction_six.locator(".archive-chip")).to_have_count(0)
        capture(interaction_six, output, "interaction-six-detail")
        interaction_six.close()

        incubator = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        incubator.on("pageerror", lambda exc: errors.append(f"incubator: {exc}"))
        incubator.goto(f"{args.base_url}/#/environments", wait_until="networkidle")
        incubator.locator("#stage-filter").select_option("built")
        incubator.locator('[data-filter-group="Incubator"]').click()
        expect(incubator.locator(".environment-card")).to_have_count(23)
        expect(incubator.locator(".quick-launch")).to_have_count(23)
        expect(incubator.locator('[data-open-env="insider_trading_captcha_env"]')).to_have_count(1)
        expect(incubator.locator('[data-open-env="thirty_year_time_wheel_env"]')).to_have_count(1)
        capture(incubator, output, "incubator-built")
        incubator.locator('[data-open-env="insider_trading_captcha_env"] .card-media').click()
        expect(incubator.locator(".detail-title")).to_have_text("Insider Trading CAPTCHA")
        expect(incubator.locator(".launch-console")).to_contain_text("WIRING REPLAY PASSED · HUMAN REVIEW PENDING")
        expect(incubator.locator("[data-config-launch]")).to_have_count(2)
        expect(incubator.locator(".roadmap-chip")).to_have_count(0)
        expect(incubator.locator(".detail-page")).to_have_css("opacity", "1")
        capture(incubator, output, "incubator-built-detail")
        incubator.close()

        mobile = browser.new_page(viewport={"width": 390, "height": 844}, device_scale_factor=1)
        mobile.on("pageerror", lambda exc: errors.append(f"mobile: {exc}"))
        mobile.goto(f"{args.base_url}/#/environments", wait_until="networkidle")
        expect(mobile.locator("#environment-search")).to_be_visible()
        mobile.locator(".mobile-nav-toggle").click()
        expect(mobile.locator("body")).to_have_class("nav-open")
        expect(mobile.locator(".sidebar")).to_have_css("transform", "matrix(1, 0, 0, 1, 0, 0)")
        capture(mobile, output, "mobile-environments", full_page=False)
        mobile.close()

        if args.exercise_reviews:
            mobile_review = browser.new_page(viewport={"width": 390, "height": 844}, device_scale_factor=1)
            mobile_review.on("pageerror", lambda exc: errors.append(f"mobile review: {exc}"))
            mobile_review.goto(f"{args.base_url}/#/reviews", wait_until="networkidle")
            expect(mobile_review.locator(".review-ledger-stamp")).to_contain_text("1 / 63")
            expect(mobile_review.locator(".review-filter-tabs")).to_be_visible()
            capture(mobile_review, output, "mobile-review-queue", full_page=False)
            mobile_review.goto(f"{args.base_url}/#/environment/domino_autopsy_env", wait_until="networkidle")
            expect(mobile_review.locator('[data-action="open-review-desk"]')).to_contain_text("Review · Approved")
            mobile_review.locator('[data-action="open-review-desk"]').click()
            mobile_review.locator("#review-desk").evaluate("node => window.scrollTo({top: window.scrollY + node.getBoundingClientRect().top - 73, behavior: 'instant'})")
            mobile_review.wait_for_timeout(180)
            expect(mobile_review.locator("#review-desk")).to_have_attribute("data-review-status", "approved")
            capture(mobile_review, output, "mobile-review-desk", full_page=False)
            mobile_review.close()
        browser.close()

    if errors:
        raise AssertionError(f"dashboard browser errors: {errors}")
    summary = {
        "ok": True,
        "screenshots": sorted(path.name for path in output.glob("*.png")),
        "checks": [
            "catalog-derived stats",
            *([
                "persistent human review queue",
                "revision request with required feedback",
                "approval transition with immutable decision history",
                "review persistence across browser pages",
                "review save without page-level reconstruction",
                "responsive review queue and decision desk",
                "review status filtering on the environment catalog",
            ] if args.exercise_reviews else []),
            "environment search",
            "catalog controls without page reconstruction",
            "screenshot detail gallery",
            "gallery swap without page-level transition",
            "dual-format Semantic Drag-Drop solution playback",
            "safe evaluation command preview",
            "poll-stable evaluation focus",
            "live-session empty state",
            "poll-stable session focus",
            "command palette",
            "Survey-free navigation and Observatory",
            "local-browser-first launch controls with preserved VNC mode",
            "zero concept and scaffold cards",
            "five launchable Interaction V builds and evidence dossier",
            "five launchable Interaction VI builds and evidence dossier",
            "twenty-three launchable Incubator builds",
            "Incubator built dossier",
            "responsive navigation",
        ],
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
