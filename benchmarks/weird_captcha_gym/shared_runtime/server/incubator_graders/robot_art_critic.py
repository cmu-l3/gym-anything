from __future__ import annotations

import copy
import hashlib
import math
from typing import Any


MECHANIC_ID = "robot_art_critic"
GRID = 24
CLASSES = ("umbrella", "sailboat", "fish", "flower", "ladder", "bicycle", "lighthouse", "locomotive")


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": feedback}


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _point(value: Any, width: int, height: int, label: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} point is malformed")
    x = _integer(value[0], f"{label} x")
    y = _integer(value[1], f"{label} y")
    if not 0 <= x <= width or not 0 <= y <= height:
        raise ValueError(f"{label} point leaves the studio canvas")
    return x, y


def _distance(first: tuple[float, float], second: tuple[float, float]) -> float:
    return math.hypot(second[0] - first[0], second[1] - first[1])


def _ellipse(cx: float, cy: float, rx: float, ry: float, count: int = 30) -> list[tuple[float, float]]:
    return [(cx + rx * math.cos(index * math.tau / count), cy + ry * math.sin(index * math.tau / count)) for index in range(count)] + [(cx + rx, cy)]


def _templates() -> dict[str, list[list[tuple[float, float]]]]:
    canopy = [
        (.14, .51), (.17, .41), (.23, .31), (.32, .23), (.42, .19), (.50, .18), (.58, .19), (.68, .23), (.77, .31), (.83, .41), (.86, .51),
        (.78, .47), (.70, .53), (.62, .47), (.54, .53), (.46, .47), (.38, .53), (.30, .47), (.22, .53), (.14, .51),
    ]
    umbrella = [
        canopy, [(.50, .50), (.50, .62), (.50, .74), (.51, .84), (.56, .90), (.63, .89), (.67, .84)],
        [(.50, .19), (.22, .52)], [(.50, .19), (.38, .52)], [(.50, .19), (.62, .52)], [(.50, .19), (.78, .52)],
        [(.50, .18), (.50, .10)], [(.23, .63), (.18, .74)], [(.39, .69), (.34, .80)], [(.77, .63), (.72, .74)],
    ]
    sailboat = [
        [(.17, .73), (.83, .73), (.70, .86), (.31, .86), (.17, .73)],
        [(.50, .72), (.50, .18)],
        [(.47, .23), (.25, .66), (.47, .66), (.47, .23)],
        [(.53, .29), (.77, .66), (.53, .66), (.53, .29)],
        [(.31, .69), (.69, .69)], [(.50, .20), (.20, .72)], [(.50, .20), (.82, .72)],
        [(.50, .18), (.65, .23), (.50, .29), (.50, .18)],
        [(.12, .88), (.34, .86), (.55, .89), (.78, .86), (.91, .88)],
        [(.16, .93), (.37, .91), (.60, .94), (.84, .91)], [(.23, .79), (.41, .77), (.59, .79), (.76, .77)],
    ]
    fish = [
        _ellipse(.46, .52, .29, .20, 34),
        [(.75, .52), (.91, .33), (.91, .71), (.75, .52)],
        _ellipse(.35, .47, .035, .035, 10),
        [(.18, .53), (.13, .56)], [(.48, .32), (.58, .18), (.66, .38)], [(.47, .71), (.58, .84), (.64, .67)],
        [(.27, .38), (.32, .52), (.27, .64)], [(.43, .46), (.48, .50), (.43, .54)],
        [(.54, .43), (.59, .48), (.54, .53)], [(.62, .48), (.67, .52), (.62, .56)],
    ]
    flower_loop = []
    for index in range(71):
        angle = index * math.tau / 70
        radius = .18 + .075 * math.cos(5 * angle)
        flower_loop.append((.50 + radius * math.cos(angle), .39 + radius * math.sin(angle)))
    flower = [
        flower_loop,
        [(.50, .56), (.50, .66), (.50, .77), (.50, .89)],
        [(.50, .72), (.62, .65), (.70, .69), (.61, .78), (.50, .72)],
        [(.50, .78), (.39, .70), (.31, .74), (.39, .82), (.50, .78)],
        _ellipse(.50, .39, .055, .055, 14),
        [(.50, .39), (.50, .18)], [(.50, .39), (.68, .27)], [(.50, .39), (.72, .47)],
        [(.50, .39), (.57, .61)], [(.50, .39), (.31, .28)], [(.26, .90), (.74, .90)],
    ]
    ladder = [
        [(.31, .14), (.31, .88)], [(.69, .14), (.69, .88)],
        [(.31, .22), (.69, .22)], [(.31, .34), (.69, .34)], [(.31, .46), (.69, .46)],
        [(.31, .58), (.69, .58)], [(.31, .70), (.69, .70)], [(.31, .82), (.69, .82)],
        [(.26, .91), (.34, .86)], [(.74, .91), (.66, .86)], [(.27, .14), (.73, .14)],
    ]
    bicycle = [
        _ellipse(.27, .68, .18, .18, 28), _ellipse(.73, .68, .18, .18, 28),
        [(.27, .68), (.43, .43), (.55, .68), (.27, .68), (.48, .68), (.64, .43), (.43, .43)],
        [(.64, .43), (.73, .68)], [(.62, .39), (.70, .36)], [(.39, .40), (.49, .40)],
        _ellipse(.48, .68, .045, .045, 14), [(.43, .68), (.54, .68)], [(.27, .68), (.48, .68)],
        [(.20, .45), (.38, .45), (.43, .43)], [(.72, .61), (.77, .58)],
    ]
    lighthouse = [
        [(.34, .84), (.40, .35), (.60, .35), (.66, .84), (.34, .84)],
        [(.36, .28), (.50, .15), (.64, .28), (.36, .28)], [(.40, .28), (.60, .28), (.60, .40), (.40, .40), (.40, .28)],
        [(.46, .84), (.46, .70), (.54, .70), (.54, .84)], [(.38, .48), (.62, .48)], [(.37, .58), (.63, .58)],
        [(.36, .68), (.64, .68)], [(.40, .32), (.12, .23)], [(.60, .32), (.88, .23)],
        [(.20, .86), (.34, .81), (.43, .86)], [(.57, .86), (.68, .81), (.82, .86)], [(.12, .88), (.88, .88)],
    ]
    locomotive = [
        [(.20, .42), (.69, .42), (.78, .58), (.78, .72), (.20, .72), (.20, .42)],
        [(.18, .31), (.38, .31), (.38, .61), (.18, .61), (.18, .31)], _ellipse(.55, .52, .20, .12, 24),
        [(.57, .40), (.57, .24), (.66, .24), (.69, .40)], [(.78, .60), (.91, .70), (.78, .70)],
        _ellipse(.29, .75, .09, .09, 20), _ellipse(.51, .75, .09, .09, 20), _ellipse(.72, .75, .09, .09, 20),
        [(.29, .75), (.72, .75)], [(.10, .84), (.90, .84)], [(.13, .89), (.87, .89)],
        _ellipse(.63, .16, .055, .045, 14), _ellipse(.73, .10, .07, .05, 14), [(.75, .49), (.83, .49)],
    ]
    return {"umbrella": umbrella, "sailboat": sailboat, "fish": fish, "flower": flower, "ladder": ladder, "bicycle": bicycle, "lighthouse": lighthouse, "locomotive": locomotive}


