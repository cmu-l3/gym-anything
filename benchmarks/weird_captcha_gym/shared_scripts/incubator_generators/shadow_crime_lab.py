from __future__ import annotations

import hashlib
import itertools
import math
import random
from typing import Any


MECHANIC_ID = "shadow_crime_lab"
CANVAS_WIDTH = 900
CANVAS_HEIGHT = 480
VARIANT_COUNT = 5 * 3 * 10_000_000_000
SHAPES = ("cylinder", "crate", "prism", "bust", "obelisk")
PALETTES = ("noir-sodium", "cold-case", "red-room")
ANCHORS = ((450, 92), (690, 178), (606, 360), (294, 360), (210, 178))
ZONE_ANCHORS = ((112, 82), (788, 82), (788, 398), (112, 398))


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _point(x: float, y: float) -> dict[str, float]:
    return {"x": round(x, 2), "y": round(y, 2)}


def _forge_contract(challenge_id: str, objects: list[dict[str, Any]]) -> dict[str, Any]:
    forge_index = int(challenge_id[0:2], 16) % len(objects)
    law_index = int(challenge_id[2:4], 16) % 3
    parameter_byte = int(challenge_id[4:6], 16)
    if law_index == 0:
        sign = -1 if parameter_byte % 2 else 1
        return {"object_id": objects[forge_index]["id"], "law": "wrong_pivot", "parameter": sign * (0.38 + (parameter_byte % 11) / 100)}
    if law_index == 1:
        scale = 0.54 + (parameter_byte % 8) / 100 if parameter_byte % 2 else 1.38 + (parameter_byte % 8) / 100
        return {"object_id": objects[forge_index]["id"], "law": "wrong_scale", "parameter": round(scale, 2)}
    return {"object_id": objects[forge_index]["id"], "law": "lagged", "parameter": round(0.24 + (parameter_byte % 9) / 100, 2)}


def _effective_lamp(raw: tuple[float, float], initial: tuple[float, float], contract: dict[str, Any]) -> tuple[float, float]:
    dx, dy = raw[0] - initial[0], raw[1] - initial[1]
    parameter = float(contract["parameter"])
    if contract["law"] == "wrong_pivot":
        cosine, sine = math.cos(parameter), math.sin(parameter)
        return initial[0] + dx * cosine - dy * sine, initial[1] + dx * sine + dy * cosine
    if contract["law"] == "wrong_scale":
        return initial[0] + dx * parameter, initial[1] + dy * parameter
    return initial[0] + dx * parameter, initial[1] + dy * parameter


def _shadow_polygon(obj: dict[str, Any], lamp: tuple[float, float], area_radius: float) -> list[tuple[float, float]]:
    ox, oy = float(obj["x"]), float(obj["y"])
    dx, dy = ox - lamp[0], oy - lamp[1]
    distance = max(62.0, math.hypot(dx, dy))
    ux, uy = dx / distance, dy / distance
    px, py = -uy, ux
    radius, height = float(obj["radius"]), float(obj["height"])
    length = _clamp(height * 250.0 / distance, 48.0, 158.0)
    near_width = radius * (0.88 + area_radius / max(distance, 1.0) * 0.42)
    far_width = near_width * (1.0 + height / distance * 0.82) + area_radius * 0.10
    near_x, near_y = ox + ux * radius * 0.28, oy + uy * radius * 0.28
    far_x, far_y = ox + ux * (radius * 0.55 + length), oy + uy * (radius * 0.55 + length)
    return [
        (near_x - px * near_width, near_y - py * near_width),
        (near_x + px * near_width, near_y + py * near_width),
        (far_x + px * far_width, far_y + py * far_width),
        (far_x - px * far_width, far_y - py * far_width),
    ]


def _inside(x: float, y: float, polygon: list[tuple[float, float]]) -> bool:
    inside = False
    previous = len(polygon) - 1
    for index, (xi, yi) in enumerate(polygon):
        xj, yj = polygon[previous]
        if ((yi > y) != (yj > y)) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi:
            inside = not inside
        previous = index
    return inside


def _polygons(objects: list[dict[str, Any]], raw_lamp: tuple[float, float], initial_lamp: tuple[float, float], area_radius: float, contract: dict[str, Any]) -> list[tuple[str, list[tuple[float, float]]]]:
    forged_lamp = _effective_lamp(raw_lamp, initial_lamp, contract)
    return [
        (
            str(obj["id"]),
            _shadow_polygon(obj, forged_lamp if obj["id"] == contract["object_id"] else raw_lamp, area_radius),
        )
        for obj in objects
    ]


def _raycast(polygons: list[tuple[str, list[tuple[float, float]]]], x: float, y: float) -> str | None:
    for object_id, polygon in reversed(polygons):
        if _inside(x, y, polygon):
            return object_id
    return None


