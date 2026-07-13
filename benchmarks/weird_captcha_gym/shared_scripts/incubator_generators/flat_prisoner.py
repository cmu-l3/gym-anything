from __future__ import annotations

import copy
import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "flat_prisoner"
VIEW_WIDTH = 900
VIEW_HEIGHT = 460
FOV_DEG = 52.0
NEAR = 0.1
FAR = 80.0
LAYOUTS = (
    ((58, 228, 352), (211, 369, 352), (394, 536, 310), (519, 687, 310), (715, 850, 269)),
    ((62, 234, 360), (216, 374, 360), (399, 542, 322), (524, 692, 322), (720, 852, 282)),
    ((55, 224, 346), (207, 365, 346), (390, 531, 302), (514, 680, 302), (708, 845, 258)),
    ((64, 238, 356), (220, 380, 356), (405, 548, 316), (530, 699, 316), (727, 858, 275)),
)
DEPTH_STACKS = (
    (6.6, 10.5, 8.1, 13.0, 7.4),
    (8.0, 12.8, 6.9, 10.1, 14.0),
    (11.6, 7.2, 13.4, 8.8, 6.4),
    (7.4, 13.6, 9.2, 6.5, 11.8),
)
PALETTES = (
    {"name": "cyanotype_cellblock", "sky": "#07141d", "haze": "#123244", "surface": "#243d4b", "edge": "#6ee8ff", "signal": "#f4c55a", "danger": "#f0645b"},
    {"name": "oxide_projection", "sky": "#19110f", "haze": "#402922", "surface": "#554035", "edge": "#76e3d5", "signal": "#ffb454", "danger": "#ec6256"},
    {"name": "violet_parallax", "sky": "#11101c", "haze": "#302b4a", "surface": "#413c5a", "edge": "#7be4ff", "signal": "#eebd69", "danger": "#ff6d78"},
    {"name": "lichen_panopticon", "sky": "#0c1511", "haze": "#263b31", "surface": "#405044", "edge": "#8de8c2", "signal": "#f4c861", "danger": "#ed6b55"},
)
YAW_VALUES = (-18.0, -6.0, 6.0, 18.0)
PITCH_VALUES = (-8.0, 0.0, 8.0)
DISTANCE_VALUES = (12.0, 13.0, 14.0)
VARIANT_COUNT = len(LAYOUTS) * 2 * len(DEPTH_STACKS) * len(PALETTES) * len(YAW_VALUES) * len(PITCH_VALUES) * len(DISTANCE_VALUES)


def _seed_int(seed: str, salt: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()[:8], "big")


def _dot(first: tuple[float, float, float], second: tuple[float, float, float]) -> float:
    return sum(a * b for a, b in zip(first, second))


def _cross(first: tuple[float, float, float], second: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        first[1] * second[2] - first[2] * second[1],
        first[2] * second[0] - first[0] * second[2],
        first[0] * second[1] - first[1] * second[0],
    )


