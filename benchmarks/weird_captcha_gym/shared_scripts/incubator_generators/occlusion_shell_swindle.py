from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "occlusion_shell_swindle"
STAGE_WIDTH = 1000
STAGE_HEIGHT = 420
TICK_MS = 120
PREVIEW_MS = 900
SHELL_RADIUS = 27


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _smoothstep(value: float) -> float:
    return value * value * (3 - 2 * value)


def _interpolate(first: tuple[float, float], second: tuple[float, float], amount: float) -> tuple[float, float]:
    eased = _smoothstep(amount)
    return first[0] + (second[0] - first[0]) * eased, first[1] + (second[1] - first[1]) * eased


def _circle_inside(point: list[int], rect: dict[str, int], radius: int = SHELL_RADIUS) -> bool:
    return (
        point[0] - radius >= rect["x"]
        and point[0] + radius <= rect["x"] + rect["width"]
        and point[1] - radius >= rect["y"]
        and point[1] + radius <= rect["y"] + rect["height"]
    )


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    shell_count = rng.choice((4, 5))
    shell_ids = [f"shell-{chr(65 + index)}" for index in range(shell_count)]
    transfer_rounds = set(rng.sample(range(3), rng.choice((1, 2))))
    rounds_public: list[dict[str, Any]] = []
    rounds_truth: list[dict[str, Any]] = []

    for round_index in range(3):
        frame_count = rng.randint(60, 68)
        start_x = [round(105 + index * 790 / (shell_count - 1)) for index in range(shell_count)]
        endpoint_order = list(range(shell_count))
        while endpoint_order == list(range(shell_count)) or sum(a != b for a, b in zip(endpoint_order, range(shell_count))) < 3:
            rng.shuffle(endpoint_order)
        end_x_by_shell = {shell_ids[shell_index]: start_x[endpoint_order[shell_index]] for shell_index in range(shell_count)}
        initial_carrier = rng.choice(shell_ids)
        inspection_partner = rng.choice([shell_id for shell_id in shell_ids if shell_id != initial_carrier])
        transfers = round_index in transfer_rounds

        lane_order = list(range(shell_count))
        rng.shuffle(lane_order)
        midpoints: dict[str, tuple[float, float]] = {}
        for shell_index, shell_id in enumerate(shell_ids):
            lane = lane_order[shell_index]
            midpoints[shell_id] = (
                330 + lane * 340 / max(1, shell_count - 1),
                112 + ((lane + round_index) % 3) * 56 + rng.randint(-10, 10),
            )
        center_x = rng.randint(430, 570)
        center_y = rng.randint(142, 214)
        midpoints[initial_carrier] = (center_x - 34, center_y)
        midpoints[inspection_partner] = (center_x + 34, center_y + rng.randint(-5, 5))
        wobble_signs = {shell_id: rng.choice((-1, 1)) for shell_id in shell_ids}

        frames: list[dict[str, Any]] = []
        for tick in range(1, frame_count + 1):
            t = tick / frame_count
            shells = []
            for shell_index, shell_id in enumerate(shell_ids):
                start = (start_x[shell_index], 338.0)
                midpoint = midpoints[shell_id]
                end = (end_x_by_shell[shell_id], 338.0)
                if t <= 0.5:
                    x, y = _interpolate(start, midpoint, t * 2)
                else:
                    x, y = _interpolate(midpoint, end, (t - 0.5) * 2)
                y += math.sin(math.pi * t) * wobble_signs[shell_id] * (5 + shell_index % 3)
                shells.append({
                    "id": shell_id,
                    "x": round(x),
                    "y": round(y),
                    "angle": round(math.sin(t * math.pi * 4 + shell_index) * 8),
                })
            frames.append({"tick": tick, "shells": shells})

        handoff = None
        occluders: list[dict[str, Any]] = []
        handoff_tick = frame_count // 2
        window_start, window_end = handoff_tick - 3, handoff_tick + 3
        hidden_points = []
        for tick in range(window_start, window_end + 1):
            frame_shells = {item["id"]: item for item in frames[tick - 1]["shells"]}
            hidden_points.extend([
                [frame_shells[initial_carrier]["x"], frame_shells[initial_carrier]["y"]],
                [frame_shells[inspection_partner]["x"], frame_shells[inspection_partner]["y"]],
            ])
        min_x = min(point[0] for point in hidden_points) - SHELL_RADIUS - 9
        max_x = max(point[0] for point in hidden_points) + SHELL_RADIUS + 9
        min_y = min(point[1] for point in hidden_points) - SHELL_RADIUS - 9
        max_y = max(point[1] for point in hidden_points) + SHELL_RADIUS + 9
        rect = {
            "id": f"curtain-{round_index + 1}-handoff",
            "x": max(18, min_x),
            "y": max(48, min_y),
            "width": min(STAGE_WIDTH - 36, max_x) - max(18, min_x),
            "height": min(292, max_y) - max(48, min_y),
            "style": rng.choice(("velvet", "mirror", "ledger")),
        }
        occluders.append(rect)
        actual_target = inspection_partner if transfers else initial_carrier
        handoff = {
            "tick": handoff_tick,
            "window_start": window_start,
            "window_end": window_end,
            "from_shell": initial_carrier,
            "partner_shell": inspection_partner,
            "to_shell": actual_target,
            "transfers": transfers,
            "occluder_id": rect["id"],
        }
        assert all(_circle_inside(point, rect) for point in hidden_points)

        cover_tick = round(frame_count * rng.choice((0.31, 0.67)))
        cover_shell = rng.choice(shell_ids)
        cover_position = next(item for item in frames[cover_tick - 1]["shells"] if item["id"] == cover_shell)
        cover_width, cover_height = rng.randint(116, 148), rng.randint(90, 116)
        occluders.append({
            "id": f"curtain-{round_index + 1}-decoy",
            "x": max(22, min(STAGE_WIDTH - cover_width - 22, cover_position["x"] - cover_width // 2)),
            "y": max(50, min(278 - cover_height, cover_position["y"] - cover_height // 2)),
            "width": cover_width,
            "height": cover_height,
            "style": rng.choice(("velvet", "mirror", "ledger")),
        })
        if len(occluders) == 1:
            occluders.append({
                "id": f"curtain-{round_index + 1}-cross",
                "x": rng.randint(390, 570),
                "y": rng.randint(72, 152),
                "width": rng.randint(118, 154),
                "height": rng.randint(92, 124),
                "style": rng.choice(("velvet", "mirror", "ledger")),
            })

        final_carrier = actual_target
        inspection = {
            "occluder_id": rect["id"],
            "window_start": window_start,
            "window_end": window_end,
            "port": [round(rect["x"] + rect["width"] / 2), round(rect["y"] + min(24, rect["height"] / 3))],
            "radius": 46,
            "from_shell": initial_carrier,
            "partner_shell": inspection_partner,
            "to_shell": actual_target,
            "minimum_samples": 3,
        }
        public_round = {
            "index": round_index,
            "label": f"TRACKING ROUND {round_index + 1} / 3",
            "preview_ms": PREVIEW_MS,
            "tick_ms": TICK_MS,
            "frame_count": frame_count,
            "duration_ms": frame_count * TICK_MS,
            "shell_ids": shell_ids,
            "initial_carrier": initial_carrier,
            "start_positions": [{"id": shell_ids[index], "x": start_x[index], "y": 338} for index in range(shell_count)],
            "frames": frames,
            "occluders": occluders,
            "inspection": inspection,
        }
        rounds_public.append(public_round)
        rounds_truth.append({
            **public_round,
            "handoff": handoff,
            "final_carrier": final_carrier,
        })

    task_id = str(task.get("id") or "occlusion_shell_swindle_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": "Track the marked token. When paired shells enter a cover, hold the cursor over its peephole and read the physical shuttle.",
        "submit_label": "CERTIFY THREE TRACKS",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "observable_inspection_port_shells_v2", "variant_count": 7_900_000_000},
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "shell_radius": SHELL_RADIUS,
        "rounds": rounds_public,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "stage": public_state["stage"],
        "shell_radius": SHELL_RADIUS,
        "rounds": rounds_truth,
        "transfer_rounds": sorted(transfer_rounds),
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert len(rounds_public) == 3 and 1 <= len(transfer_rounds) <= 2
    return public_state, ground_truth
