from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "exit_vim_terminal_escape"
CALLSIGNS = ("MOTH", "KITE", "EMBER", "NOVA", "RAVEN", "MICA", "ORBIT", "LATCH")
ROUTES = ("NORTH-7", "BAY-12", "VAULT-3", "RING-9", "ECHO-4", "DOCK-8")
TOKENS = ("K7Q2", "V4MX", "P9RA", "D2WN", "H8LC", "T5ZF", "B3JK")
LAYER_NAMES = ("pager", "job", "ssh")


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _different(rng: random.Random, values: tuple[str, ...], target: str) -> str:
    choices = [value for value in values if value != target]
    return rng.choice(choices)


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    callsign = rng.choice(CALLSIGNS)
    route = rng.choice(ROUTES)
    token = rng.choice(TOKENS)
    target_buffer = [
        f"AGENT={callsign}",
        f"ROUTE={route}",
        f"TOKEN={token}",
    ]
    initial_buffer = [
        f"AGENT={_different(rng, CALLSIGNS, callsign)}",
        f"ROUTE={_different(rng, ROUTES, route)}",
        f"TOKEN={_different(rng, TOKENS, token)}",
    ]
    layer_count = rng.choice((2, 3))
    layers = list(LAYER_NAMES)
    rng.shuffle(layers)
    layer_order = layers[:layer_count]
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "")
    host = f"gate-{rng.randint(12, 98)}.verify"
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Repair the manifest, write it, and escape every terminal layer.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "modal_terminal_escape_v1", "variant_count": 9_000_000_000},
        "initial_buffer": initial_buffer,
        "target_buffer": target_buffer,
        "layer_order": layer_order,
        "host": host,
        "session_label": f"TTY-{challenge_id[:6].upper()}",
        "submit_label": "VERIFY SESSION",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "initial_buffer": initial_buffer,
        "target_buffer": target_buffer,
        "layer_order": layer_order,
        "host": host,
        "variant_count": 9_000_000_000,
    }
    assert len(initial_buffer) == len(target_buffer) == 3
    assert all(initial != target for initial, target in zip(initial_buffer, target_buffer))
    assert len(layer_order) in {2, 3}
    assert len(set(layer_order)) == len(layer_order)
    return public_state, ground_truth