TEMPLATES = _templates()


def _transform_template(class_name: str, angle_deg: float, x_scale_milli: int) -> list[list[tuple[float, float]]]:
    angle = math.radians(angle_deg)
    cosine, sine = math.cos(angle), math.sin(angle)
    x_scale = x_scale_milli / 1000
    output: list[list[tuple[float, float]]] = []
    for stroke in TEMPLATES[class_name]:
        transformed = []
        for x, y in stroke:
            dx, dy = (x - .5) * x_scale, y - .5
            transformed.append((.5 + dx * cosine - dy * sine, .5 + dx * sine + dy * cosine))
        output.append(transformed)
    return output


def _normalize(strokes: list[list[tuple[float, float]]]) -> tuple[list[list[tuple[float, float]]], dict[str, float]]:
    points = [point for stroke in strokes for point in stroke]
    if not points:
        return [], {"width": 0, "height": 0, "center_x": .5, "center_y": .5, "max_dim": 0}
    minimum_x = min(point[0] for point in points)
    maximum_x = max(point[0] for point in points)
    minimum_y = min(point[1] for point in points)
    maximum_y = max(point[1] for point in points)
    width, height = maximum_x - minimum_x, maximum_y - minimum_y
    maximum_dimension = max(width, height, 1e-9)
    center_x, center_y = (minimum_x + maximum_x) / 2, (minimum_y + maximum_y) / 2
    normalized = [[(.5 + (x - center_x) / maximum_dimension * .82, .5 + (y - center_y) / maximum_dimension * .82) for x, y in stroke] for stroke in strokes]
    return normalized, {"width": width, "height": height, "center_x": center_x, "center_y": center_y, "max_dim": maximum_dimension}


