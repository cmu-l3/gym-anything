from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "ribbon_switchboard"
STAGE_WIDTH = 1000
STAGE_HEIGHT = 440
CONTROL_X = (70, 242, 414, 586, 758, 930)
SAMPLES_PER_SPAN = 18
COLORS = ("#ff5f6d", "#5fe0d0", "#ffd166", "#7e8cff", "#f39cde", "#93e85f")


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _transition(value: float, weight: float) -> float:
    if value <= 0:
        return 0.0
    if value >= 1:
        return 1.0
    first = value**1.7
    second = (1 - value) ** 1.7 * weight
    return first / (first + second)


def _crossings(ribbons: list[dict[str, Any]], rng: random.Random) -> list[dict[str, Any]]:
    crossings: list[dict[str, Any]] = []
    serial = 1
    for first_index, first in enumerate(ribbons):
        for second in ribbons[first_index + 1 :]:
            last_crossing = -10.0
            for index in range(len(first["points"]) - 1):
                first_delta = first["points"][index][1] - second["points"][index][1]
                second_delta = first["points"][index + 1][1] - second["points"][index + 1][1]
                if first_delta == 0:
                    fraction = 0.0
                elif first_delta * second_delta < 0:
                    fraction = abs(first_delta) / (abs(first_delta) + abs(second_delta))
                else:
                    continue
                parameter = index + fraction
                if parameter - last_crossing < 3.0:
                    continue
                x = round(first["points"][index][0] + (first["points"][index + 1][0] - first["points"][index][0]) * fraction)
                y = round(first["points"][index][1] + (first["points"][index + 1][1] - first["points"][index][1]) * fraction)
                over = rng.choice((first["id"], second["id"]))
                crossings.append({
                    "id": f"cross-{serial:02}",
                    "ribbons": [first["id"], second["id"]],
                    "over": over,
                    "under": second["id"] if over == first["id"] else first["id"],
                    "point": [x, y],
                    "parameters": {first["id"]: round(parameter, 4), second["id"]: round(parameter, 4)},
                })
                serial += 1
                last_crossing = parameter
    return crossings


def _max_close_run(ribbons: list[dict[str, Any]], threshold: int) -> int:
    maximum = 0
    for first_index, first in enumerate(ribbons):
        for second in ribbons[first_index + 1 :]:
            current = 0
            for first_point, second_point in zip(first["points"], second["points"]):
                if abs(first_point[1] - second_point[1]) < threshold:
                    current += 1
                    maximum = max(maximum, current)
                else:
                    current = 0
    return maximum


def _ambiguous_crossing(crossing: dict[str, Any], ribbons: list[dict[str, Any]], threshold: int = 16) -> bool:
    involved = set(crossing["ribbons"])
    parameter = next(iter(crossing["parameters"].values()))
    index = min(len(ribbons[0]["points"]) - 2, int(parameter))
    fraction = parameter - index
    y = crossing["point"][1]
    for ribbon in ribbons:
        if ribbon["id"] in involved:
            continue
        candidate = ribbon["points"][index][1] + (ribbon["points"][index + 1][1] - ribbon["points"][index][1]) * fraction
        if abs(candidate - y) < threshold:
            return True
    return False


