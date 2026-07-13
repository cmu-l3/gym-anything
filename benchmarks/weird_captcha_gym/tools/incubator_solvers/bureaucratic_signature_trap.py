from __future__ import annotations

import math
from pathlib import Path

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    center, drag_delta, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "bureaucratic_signature_trap"


def _align(page, form: dict) -> None:
    # Sheets are stacked in manifest order; expose and move the top carbon first
    # so no lower rail tab is accidentally operated through translucent paper.
    for layer in reversed(form["layers"]):
        dx = float(layer["target"]["x"]) - float(layer["initial"]["x"])
        dy = float(layer["target"]["y"]) - float(layer["initial"]["y"])
        drag_delta(page, page.locator(f'[data-sheet-id="{layer["id"]}"] .sheet-tab'), dx, dy, maximum_step=25)


def _stroke(page, form: dict, radius: float, count: int) -> None:
    canvas = page.locator(".signature-surface")
    box = canvas.bounding_box()
    assert box
    stage = form["stage"]
    aperture = form["aperture"]
    points = []
    for index in range(count + 1):
        angle = index * math.tau / count
        px = float(aperture["x"]) + radius * math.cos(angle)
        py = float(aperture["y"]) + radius * math.sin(angle)
        points.append((box["x"] + px / float(stage["width"]) * box["width"], box["y"] + py / float(stage["height"]) * box["height"]))
    page.mouse.move(*points[0])
    page.mouse.down()
    for point in points[1:]:
        page.mouse.move(*point, steps=1)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    truth = read_json(state_dir / "ground_truth.json")
    before, form = truth["challenge_id"], truth["form"]
    _align(page, form)
    _stroke(page, form, 8, 5)
    page.locator(".carbon-submit").click()
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-short-signature-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    form = read_json(state_dir / "public_state.json")["form"]
    _align(page, form)
    _stroke(page, form, float(form["aperture"]["radius"]) * .78, 48)
    shot(page, out_dir, mechanic, "aligned-carbon-continuous-stroke")
    page.locator(".carbon-submit").click()
