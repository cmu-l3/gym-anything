from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "robot_art_critic"
CLASSES = ("umbrella", "sailboat", "fish", "flower", "ladder", "bicycle", "lighthouse", "locomotive")


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_for_new_challenge(state_dir: Path, previous: str) -> str:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read_json(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return current
        time.sleep(.05)
    raise AssertionError("robot critic did not issue a fresh brief after failure")


def _ellipse(cx: float, cy: float, rx: float, ry: float, count: int = 30) -> list[tuple[float, float]]:
    return [
        (cx + rx * math.cos(index * math.tau / count), cy + ry * math.sin(index * math.tau / count))
        for index in range(count)
    ] + [(cx + rx, cy)]


def _sketch_vocabulary() -> dict[str, list[list[tuple[float, float]]]]:
    """Generic object sketches used by the benchmark's physical QA agent.

    These are class-level exemplars, not generated challenge coordinates. The live
    brief supplies only class, lean, and width; the recognizer independently judges
    the pointer transcript against every class in the vocabulary.
    """
    canopy = [
        (.14, .51), (.17, .41), (.23, .31), (.32, .23), (.42, .19), (.50, .18),
        (.58, .19), (.68, .23), (.77, .31), (.83, .41), (.86, .51), (.78, .47),
        (.70, .53), (.62, .47), (.54, .53), (.46, .47), (.38, .53), (.30, .47),
        (.22, .53), (.14, .51),
    ]
    flower_loop: list[tuple[float, float]] = []
    for index in range(71):
        angle = index * math.tau / 70
        radius = .18 + .075 * math.cos(5 * angle)
        flower_loop.append((.50 + radius * math.cos(angle), .39 + radius * math.sin(angle)))
    return {
        "umbrella": [
            canopy,
            [(.50, .50), (.50, .62), (.50, .74), (.51, .84), (.56, .90), (.63, .89), (.67, .84)],
            [(.50, .19), (.22, .52)], [(.50, .19), (.38, .52)], [(.50, .19), (.62, .52)], [(.50, .19), (.78, .52)],
            [(.50, .18), (.50, .10)], [(.23, .63), (.18, .74)], [(.39, .69), (.34, .80)], [(.77, .63), (.72, .74)],
        ],
        "sailboat": [
            [(.17, .73), (.83, .73), (.70, .86), (.31, .86), (.17, .73)],
            [(.50, .72), (.50, .18)],
            [(.47, .23), (.25, .66), (.47, .66), (.47, .23)],
            [(.53, .29), (.77, .66), (.53, .66), (.53, .29)],
            [(.31, .69), (.69, .69)], [(.50, .20), (.20, .72)], [(.50, .20), (.82, .72)],
            [(.50, .18), (.65, .23), (.50, .29), (.50, .18)],
            [(.12, .88), (.34, .86), (.55, .89), (.78, .86), (.91, .88)],
            [(.16, .93), (.37, .91), (.60, .94), (.84, .91)], [(.23, .79), (.41, .77), (.59, .79), (.76, .77)],
        ],
        "fish": [
            _ellipse(.46, .52, .29, .20, 34),
            [(.75, .52), (.91, .33), (.91, .71), (.75, .52)],
            _ellipse(.35, .47, .035, .035, 10),
            [(.18, .53), (.13, .56)], [(.48, .32), (.58, .18), (.66, .38)], [(.47, .71), (.58, .84), (.64, .67)],
            [(.27, .38), (.32, .52), (.27, .64)], [(.43, .46), (.48, .50), (.43, .54)],
            [(.54, .43), (.59, .48), (.54, .53)], [(.62, .48), (.67, .52), (.62, .56)],
        ],
        "flower": [
            flower_loop,
            [(.50, .56), (.50, .66), (.50, .77), (.50, .89)],
            [(.50, .72), (.62, .65), (.70, .69), (.61, .78), (.50, .72)],
            [(.50, .78), (.39, .70), (.31, .74), (.39, .82), (.50, .78)], _ellipse(.50, .39, .055, .055, 14),
            [(.50, .39), (.50, .18)], [(.50, .39), (.68, .27)], [(.50, .39), (.72, .47)],
            [(.50, .39), (.57, .61)], [(.50, .39), (.31, .28)], [(.26, .90), (.74, .90)],
        ],
        "ladder": [
            [(.31, .14), (.31, .88)], [(.69, .14), (.69, .88)],
            [(.31, .22), (.69, .22)], [(.31, .34), (.69, .34)], [(.31, .46), (.69, .46)],
            [(.31, .58), (.69, .58)], [(.31, .70), (.69, .70)], [(.31, .82), (.69, .82)],
            [(.26, .91), (.34, .86)], [(.74, .91), (.66, .86)], [(.27, .14), (.73, .14)],
        ],
        "bicycle": [
            _ellipse(.27, .68, .18, .18, 28), _ellipse(.73, .68, .18, .18, 28),
            [(.27, .68), (.43, .43), (.55, .68), (.27, .68), (.48, .68), (.64, .43), (.43, .43)],
            [(.64, .43), (.73, .68)], [(.62, .39), (.70, .36)], [(.39, .40), (.49, .40)],
            _ellipse(.48, .68, .045, .045, 14), [(.43, .68), (.54, .68)], [(.27, .68), (.48, .68)],
            [(.20, .45), (.38, .45), (.43, .43)], [(.72, .61), (.77, .58)],
        ],
        "lighthouse": [
            [(.34, .84), (.40, .35), (.60, .35), (.66, .84), (.34, .84)], [(.36, .28), (.50, .15), (.64, .28), (.36, .28)],
            [(.40, .28), (.60, .28), (.60, .40), (.40, .40), (.40, .28)], [(.46, .84), (.46, .70), (.54, .70), (.54, .84)],
            [(.38, .48), (.62, .48)], [(.37, .58), (.63, .58)], [(.36, .68), (.64, .68)],
            [(.40, .32), (.12, .23)], [(.60, .32), (.88, .23)], [(.20, .86), (.34, .81), (.43, .86)],
            [(.57, .86), (.68, .81), (.82, .86)], [(.12, .88), (.88, .88)],
        ],
        "locomotive": [
            [(.20, .42), (.69, .42), (.78, .58), (.78, .72), (.20, .72), (.20, .42)],
            [(.18, .31), (.38, .31), (.38, .61), (.18, .61), (.18, .31)], _ellipse(.55, .52, .20, .12, 24),
            [(.57, .40), (.57, .24), (.66, .24), (.69, .40)], [(.78, .60), (.91, .70), (.78, .70)],
            _ellipse(.29, .75, .09, .09, 20), _ellipse(.51, .75, .09, .09, 20), _ellipse(.72, .75, .09, .09, 20),
            [(.29, .75), (.72, .75)], [(.10, .84), (.90, .84)], [(.13, .89), (.87, .89)],
            _ellipse(.63, .16, .055, .045, 14), _ellipse(.73, .10, .07, .05, 14), [(.75, .49), (.83, .49)],
        ],
    }


SKETCHES = _sketch_vocabulary()


def _transformed_sketch(class_name: str, truth: dict) -> list[list[tuple[float, float]]]:
    target = truth["target"]
    angle = math.radians(float(target["pose"]["angle_deg"]))
    cosine, sine = math.cos(angle), math.sin(angle)
    x_scale = int(target["style"]["x_scale_milli"]) / 1000
    scale = .72
    output: list[list[tuple[float, float]]] = []
    for stroke in SKETCHES[class_name]:
        transformed = []
        for x, y in stroke:
            dx, dy = (x - .5) * x_scale, y - .5
            rotated_x = .5 + dx * cosine - dy * sine
            rotated_y = .5 + dx * sine + dy * cosine
            transformed.append((.5 + (rotated_x - .5) * scale, .5 + (rotated_y - .5) * scale))
        output.append(transformed)
    return output


def _humanized(strokes: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Apply small deterministic hand-drawn deviations to every exemplar.

    The passing smoke path intentionally avoids pixel-perfect template input;
    this is a tolerance check for ordinary, slightly wobbly human strokes.
    """
    output: list[list[tuple[float, float]]] = []
    for stroke_index, stroke in enumerate(strokes):
        adjusted: list[tuple[float, float]] = []
        closed = len(stroke) > 2 and math.hypot(stroke[0][0] - stroke[-1][0], stroke[0][1] - stroke[-1][1]) < .02
        for point_index, (x, y) in enumerate(stroke):
            phase = (stroke_index + 1) * 1.73 + point_index * 0.91
            adjusted.append((x + math.sin(phase) * .006, y + math.cos(phase * 1.17) * .006))
        if closed and adjusted:
            adjusted[-1] = adjusted[0]
        output.append(adjusted)
    return output


def _resample(stroke: list[tuple[float, float]], width: int, height: int, maximum_gap: float = 16) -> list[tuple[int, int]]:
    if not stroke:
        return []
    points = [(round(stroke[0][0] * width), round(stroke[0][1] * height))]
    for first, second in zip(stroke, stroke[1:]):
        dx = (second[0] - first[0]) * width
        dy = (second[1] - first[1]) * height
        steps = max(1, math.ceil(math.hypot(dx, dy) / maximum_gap))
        for index in range(1, steps + 1):
            amount = index / steps
            point = (
                round((first[0] + (second[0] - first[0]) * amount) * width),
                round((first[1] + (second[1] - first[1]) * amount) * height),
            )
            if point != points[-1]:
                points.append(point)
    # Even a short rung must generate dense continuous pointer evidence.
    while len(points) < 6 and len(points) >= 2:
        expanded = [points[0]]
        for first, second in zip(points, points[1:]):
            expanded.extend([
                (round((first[0] * 2 + second[0]) / 3), round((first[1] * 2 + second[1]) / 3)),
                (round((first[0] + second[0] * 2) / 3), round((first[1] + second[1] * 2) / 3)),
                second,
            ])
        points = list(dict.fromkeys(expanded))
    return points


def _canvas_to_screen(box: dict, canvas: dict, point: tuple[int, int]) -> tuple[float, float]:
    return (
        box["x"] + point[0] / int(canvas["width"]) * box["width"],
        box["y"] + point[1] / int(canvas["height"]) * box["height"],
    )


def _draw_strokes(
    page,
    truth: dict,
    strokes: list[list[tuple[float, float]]],
    *,
    out_dir: Path | None = None,
    mid_label: str | None = None,
) -> None:
    box = page.locator("#art-canvas").bounding_box()
    if not box:
        raise AssertionError("robot art canvas is not visible")
    canvas = truth["canvas"]
    width, height = int(canvas["width"]), int(canvas["height"])
    midpoint = max(0, len(strokes) // 2)
    for stroke_index, normalized in enumerate(strokes):
        points = _resample(normalized, width, height)
        if len(points) < 5:
            raise AssertionError(f"stroke {stroke_index + 1} could not be sampled densely")
        page.mouse.move(*_canvas_to_screen(box, canvas, points[0]))
        page.mouse.down()
        for point_index, point in enumerate(points[1:], start=1):
            page.mouse.move(*_canvas_to_screen(box, canvas, point), steps=1)
            page.wait_for_timeout(7)
            if out_dir is not None and mid_label and stroke_index == midpoint and point_index == max(1, len(points) // 2):
                _screenshot(page, out_dir, MECHANIC_ID, mid_label)
        page.mouse.up()
        page.wait_for_timeout(12)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])

    # A blank review is a real recognizer rejection, not a frontend-only warning.
    page.locator("#ask-critic").click()
    expect(page.locator("#critic-response[data-status='rejected']")).to_be_visible()
    expect(page.locator("#critic-response")).to_contain_text("NO COMMITTED FORM")
    expect(page.locator(".readout")).to_contain_text("REVISE")
    _screenshot(page, out_dir, mechanic, "real-blank-critique")

    truth = _read_json(state_dir / "ground_truth.json")
    target_class = str(truth["target"]["class_name"])
    wrong_class = {
        "umbrella": "fish", "sailboat": "fish", "fish": "flower",
        "flower": "fish", "ladder": "umbrella", "bicycle": "lighthouse",
        "lighthouse": "bicycle", "locomotive": "bicycle",
    }[target_class]
    _draw_strokes(page, truth, _transformed_sketch(wrong_class, truth))
    page.locator("#ask-critic").click()
    expect(page.locator("#critic-response[data-status='rejected']")).to_be_visible()
    _screenshot(page, out_dir, mechanic, "wrong-silhouette-critique")
    page.locator("#clear-art").click()
    stray = [[(.43, .46), (.48, .52), (.53, .48), (.57, .54)]]
    _draw_strokes(page, truth, stray)
    page.locator("#undo-stroke").click()
    expect(page.locator(".readout")).to_contain_text("UNDONE")

    page.locator("#abandon-art").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".art-verdict-fail")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    target_class = str(truth["target"]["class_name"])

    page.wait_for_timeout(1_300)
    expect(page.locator(".art-verdict-fresh")).to_have_count(0)

    _draw_strokes(
        page,
        truth,
        _humanized(_transformed_sketch(target_class, truth)),
        out_dir=out_dir,
        mid_label="active-continuous-drawing",
    )
    physical = page.evaluate("""() => ({
      strokes: window.robotArtCriticModel.strokes.length,
      allDense: window.robotArtCriticModel.strokes.every(stroke => stroke.dense),
      moves: window.robotArtCriticModel.events.filter(event => event.kind === 'stroke_move').length,
      reviews: window.robotArtCriticModel.attempts.length,
      clears: window.robotArtCriticModel.clearCount,
      undos: window.robotArtCriticModel.undoCount,
    })""")
    expected_strokes = int(truth["target"]["expected_strokes"])
    if physical["strokes"] != expected_strokes or not physical["allDense"] or physical["moves"] < expected_strokes * 4 or physical["reviews"] != 0 or physical["clears"] != 0 or physical["undos"] != 0:
        raise AssertionError(f"art studio clean humanized drawing contract failed: {physical}")
    _screenshot(page, out_dir, mechanic, "accepted-drawing-before-review")

    page.locator("#ask-critic").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=10_000)
    expect(page.locator(".readout")).to_have_attribute("data-status", "passed")
    expect(page.locator(".art-verdict-pass")).to_be_visible()