def _make_layout(rng: random.Random, ribbon_count: int, target_id: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    ribbon_ids = [f"ribbon-{index + 1}" for index in range(ribbon_count)]
    slots = [round(67 + index * 306 / (ribbon_count - 1)) for index in range(ribbon_count)]
    for _attempt in range(500):
        orders: list[list[int]] = [list(range(ribbon_count))]
        rng.shuffle(orders[0])
        for column in range(1, len(CONTROL_X)):
            previous = orders[-1]
            candidate = previous[:]
            for _ in range(100):
                rng.shuffle(candidate)
                moved = sum(a != b for a, b in zip(previous, candidate))
                if moved >= max(3, ribbon_count - 1):
                    break
            orders.append(candidate[:])

        y_controls: dict[int, list[int]] = {index: [] for index in range(ribbon_count)}
        for order in orders:
            for slot_index, ribbon_index in enumerate(order):
                y_controls[ribbon_index].append(slots[slot_index] + rng.randint(-4, 4))
        weights = {
            ribbon_index: [rng.uniform(0.48, 1.9) for _ in range(len(CONTROL_X) - 1)]
            for ribbon_index in range(ribbon_count)
        }
        bows = {
            ribbon_index: [rng.randint(-11, 11) for _ in range(len(CONTROL_X) - 1)]
            for ribbon_index in range(ribbon_count)
        }
        ribbons: list[dict[str, Any]] = []
        for ribbon_index, ribbon_id in enumerate(ribbon_ids):
            points: list[list[int]] = []
            for span in range(len(CONTROL_X) - 1):
                for sample in range(SAMPLES_PER_SPAN):
                    t = sample / SAMPLES_PER_SPAN
                    amount = _transition(t, weights[ribbon_index][span])
                    x = CONTROL_X[span] + (CONTROL_X[span + 1] - CONTROL_X[span]) * t
                    y = y_controls[ribbon_index][span] + (y_controls[ribbon_index][span + 1] - y_controls[ribbon_index][span]) * amount
                    y += math.sin(math.pi * t) * bows[ribbon_index][span]
                    point = [round(x), round(y)]
                    if not points or points[-1] != point:
                        points.append(point)
            points.append([CONTROL_X[-1], y_controls[ribbon_index][-1]])
            ribbons.append({
                "id": ribbon_id,
                "label": f"BUS {chr(65 + ribbon_index)}",
                "color": COLORS[ribbon_index],
                "points": points,
                "source": points[0],
                "terminal": points[-1],
            })
        crossings = _crossings(ribbons, rng)
        target_crossings = []
        for crossing in crossings:
            if target_id in crossing["ribbons"]:
                target_crossings.append({
                    **crossing,
                    "target_parameter": crossing["parameters"][target_id],
                    "target_is_over": crossing["over"] == target_id,
                })
        target_crossings.sort(key=lambda item: item["target_parameter"])
        spacings = [b["target_parameter"] - a["target_parameter"] for a, b in zip(target_crossings, target_crossings[1:])]
        max_close = _max_close_run(ribbons, 18)
        if (
            len(crossings) >= max(8, ribbon_count + 4)
            and len(target_crossings) >= 5
            and (not spacings or min(spacings) >= 1.8)
            and max_close <= 9
            and not any(_ambiguous_crossing(item, ribbons) for item in target_crossings)
        ):
            audit = {
                "crossing_count": len(crossings),
                "target_crossing_count": len(target_crossings),
                "minimum_target_crossing_spacing": round(min(spacings) if spacings else len(ribbons[0]["points"]), 3),
                "maximum_close_run": max_close,
                "third_ribbon_clearance": 16,
            }
            return ribbons, crossings, audit
    raise RuntimeError("could not generate a distinguishable woven ribbon layout")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    ribbon_count = rng.randint(4, 6)
    target_id = f"ribbon-{rng.randrange(ribbon_count) + 1}"
    ribbons, crossings, clearance_audit = _make_layout(rng, ribbon_count, target_id)
    target = next(ribbon for ribbon in ribbons if ribbon["id"] == target_id)
    target_crossings = [
        {
            **crossing,
            "target_parameter": crossing["parameters"][target_id],
            "target_is_over": crossing["over"] == target_id,
        }
        for crossing in crossings
        if target_id in crossing["ribbons"]
    ]
    target_crossings.sort(key=lambda item: item["target_parameter"])
    hover_radius = rng.randint(58, 66)
    corridor_radius = rng.randint(18, 22)
    requirements = {
        "min_hover_samples": 26,
        "min_hover_cells": 14,
        "min_target_coverage": min(62, round(len(target["points"]) * 0.66)),
        "min_crossing_coverage": min(6, len(target_crossings)),
        "min_trace_samples": max(70, round(len(target["points"]) * 0.78)),
        "min_trace_ms": 560,
        "max_raw_step": 44,
        "max_parameter_jump": 4.5,
        "backtrack_tolerance": 1.5,
    }
    task_id = str(task.get("id") or "ribbon_switchboard_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Illuminate the weave locally. Carry the marked signal from its source to the true terminal without leaving the ribbon.",
        "submit_label": "CERTIFY ROUTED SIGNAL",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "analytic_woven_ribbon_field_v1", "variant_count": 9_400_000_000},
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "ribbons": ribbons,
        "crossings": crossings,
        "target_id": target_id,
        "target_color": target["color"],
        "source": target["source"],
        "terminals": [{"id": ribbon["id"], "label": ribbon["label"], "point": ribbon["terminal"], "color": ribbon["color"]} for ribbon in ribbons],
        "hover_radius": hover_radius,
        "corridor_radius": corridor_radius,
        "requirements": requirements,
        "clearance_audit": clearance_audit,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": public_state["stage"],
        "ribbons": ribbons,
        "crossings": crossings,
        "target_id": target_id,
        "target_path": target["points"],
        "target_terminal": target["terminal"],
        "target_crossings": target_crossings,
        "hover_radius": hover_radius,
        "corridor_radius": corridor_radius,
        "requirements": requirements,
        "clearance_audit": clearance_audit,
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert len(target_crossings) >= 5 and clearance_audit["maximum_close_run"] <= 9
    return public_state, ground_truth