def _tag_point(polygons: list[tuple[str, list[tuple[float, float]]]], forged_id: str) -> tuple[float, float] | None:
    forged_polygon = next(polygon for object_id, polygon in polygons if object_id == forged_id)
    centroid = (
        sum(point[0] for point in forged_polygon) / len(forged_polygon),
        sum(point[1] for point in forged_polygon) / len(forged_polygon),
    )
    candidates = [centroid]
    for first, second in ((0, 3), (1, 2), (2, 3)):
        candidates.append(((forged_polygon[first][0] + forged_polygon[second][0] + centroid[0]) / 3, (forged_polygon[first][1] + forged_polygon[second][1] + centroid[1]) / 3))
    minimum_x, maximum_x = min(point[0] for point in forged_polygon), max(point[0] for point in forged_polygon)
    minimum_y, maximum_y = min(point[1] for point in forged_polygon), max(point[1] for point in forged_polygon)
    for row in range(1, 6):
        for column in range(1, 6):
            candidates.append((minimum_x + (maximum_x - minimum_x) * column / 6, minimum_y + (maximum_y - minimum_y) * row / 6))
    for x, y in candidates:
        if 14 <= x <= CANVAS_WIDTH - 14 and 14 <= y <= CANVAS_HEIGHT - 14 and _inside(x, y, forged_polygon) and _raycast(polygons, x, y) == forged_id:
            return round(x, 2), round(y, 2)
    return None


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "shadow_crime_lab_seed_0001@0.1")
    shapes = list(SHAPES)
    rng.shuffle(shapes)
    objects = []
    for index, ((anchor_x, anchor_y), shape) in enumerate(zip(ANCHORS, shapes), start=1):
        token = hashlib.sha256(f"{seed}|shadow-object|{index}".encode("utf-8")).hexdigest()[:5]
        objects.append({
            "id": f"evidence-{token}",
            "case_label": f"E-{index:02d}",
            "shape": shape,
            "x": anchor_x + rng.randint(-18, 18),
            "y": anchor_y + rng.randint(-14, 14),
            "radius": rng.randint(18, 26),
            "height": rng.randint(48, 82),
            "tone": rng.choice(("oxide", "slate", "bone", "brass", "umber")),
        })
    lamp_initial = (450 + rng.randint(-15, 15), 238 + rng.randint(-12, 12))
    lamp_type = rng.choice(("point", "area"))
    area_radius = 0.0 if lamp_type == "point" else float(rng.randint(14, 22))
    probe_zones = [
        {"id": f"P{index + 1}", "x": x + rng.randint(-10, 10), "y": y + rng.randint(-9, 9), "radius": 42}
        for index, (x, y) in enumerate(ZONE_ANCHORS)
    ]
    contract = _forge_contract(challenge_id, objects)

    solution = None
    zone_permutations = list(itertools.permutations(probe_zones))
    rng.shuffle(zone_permutations)
    for ordering in zone_permutations:
        final_lamp = (float(ordering[-1]["x"]), float(ordering[-1]["y"]))
        polygons = _polygons(objects, final_lamp, lamp_initial, area_radius, contract)
        click = _tag_point(polygons, str(contract["object_id"]))
        if click is None:
            continue
        solution = {
            "probe_path": [{"zone_id": zone["id"], "x": zone["x"], "y": zone["y"]} for zone in ordering],
            "expected_tag_point": _point(*click),
        }
        break
    if solution is None:
        raise RuntimeError("could not find an unobstructed forged-shadow tag point")

    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": task.get("natural_language") or "Move the light through all probe zones. Tag the shadow that cannot be physically true.",
        "generator": {"name": "analytic_shadow_crime_lab_v1", "variant_count": VARIANT_COUNT},
        "case_number": f"SC-{challenge_id[:4].upper()}-{rng.randint(100, 999)}",
        "palette": rng.choice(PALETTES),
        "canvas": {"width": CANVAS_WIDTH, "height": CANVAS_HEIGHT},
        "objects": objects,
        "lamp": {"type": lamp_type, "x": lamp_initial[0], "y": lamp_initial[1], "area_radius": area_radius, "drag_radius": 34},
        "probe_zones": probe_zones,
        "minimum_probe_zones": 4,
        "minimum_travel": 1_050,
        "submit_label": "FILE FINDING",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "canvas": public_state["canvas"],
        "objects": objects,
        "lamp": public_state["lamp"],
        "probe_zones": probe_zones,
        "minimum_probe_zones": 4,
        "minimum_travel": 1_050,
        "forged_object_id": contract["object_id"],
        "forged_law": contract["law"],
        "forged_parameter": contract["parameter"],
        "solution": solution,
        "variant_count": VARIANT_COUNT,
    }
    initial_polygons = _polygons(objects, lamp_initial, lamp_initial, area_radius, contract)
    honest_initial = [_shadow_polygon(obj, lamp_initial, area_radius) for obj in objects]
    assert all(
        all(abs(first[axis] - second[axis]) < 1e-9 for first, second in zip(polygon, honest) for axis in (0, 1))
        for (_, polygon), honest in zip(initial_polygons, honest_initial)
    )
    return public_state, ground_truth
