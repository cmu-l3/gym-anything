from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "fake_desktop_automation_inversion"
DESKTOP_WIDTH = 900
DESKTOP_HEIGHT = 510
MAPPINGS = ("normal", "mirror_x", "mirror_y", "rotate_180")
KEYFILE_NAMES = (
    "HUMAN_OVERRIDE.KEY",
    "PARADOX_TOKEN.KEY",
    "ORGANIC_INPUT.KEY",
    "OPERATOR_PROOF.KEY",
    "MANUAL_ONLY.KEY",
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def _window(window_id: str, title: str, x: int, y: int, width: int, height: int, z: int) -> dict[str, Any]:
    return {
        "id": window_id,
        "title": title,
        "x": x,
        "y": y,
        "width": width,
        "height": height,
        "z": z,
        "closed": False,
        "closable": True,
    }


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    mappings = list(MAPPINGS)
    rng.shuffle(mappings)
    mapping_sequence = mappings[:2]

    target_name = rng.choice(KEYFILE_NAMES)
    decoy_pool = [name for name in KEYFILE_NAMES if name != target_name]
    rng.shuffle(decoy_pool)
    file_names = [target_name, decoy_pool[0], decoy_pool[1]]
    rng.shuffle(file_names)
    files = []
    target_file_id = ""
    for index, name in enumerate(file_names):
        file_id = f"file-{hashlib.sha256(f'{seed}|{name}'.encode('utf-8')).hexdigest()[:8]}"
        if name == target_name:
            target_file_id = file_id
        files.append({"id": file_id, "name": name, "slot": index})

    jitter_x = rng.randint(-12, 12)
    jitter_y = rng.randint(-9, 9)
    windows = [
        _window("directive", "MANUAL OPERATOR DIRECTIVE", 20, 28, 314, 108, 2),
        _window("vault", "LOCAL KEY VAULT", 72 + jitter_x, 154 + jitter_y, 368, 258, 1),
        _window("verifier", "AUTOMATION VERIFIER", 538 - jitter_x, 214 - jitter_y, 330, 252, 3),
        _window("interceptor", "BOT ACTIVITY INTERCEPTOR", 214 + jitter_x, 108 + jitter_y, 352, 230, 4),
    ]
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "fake_desktop_automation_inversion_seed_0001@0.1")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Use the transformed remote cursor to recover the named keyfile and certify manual control.",
        "submit_label": "SUBMIT MANUAL AUDIT",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {
            "name": "automation_inversion_desktop_v1",
            "variant_count": len(MAPPINGS) * (len(MAPPINGS) - 1) * len(KEYFILE_NAMES) * 25 * 19,
        },
        "desktop": {"width": DESKTOP_WIDTH, "height": DESKTOP_HEIGHT},
        "mapping_sequence": mapping_sequence,
        "mapping_labels": {
            "normal": "DIRECT / X→X · Y→Y",
            "mirror_x": "MIRROR X / X→−X · Y→Y",
            "mirror_y": "MIRROR Y / X→X · Y→−Y",
            "rotate_180": "ROTATE 180° / X→−X · Y→−Y",
        },
        "windows": windows,
        "files": files,
        "target_filename": target_name,
        "required_blocker_id": "interceptor",
        "workflow": [
            "Close the interceptor and move a window to expose the vault.",
            f"Drag {target_name} into the verifier intake.",
            "After the visible remap, use the remote cursor to arm MANUAL CONTROL.",
        ],
        "geometry": {
            "title_height": 38,
            "close_width": 44,
            "file_origin": [22, 82],
            "file_size": [98, 82],
            "file_gap": 8,
            "drop_zone": [20, 70, 290, 104],
            "arm_control": [20, 184, 186, 48],
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "desktop": public_state["desktop"],
        "mapping_sequence": mapping_sequence,
        "initial_windows": windows,
        "files": files,
        "target_file_id": target_file_id,
        "target_filename": target_name,
        "required_blocker_id": "interceptor",
        "geometry": public_state["geometry"],
        "minimum_window_move": 44,
        "variant_count": public_state["generator"]["variant_count"],
    }
    assert len(windows) == 4
    assert len(set(mapping_sequence)) == 2
    assert sum(1 for item in files if item["id"] == target_file_id) == 1
    return public_state, ground_truth