def _rasterize(strokes: list[list[tuple[float, float]]]) -> list[int]:
    raster = [0] * (GRID * GRID)

    def mark(x: float, y: float) -> None:
        column = max(0, min(GRID - 1, round(x * (GRID - 1))))
        row = max(0, min(GRID - 1, round(y * (GRID - 1))))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                cx, cy = column + dx, row + dy
                if 0 <= cx < GRID and 0 <= cy < GRID:
                    raster[cy * GRID + cx] = 1

    for stroke in strokes:
        for first, second in zip(stroke, stroke[1:]):
            length = _distance(first, second)
            steps = max(1, math.ceil(length * GRID * 2.5))
            for index in range(steps + 1):
                amount = index / steps
                mark(first[0] + (second[0] - first[0]) * amount, first[1] + (second[1] - first[1]) * amount)
    return raster


def _segment_intersection(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]) -> bool:
    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return o1 * o2 < -1e-8 and o3 * o4 < -1e-8


def _extract_features(strokes: list[list[tuple[float, float]]]) -> dict[str, Any]:
    normalized, bounds = _normalize(strokes)
    raster = _rasterize(normalized)
    occupied = [index for index, value in enumerate(raster) if value]
    coarse: list[float] = []
    for block_y in range(6):
        for block_x in range(6):
            cells = []
            for row in range(block_y * 4, block_y * 4 + 4):
                for column in range(block_x * 4, block_x * 4 + 4):
                    cells.append(raster[row * GRID + column])
            coarse.append(sum(cells) / 16)
    direction = [0.0] * 8
    total_length = 0.0
    turns = 0
    turn_denominator = 0
    closed = 0
    segments: list[tuple[int, int, tuple[float, float], tuple[float, float]]] = []
    endpoints: list[tuple[float, float]] = []
    for stroke_index, stroke in enumerate(normalized):
        if not stroke:
            continue
        endpoints.extend((stroke[0], stroke[-1]))
        length = sum(_distance(first, second) for first, second in zip(stroke, stroke[1:]))
        total_length += length
        if len(stroke) >= 3 and _distance(stroke[0], stroke[-1]) <= .055:
            closed += 1
        for segment_index, (first, second) in enumerate(zip(stroke, stroke[1:])):
            segment_length = _distance(first, second)
            if segment_length <= 1e-9:
                continue
            angle = math.atan2(second[1] - first[1], second[0] - first[0]) % math.pi
            bucket = min(7, int(angle / math.pi * 8))
            direction[bucket] += segment_length
            segments.append((stroke_index, segment_index, first, second))
        for first, middle, last in zip(stroke, stroke[1:], stroke[2:]):
            first_angle = math.atan2(middle[1] - first[1], middle[0] - first[0])
            second_angle = math.atan2(last[1] - middle[1], last[0] - middle[0])
            delta = abs((second_angle - first_angle + math.pi) % (2 * math.pi) - math.pi)
            if _distance(first, middle) > .005 and _distance(middle, last) > .005:
                turn_denominator += 1
                if delta > math.radians(38):
                    turns += 1
    if total_length:
        direction = [value / total_length for value in direction]
    endpoint_grid = [0.0] * 16
    for x, y in endpoints:
        endpoint_grid[min(3, int(y * 4)) * 4 + min(3, int(x * 4))] += 1
    if endpoints:
        endpoint_grid = [value / len(endpoints) for value in endpoint_grid]
    intersections = 0
    for first_index, first in enumerate(segments):
        for second in segments[first_index + 1 :]:
            if first[0] == second[0] and abs(first[1] - second[1]) <= 1:
                continue
            if _segment_intersection(first[2], first[3], second[2], second[3]):
                intersections += 1
    vertical_diff = horizontal_diff = 0
    for row in range(GRID):
        for column in range(GRID):
            vertical_diff += abs(raster[row * GRID + column] - raster[row * GRID + (GRID - 1 - column)])
            horizontal_diff += abs(raster[row * GRID + column] - raster[(GRID - 1 - row) * GRID + column])
    symmetry = [1 - vertical_diff / (GRID * GRID), 1 - horizontal_diff / (GRID * GRID)]
    radial = [0.0] * 4
    for index in occupied:
        x = (index % GRID) / (GRID - 1)
        y = (index // GRID) / (GRID - 1)
        radius = min(.707, math.hypot(x - .5, y - .5))
        radial[min(3, int(radius / .708 * 4))] += 1
    if occupied:
        radial = [value / len(occupied) for value in radial]
    aspect = bounds["width"] / max(bounds["height"], 1e-9)
    return {
        "raster": raster,
        "coarse": coarse,
        "direction": direction,
        "endpoint_grid": endpoint_grid,
        "stroke_count": len(strokes),
        "closed_count": closed,
        "intersections": min(intersections, 12),
        "turn_rate": turns / max(1, turn_denominator),
        "aspect": aspect,
        "symmetry": symmetry,
        "radial": radial,
        "length": total_length,
        "density": len(occupied) / (GRID * GRID),
        "bounds": bounds,
    }


def _cosine(first: list[float], second: list[float]) -> float:
    numerator = sum(a * b for a, b in zip(first, second))
    denominator = math.sqrt(sum(value * value for value in first) * sum(value * value for value in second))
    return numerator / denominator if denominator > 1e-12 else 0.0


def _distribution_similarity(first: list[float], second: list[float]) -> float:
    return max(0.0, 1 - sum(abs(a - b) for a, b in zip(first, second)) / 2)


def _feature_score(features: dict[str, Any], prototype: dict[str, Any]) -> float:
    first_ink = sum(features["raster"])
    second_ink = sum(prototype["raster"])
    overlap = sum(a and b for a, b in zip(features["raster"], prototype["raster"]))
    dice = 2 * overlap / max(1, first_ink + second_ink)
    coarse = max(0.0, 1 - sum(abs(a - b) for a, b in zip(features["coarse"], prototype["coarse"])) / len(features["coarse"]) * 2.3)
    direction = _cosine(features["direction"], prototype["direction"])
    endpoints = _distribution_similarity(features["endpoint_grid"], prototype["endpoint_grid"])
    topology = (
        max(0.0, 1 - abs(features["stroke_count"] - prototype["stroke_count"]) / 5)
        + max(0.0, 1 - abs(features["closed_count"] - prototype["closed_count"]) / 3)
        + max(0.0, 1 - abs(features["intersections"] - prototype["intersections"]) / 5)
        + max(0.0, 1 - abs(features["turn_rate"] - prototype["turn_rate"]) * 2)
    ) / 4
    aspect = math.exp(-abs(math.log(max(features["aspect"], .05) / max(prototype["aspect"], .05))) * 1.1)
    symmetry = max(0.0, 1 - sum(abs(a - b) for a, b in zip(features["symmetry"], prototype["symmetry"])) / 2)
    radial = _distribution_similarity(features["radial"], prototype["radial"])
    length = math.exp(-abs(math.log(max(features["length"], .05) / max(prototype["length"], .05))) * .65)
    density = math.exp(-abs(math.log(max(features["density"], .01) / max(prototype["density"], .01))) * .65)
    return 100 * (
        .39 * dice + .10 * coarse + .12 * direction + .07 * endpoints + .12 * topology
        + .06 * aspect + .035 * symmetry + .045 * radial + .035 * length + .025 * density
    )


def _prototype_features(angle_deg: float, x_scale_milli: int) -> dict[str, dict[str, Any]]:
    return {class_name: _extract_features(_transform_template(class_name, angle_deg, x_scale_milli)) for class_name in CLASSES}


def _recognize(strokes: list[list[tuple[int, int]]], target: dict[str, Any], requirements: dict[str, int], width: int, height: int) -> dict[str, Any]:
    floating = [[(x / width, y / height) for x, y in stroke] for stroke in strokes]
    features = _extract_features(floating)
    prototypes = _prototype_features(float(target["pose"]["angle_deg"]), int(target["style"]["x_scale_milli"]))
    scores = {class_name: round(_feature_score(features, prototype), 3) for class_name, prototype in prototypes.items()}
    target_class = str(target["class_name"])
    target_score = scores[target_class]
    ordered = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    best_class, best_score = ordered[0]
    best_other = max(score for name, score in scores.items() if name != target_class)
    margin = target_score - best_other
    bounds = features["bounds"]
    max_fraction = max(bounds["width"], bounds["height"])
    center_offset = max(abs(bounds["center_x"] - .5), abs(bounds["center_y"] - .5))
    minimum_fraction = requirements["minimum_bbox_fraction_milli"] / 1000
    maximum_fraction = requirements["maximum_bbox_fraction_milli"] / 1000
    maximum_center = requirements["maximum_center_offset_milli"] / 1000
    composition_ok = minimum_fraction <= max_fraction <= maximum_fraction and center_offset <= maximum_center
    accepted = (
        bool(strokes)
        and len(strokes) <= requirements["stroke_budget"]
        and composition_ok
        and target_score >= requirements["acceptance_score_milli"] / 10
        and margin >= requirements["minimum_margin_milli"] / 10
        and best_class == target_class
    )
    if not strokes or max_fraction < .08:
        critique = "BLANK_OR_DOT"
    elif max_fraction < minimum_fraction:
        critique = "MAKE_LARGER"
    elif max_fraction > maximum_fraction:
        critique = "GIVE_IT_AIR"
    elif center_offset > maximum_center:
        critique = "CENTER_FORM"
    elif abs(features["stroke_count"] - int(target["expected_strokes"])) >= 2:
        critique = "CHECK_TOPOLOGY"
    elif best_class != target_class:
        critique = "WRONG_SILHOUETTE"
    elif margin < requirements["minimum_margin_milli"] / 10:
        critique = "SIMPLIFY_SILHOUETTE"
    elif target_score < requirements["acceptance_score_milli"] / 10:
        critique = "REFINE_DIRECTIONS"
    else:
        critique = "ACCEPTED"
    return {
        "scores": {name: round(score * 10) for name, score in scores.items()},
        "target_score_milli": round(target_score * 10),
        "best_class": best_class,
        "best_score_milli": round(best_score * 10),
        "margin_milli": round(margin * 10),
        "accepted": accepted,
        "critique": critique,
        "composition": {
            "bbox_fraction_milli": round(max_fraction * 1000),
            "center_offset_milli": round(center_offset * 1000),
            "stroke_count": len(strokes),
            "closed_count": features["closed_count"],
            "intersections": features["intersections"],
        },
    }


def _bind(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> str | None:
    for label, source in (("payload", payload), ("ground-truth", ground_truth), ("public-state", public_state)):
        if str(source.get("mechanic_id") or "") != MECHANIC_ID:
            return f"{label} mechanic mismatch"
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return "stale challenge"
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return "public-state challenge mismatch"
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return "payload task mismatch"
    if str(public_state.get("task_id") or "") != task_id:
        return "public-state task mismatch"
    return None


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> tuple[int, int, dict[str, Any], dict[str, int]]:
    for key in ("palette", "canvas", "target", "requirements"):
        if public_state.get(key) != ground_truth.get(key):
            raise ValueError(f"public {key} differs from hidden contract")
    public_vocab = [str(item).lower() for item in public_state.get("class_vocabulary") or []]
    hidden_vocab = [str(item) for item in ground_truth.get("class_vocabulary") or []]
    if public_vocab != hidden_vocab or tuple(hidden_vocab) != CLASSES:
        raise ValueError("class vocabulary differs from recognizer corpus")
    canvas = ground_truth.get("canvas")
    target = ground_truth.get("target")
    requirements = ground_truth.get("requirements")
    if not isinstance(canvas, dict) or not isinstance(target, dict) or not isinstance(requirements, dict):
        raise ValueError("canvas, target, or requirements are malformed")
    width = _integer(canvas.get("width"), "canvas width")
    height = _integer(canvas.get("height"), "canvas height")
    if target.get("class_name") not in CLASSES or int(target.get("expected_strokes", 0)) != len(TEMPLATES[str(target.get("class_name"))]):
        raise ValueError("target class topology is malformed")
    return width, height, target, {key: int(value) for key, value in requirements.items()}


def _summary(result: dict[str, Any], attempt_index: int) -> dict[str, Any]:
    return {
        "attempt_index": attempt_index,
        "scores": result["scores"],
        "target_score_milli": result["target_score_milli"],
        "best_class": result["best_class"],
        "best_score_milli": result["best_score_milli"],
        "margin_milli": result["margin_milli"],
        "accepted": result["accepted"],
        "critique": result["critique"],
        "composition": result["composition"],
    }


def _summary_matches(submitted: Any, expected: list[dict[str, Any]]) -> bool:
    if not isinstance(submitted, list) or len(submitted) != len(expected):
        return False
    for actual, wanted in zip(submitted, expected):
        if not isinstance(actual, dict):
            return False
        for key in ("attempt_index", "best_class", "accepted", "critique"):
            if actual.get(key) != wanted.get(key):
                return False
        for key in ("target_score_milli", "best_score_milli", "margin_milli"):
            if not isinstance(actual.get(key), int) or abs(actual[key] - wanted[key]) > 5:
                return False
        actual_scores = actual.get("scores")
        if not isinstance(actual_scores, dict) or set(actual_scores) != set(wanted["scores"]):
            return False
        if any(not isinstance(actual_scores[name], int) or abs(actual_scores[name] - wanted["scores"][name]) > 5 for name in wanted["scores"]):
            return False
        actual_composition = actual.get("composition")
        if not isinstance(actual_composition, dict) or set(actual_composition) != set(wanted["composition"]):
            return False
        if any(not isinstance(actual_composition[name], int) or abs(actual_composition[name] - wanted["composition"][name]) > 2 for name in wanted["composition"]):
            return False
    return True


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        width, height, target, requirements = _contract(ground_truth, public_state)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid art-recognizer contract: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 2500):
        return _fail("drawing transcript is missing or outside limits")

    strokes: list[dict[str, Any]] = []
    active: dict[str, Any] | None = None
    attempt_summaries: list[dict[str, Any]] = []
    undo_count = clear_count = 0
    accepted = abandoned = terminal = False
    last_clock = -1

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has an invalid sequence")
        if terminal:
            return _fail("transcript continues after terminal review")
        kind = str(event.get("kind") or "")
        if kind == "stroke_down":
            if active is not None or len(strokes) >= requirements["stroke_budget"]:
                return _fail(f"event {sequence} exceeds the continuous stroke budget")
            try:
                point = _point(event.get("point"), width, height, "stroke start")
                elapsed = _integer(event.get("elapsed_ms"), "stroke clock")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            expected_id = f"stroke-{len(strokes) + 1}"
            if event.get("stroke_id") != expected_id or elapsed < last_clock:
                return _fail(f"event {sequence} stroke identity or clock is inconsistent")
            active = {"id": expected_id, "points": [point], "times": [elapsed], "start": elapsed}
            last_clock = elapsed
            continue
        if kind == "stroke_move":
            if active is None or event.get("stroke_id") != active["id"]:
                return _fail(f"event {sequence} has no matching continuous pointer hold")
            try:
                point = _point(event.get("point"), width, height, "stroke sample")
                elapsed = _integer(event.get("elapsed_ms"), "stroke sample clock")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            gap = _distance(active["points"][-1], point)
            interval = elapsed - active["times"][-1]
            if elapsed < last_clock or interval < 0 or interval > requirements["maximum_sample_interval_ms"] or gap > requirements["maximum_sample_gap_px"]:
                return _fail(f"event {sequence} teleports, reverses time, or breaks continuity")
            if point != active["points"][-1]:
                active["points"].append(point)
                active["times"].append(elapsed)
            last_clock = elapsed
            continue
        if kind == "stroke_up":
            if active is None or event.get("stroke_id") != active["id"]:
                return _fail(f"event {sequence} releases a nonexistent stroke")
            try:
                point = _point(event.get("point"), width, height, "stroke release")
                elapsed = _integer(event.get("elapsed_ms"), "stroke release clock")
                duration = _integer(event.get("duration_ms"), "stroke duration")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if elapsed < last_clock or duration != elapsed - active["start"] or event.get("sample_count") != len(active["points"]):
                return _fail(f"event {sequence} stroke summary disagrees with replay")
            if _distance(active["points"][-1], point) > requirements["maximum_sample_gap_px"]:
                return _fail(f"event {sequence} teleports on pointer release")
            if point != active["points"][-1]:
                active["points"].append(point)
                active["times"].append(elapsed)
            active["dense"] = len(active["points"]) >= requirements["minimum_points_per_stroke"] and duration >= requirements["minimum_stroke_ms"]
            strokes.append(active)
            active = None
            last_clock = elapsed
            continue
        if kind == "undo":
            if active is not None or not strokes:
                return _fail(f"event {sequence} undo has no completed stroke")
            removed = strokes.pop()
            if event.get("removed_stroke_id") != removed["id"]:
                return _fail(f"event {sequence} undo identity disagrees with replay")
            undo_count += 1
            continue
        if kind == "clear":
            if active is not None or event.get("cleared_strokes") != len(strokes):
                return _fail(f"event {sequence} clear count disagrees with replay")
            strokes = []
            clear_count += 1
            continue
        if kind == "attempt":
            if active is not None or event.get("attempt_index") != len(attempt_summaries) + 1:
                return _fail(f"event {sequence} attempt order is inconsistent")
            if len(attempt_summaries) >= requirements["maximum_attempts"]:
                return _fail(f"event {sequence} exceeds the review-attempt budget")
            replay_strokes = [stroke["points"] for stroke in strokes]
            result = _recognize(replay_strokes, target, requirements, width, height)
            if any(not stroke.get("dense") for stroke in strokes):
                result = {**result, "accepted": False, "critique": "SPARSE_STROKE"}
            summary = _summary(result, len(attempt_summaries) + 1)
            attempt_summaries.append(summary)
            if summary["accepted"]:
                accepted = terminal = True
            elif len(attempt_summaries) == requirements["maximum_attempts"]:
                terminal = True
            continue
        if kind == "abandon":
            if active is not None or accepted:
                return _fail(f"event {sequence} cannot abandon this review state")
            abandoned = terminal = True
            continue
        return _fail(f"event {sequence} has unknown kind {kind!r}")

    expected_payload = {
        "attempt_count": len(attempt_summaries),
        "attempt_summaries": attempt_summaries,
        "accepted": accepted,
        "stroke_count": len(strokes),
        "undo_count": undo_count,
        "clear_count": clear_count,
        "abandoned": abandoned,
    }
    for field, expected in expected_payload.items():
        matches = _summary_matches(payload.get(field), expected) if field == "attempt_summaries" else payload.get(field) == expected
        if not matches:
            return _fail(f"submitted {field} does not match recognizer replay")
    passed = payload.get("completed") is True and accepted and terminal and not abandoned and bool(attempt_summaries)
    last = attempt_summaries[-1] if attempt_summaries else None
    target_score = last["target_score_milli"] / 10 if last else 0.0
    margin = last["margin_milli"] / 10 if last else 0.0
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"semantic replay: attempts {len(attempt_summaries)}/{requirements['maximum_attempts']}; strokes {len(strokes)}/{requirements['stroke_budget']}; "
            f"target score {target_score:.1f} margin {margin:.1f}; "
            f"best {last['best_class'] if last else 'none'}; critique {last['critique'] if last else 'none'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    target = ground_truth.get("target") or {}
    return {
        "target": target,
        "feature_contract": ["24x24 occupancy", "6x6 density", "8-bin undirected directions", "endpoint grid", "stroke/closure/intersection/turn topology", "aspect", "symmetry", "radial density", "normalized ink length"],
        "instruction": "Draw the named generic class with its described lean and width. Prototypes are semantic class exemplars, not challenge-specific coordinate paths.",
        "answers": [],
    }