def _normalize(vector: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(_dot(vector, vector))
    if length <= 1e-12:
        raise ValueError("zero camera basis vector")
    return tuple(value / length for value in vector)  # type: ignore[return-value]


def _add(first: tuple[float, float, float], second: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(a + b for a, b in zip(first, second))  # type: ignore[return-value]


def _scale(vector: tuple[float, float, float], amount: float) -> tuple[float, float, float]:
    return tuple(value * amount for value in vector)  # type: ignore[return-value]


def camera_basis(camera: dict[str, Any]) -> dict[str, tuple[float, float, float]]:
    yaw = math.radians(float(camera["yaw_deg"]))
    pitch = math.radians(float(camera["pitch_deg"]))
    distance = float(camera["distance"])
    target = tuple(float(value) for value in camera["target"])
    offset = (
        distance * math.cos(pitch) * math.sin(yaw),
        distance * math.sin(pitch),
        distance * math.cos(pitch) * math.cos(yaw),
    )
    eye = _add(target, offset)
    forward = _normalize(tuple(target[index] - eye[index] for index in range(3)))
    right = _normalize(_cross(forward, (0.0, 1.0, 0.0)))
    up = _normalize(_cross(right, forward))
    return {"eye": eye, "forward": forward, "right": right, "up": up}


def view_matrix(camera: dict[str, Any]) -> list[list[float]]:
    basis = camera_basis(camera)
    eye, forward, right, up = basis["eye"], basis["forward"], basis["right"], basis["up"]
    return [
        [right[0], right[1], right[2], -_dot(right, eye)],
        [up[0], up[1], up[2], -_dot(up, eye)],
        [-forward[0], -forward[1], -forward[2], _dot(forward, eye)],
        [0.0, 0.0, 0.0, 1.0],
    ]


def projection_matrix(viewport: dict[str, Any]) -> list[list[float]]:
    aspect = float(viewport["width"]) / float(viewport["height"])
    focal = 1.0 / math.tan(math.radians(float(viewport["fov_deg"])) / 2)
    near, far = float(viewport["near"]), float(viewport["far"])
    return [
        [focal / aspect, 0.0, 0.0, 0.0],
        [0.0, focal, 0.0, 0.0],
        [0.0, 0.0, (far + near) / (near - far), 2 * far * near / (near - far)],
        [0.0, 0.0, -1.0, 0.0],
    ]


def _matmul(first: list[list[float]], second: list[list[float]]) -> list[list[float]]:
    return [[sum(first[row][index] * second[index][column] for index in range(4)) for column in range(4)] for row in range(4)]


def _matvec(matrix: list[list[float]], vector: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    return tuple(sum(matrix[row][index] * vector[index] for index in range(4)) for row in range(4))  # type: ignore[return-value]


def project_point(point: list[float] | tuple[float, float, float], camera: dict[str, Any], viewport: dict[str, Any]) -> dict[str, float | bool]:
    matrix = _matmul(projection_matrix(viewport), view_matrix(camera))
    clip = _matvec(matrix, (float(point[0]), float(point[1]), float(point[2]), 1.0))
    if clip[3] <= 1e-8:
        return {"x": -9999.0, "y": -9999.0, "depth": 9999.0, "visible": False}
    ndc_x, ndc_y, ndc_z = clip[0] / clip[3], clip[1] / clip[3], clip[2] / clip[3]
    return {
        "x": (ndc_x * .5 + .5) * float(viewport["width"]),
        "y": (1 - (ndc_y * .5 + .5)) * float(viewport["height"]),
        "depth": ndc_z,
        "visible": -1.2 <= ndc_x <= 1.2 and -1.2 <= ndc_y <= 1.2 and -1 <= ndc_z <= 1,
    }


def unproject_screen(x: float, y: float, depth: float, camera: dict[str, Any], viewport: dict[str, Any]) -> tuple[float, float, float]:
    basis = camera_basis(camera)
    ndc_x = x / float(viewport["width"]) * 2 - 1
    ndc_y = 1 - y / float(viewport["height"]) * 2
    tangent = math.tan(math.radians(float(viewport["fov_deg"])) / 2)
    aspect = float(viewport["width"]) / float(viewport["height"])
    point = basis["eye"]
    point = _add(point, _scale(basis["forward"], depth))
    point = _add(point, _scale(basis["right"], ndc_x * depth * tangent * aspect))
    point = _add(point, _scale(basis["up"], ndc_y * depth * tangent))
    return point


def _rounded(point: tuple[float, float, float]) -> list[float]:
    return [round(value, 6) for value in point]


def _platform(platform_id: str, role: str, screen: tuple[float, float, float], depth: float, camera: dict[str, Any], viewport: dict[str, Any], tone: int) -> dict[str, Any]:
    left, right, top = screen
    bottom = top + 27
    back_depth = depth + .34
    front_points = [
        unproject_screen(left, top, depth, camera, viewport),
        unproject_screen(right, top, depth, camera, viewport),
        unproject_screen(right, bottom, depth, camera, viewport),
        unproject_screen(left, bottom, depth, camera, viewport),
    ]
    back_points = [
        unproject_screen(left, top, back_depth, camera, viewport),
        unproject_screen(right, top, back_depth, camera, viewport),
        unproject_screen(right, bottom, back_depth, camera, viewport),
        unproject_screen(left, bottom, back_depth, camera, viewport),
    ]
    vertices = [_rounded(point) for point in front_points + back_points]
    return {
        "id": platform_id,
        "role": role,
        "tone": tone,
        "vertices": vertices,
        "faces": [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]],
        "walk_edge": [vertices[0], vertices[1]],
    }


def projected_segments(platforms: list[dict[str, Any]], camera: dict[str, Any], viewport: dict[str, Any]) -> list[dict[str, Any]]:
    segments = []
    for platform in platforms:
        first = project_point(platform["walk_edge"][0], camera, viewport)
        second = project_point(platform["walk_edge"][1], camera, viewport)
        if float(first["x"]) <= float(second["x"]):
            left, right = first, second
        else:
            left, right = second, first
        segments.append({
            "id": platform["id"],
            "role": platform["role"],
            "left": float(left["x"]),
            "right": float(right["x"]),
            "left_y": float(left["y"]),
            "right_y": float(right["y"]),
            "visible": bool(first["visible"] and second["visible"] and float(right["x"]) - float(left["x"]) >= 42),
        })
    return segments


def _segment_y(segment: dict[str, Any], x: float) -> float:
    amount = (x - float(segment["left"])) / max(1e-9, float(segment["right"]) - float(segment["left"]))
    return float(segment["left_y"]) + (float(segment["right_y"]) - float(segment["left_y"])) * amount


def topology(platforms: list[dict[str, Any]], camera: dict[str, Any], viewport: dict[str, Any]) -> dict[str, Any]:
    segments = projected_segments(platforms, camera, viewport)
    joins: list[dict[str, Any]] = []
    directed: dict[str, set[str]] = {str(segment["id"]): set() for segment in segments}
    for index, first in enumerate(segments):
        if not first["visible"]:
            continue
        for second in segments[index + 1 :]:
            if not second["visible"]:
                continue
            overlap_left = max(float(first["left"]), float(second["left"]))
            overlap_right = min(float(first["right"]), float(second["right"]))
            if overlap_right - overlap_left >= 10:
                midpoint = (overlap_left + overlap_right) / 2
                separation = abs(_segment_y(first, midpoint) - _segment_y(second, midpoint))
                if separation <= 10:
                    directed[str(first["id"])].add(str(second["id"]))
                    directed[str(second["id"])].add(str(first["id"]))
                    joins.append({"a": first["id"], "b": second["id"], "overlap": overlap_right - overlap_left, "separation": separation})
    for first in segments:
        if not first["visible"]:
            continue
        for second in segments:
            if first is second or not second["visible"]:
                continue
            gap = float(second["left"]) - float(first["right"])
            if 4 <= gap <= 74:
                first_y = _segment_y(first, float(first["right"]))
                second_y = _segment_y(second, float(second["left"]))
                rise = first_y - second_y
                if -42 <= rise <= 78:
                    directed[str(first["id"])].add(str(second["id"]))
    start_id = next(str(item["id"]) for item in platforms if item["role"] == "start")
    exit_id = next(str(item["id"]) for item in platforms if item["role"] == "exit")
    reached = {start_id}
    frontier = [start_id]
    while frontier:
        current = frontier.pop()
        for neighbor in directed.get(current, set()):
            if neighbor not in reached:
                reached.add(neighbor)
                frontier.append(neighbor)
    core_visible = all(segment["visible"] for segment in segments if not str(segment["id"]).startswith("decoy-"))
    valid = core_visible and len(joins) >= 2 and exit_id in reached
    return {"segments": segments, "joins": joins, "reachable": sorted(reached), "valid": valid, "start_id": start_id, "exit_id": exit_id}


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    task_id = str(task.get("id") or "flat_prisoner_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|matrix-prison-v1".encode("utf-8")).hexdigest()[:14]
    layout_index = rng.randrange(len(LAYOUTS))
    depth_index = rng.randrange(len(DEPTH_STACKS))
    mirror = rng.choice((-1, 1))
    palette = copy.deepcopy(rng.choice(PALETTES))
    viewport = {"width": VIEW_WIDTH, "height": VIEW_HEIGHT, "fov_deg": FOV_DEG, "near": NEAR, "far": FAR}
    solution_camera = {
        "yaw_deg": rng.choice(YAW_VALUES),
        "pitch_deg": rng.choice(PITCH_VALUES),
        "distance": rng.choice(DISTANCE_VALUES),
        "target": [0.0, 1.0, 0.0],
    }
    initial_camera = {
        "yaw_deg": solution_camera["yaw_deg"] + mirror * 24.0,
        "pitch_deg": solution_camera["pitch_deg"] + 12.0,
        "distance": solution_camera["distance"] + 3.0,
        "target": [mirror * 2.4, 1.8, 0.0],
    }
    roles = ("start", "bridge", "bridge", "bridge", "exit")
    platforms = [
        _platform(f"surface-{index + 1:02d}", roles[index], tuple(float(value) for value in screen), DEPTH_STACKS[depth_index][index], solution_camera, viewport, rng.randrange(4))
        for index, screen in enumerate(LAYOUTS[layout_index])
    ]
    decoys = ((108, 268, 176, 9.7), (574, 778, 178, 11.4), (332, 478, 411, 7.1))
    for index, (left, right, top, depth) in enumerate(decoys, start=1):
        platforms.append(_platform(f"decoy-{index:02d}", "decoy", (left, right, top), depth + (depth_index % 2) * .55, solution_camera, viewport, rng.randrange(4)))
    controls = {
        "orbit_step_deg": 3.0,
        "pan_step": .4,
        "dolly_step": .5,
        "yaw_min": -70.0,
        "yaw_max": 70.0,
        "pitch_min": -35.0,
        "pitch_max": 28.0,
        "distance_min": 8.0,
        "distance_max": 22.0,
    }
    physics = {
        "tick_ms": 20,
        "move_speed": 116.0,
        "gravity": 780.0,
        "jump_velocity": -338.0,
        "player_width": 16.0,
        "player_height": 28.0,
        "death_y": 515.0,
        "exit_radius": 24.0,
        "maximum_deaths": 3,
    }
    requirements = {
        "minimum_camera_events": 18,
        "minimum_camera_elapsed_ms": 520,
        "minimum_freeze_settle_ms": 55,
        "minimum_screen_joins": 2,
        "minimum_traversal_ticks": 130,
        "maximum_traversal_ticks": 1800,
        "minimum_key_transitions": 5,
        "minimum_jumps": 2,
        "maximum_event_gap_ticks": 650,
        "camera_claim_tolerance": .0005,
    }
    target_topology = topology(platforms, solution_camera, viewport)
    initial_topology = topology(platforms, initial_camera, viewport)
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": "Orbit, pan, and dolly the 3D cellblock until distant ledges connect in projection. Freeze the view, then guide the flat prisoner to the exit.",
        "submit_label": "CERTIFY ESCAPE",
        "generator": {"name": "procedural_matrix_prison_v1", "variant_count": VARIANT_COUNT, "variant_count_kind": "layout/mirror/depth-stack/palette/camera construction space"},
        "palette": palette,
        "viewport": viewport,
        "initial_camera": copy.deepcopy(initial_camera),
        "controls": controls,
        "physics": physics,
        "requirements": requirements,
        "platforms": copy.deepcopy(platforms),
        "start_surface_id": target_topology["start_id"],
        "exit_surface_id": target_topology["exit_id"],
        "rules": [
            "Every ledge is projected through a perspective camera matrix. World-space proximity is irrelevant after flattening.",
            "Freeze only when enough screen-space edges genuinely overlap. The live projection audit reports joins, not a solution camera.",
            "In flat mode use continuous LEFT / RIGHT and JUMP controls. Gravity, gaps, and collision remain active.",
            "Thaw after a failed traversal, reframe the 3D scene, and freeze another temporary level.",
        ],
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "palette": copy.deepcopy(palette),
        "viewport": viewport,
        "initial_camera": copy.deepcopy(initial_camera),
        "controls": controls,
        "physics": physics,
        "requirements": requirements,
        "platforms": copy.deepcopy(platforms),
        "start_surface_id": target_topology["start_id"],
        "exit_surface_id": target_topology["exit_id"],
        "variant": {"layout": layout_index, "mirror": mirror, "depth_stack": depth_index, "palette": palette["name"]},
        "solution": {
            "camera": solution_camera,
            "required_join_pairs": [["surface-01", "surface-02"], ["surface-03", "surface-04"]],
            "screen_segments": [segment for segment in target_topology["segments"] if str(segment["id"]).startswith("surface-")],
        },
        "variant_count": VARIANT_COUNT,
        "transform_convention": "right-handed world; row-major matrices times column vectors; OpenGL clip; +Y up; camera forward is -view-Z; screen Y down",
    }
    assert target_topology["valid"] and len(target_topology["joins"]) >= 2
    assert not initial_topology["valid"]
    assert len({round(DEPTH_STACKS[depth_index][index], 1) for index in range(5)}) >= 5
    assert all(project_point(platform["walk_edge"][0], solution_camera, viewport)["visible"] for platform in platforms[:5])
    return public_state, ground_truth
