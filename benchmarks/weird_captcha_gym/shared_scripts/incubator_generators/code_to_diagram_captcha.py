from __future__ import annotations

import hashlib
import random
from typing import Any


MECHANIC_ID = "code_to_diagram_captcha"
PALETTES = ("oxide", "cyanotype", "signal")
NODE_POSITIONS = (
    (13, 22), (42, 14), (72, 22),
    (13, 69), (42, 78), (72, 69),
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _node_ids(rng: random.Random) -> list[str]:
    letters = list("ABCDEFGHJKLMNPQRSTUVWXYZ")
    rng.shuffle(letters)
    digits = list("23456789")
    rng.shuffle(digits)
    return [f"{letters[index]}{digits[index]}" for index in range(6)]


def _condition(rng: random.Random) -> dict[str, Any]:
    kind = rng.choice(("gte", "lt", "even", "mod3"))
    if kind == "gte":
        threshold = rng.randint(3, 11)
        return {"kind": kind, "value": threshold, "display": f"probe >= {threshold}"}
    if kind == "lt":
        threshold = rng.randint(0, 9)
        return {"kind": kind, "value": threshold, "display": f"probe < {threshold}"}
    if kind == "even":
        return {"kind": kind, "value": 0, "display": "probe % 2 == 0"}
    residue = rng.randint(0, 2)
    return {"kind": kind, "value": residue, "display": f"probe % 3 == {residue}"}


def _condition_result(condition: dict[str, Any], value: int) -> bool:
    kind = condition["kind"]
    target = int(condition["value"])
    if kind == "gte":
        return value >= target
    if kind == "lt":
        return value < target
    if kind == "even":
        return value % 2 == 0
    return value % 3 == target


def _trace(nodes: list[dict[str, Any]], entry_id: str, probe: int) -> dict[str, Any]:
    by_id = {str(node["id"]): node for node in nodes}
    current = entry_id
    accumulator = probe
    steps: list[dict[str, Any]] = []
    for sequence in range(1, 10):
        node = by_id[current]
        before = accumulator
        kind = str(node["kind"])
        if kind == "entry":
            accumulator = probe
            branch = "NEXT"
        elif kind == "decision":
            branch = "TRUE" if _condition_result(node["condition"], probe) else "FALSE"
        elif kind == "operation":
            amount = int(node["amount"])
            accumulator = accumulator + amount if node["operator"] == "add" else accumulator - amount
            branch = "NEXT"
        elif kind == "audit":
            multiplier = int(node["multiplier"])
            accumulator *= multiplier
            branch = "NEXT"
        elif kind == "halt":
            branch = "HALT"
        else:
            raise AssertionError(f"unknown node kind {kind}")
        next_node = (node.get("transitions") or {}).get(branch)
        steps.append({
            "sequence": sequence,
            "node_id": current,
            "value_before": before,
            "value_after": accumulator,
            "branch": branch,
            "next_node_id": next_node,
        })
        if branch == "HALT":
            return {"input": probe, "steps": steps, "halted": True, "output": accumulator}
        if not next_node:
            raise AssertionError("program transition is missing")
        current = str(next_node)
    raise AssertionError("generated control-flow program did not halt")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    ids = _node_ids(rng)
    entry_id, gate_id, true_id, false_id, audit_id, halt_id = ids
    condition = _condition(rng)
    true_amount = rng.randint(2, 8)
    false_amount = rng.randint(2, 8)
    long_branch = rng.choice(("TRUE", "FALSE"))

    true_next = audit_id if long_branch == "TRUE" else halt_id
    false_next = audit_id if long_branch == "FALSE" else halt_id
    nodes: list[dict[str, Any]] = [
        {
            "id": entry_id,
            "kind": "entry",
            "title": "ENTRY",
            "code": f"acc <- probe   GOTO {gate_id}",
            "transitions": {"NEXT": gate_id},
            "ports": ["NEXT"],
        },
        {
            "id": gate_id,
            "kind": "decision",
            "title": "BRANCH",
            "code": f"IF {condition['display']}   T:{true_id} / F:{false_id}",
            "condition": condition,
            "transitions": {"TRUE": true_id, "FALSE": false_id},
            "ports": ["TRUE", "FALSE"],
        },
        {
            "id": true_id,
            "kind": "operation",
            "title": "TRUE BAY",
            "code": f"acc <- acc + {true_amount}   GOTO {true_next}",
            "operator": "add",
            "amount": true_amount,
            "transitions": {"NEXT": true_next},
            "ports": ["NEXT"],
        },
        {
            "id": false_id,
            "kind": "operation",
            "title": "FALSE BAY",
            "code": f"acc <- acc - {false_amount}   GOTO {false_next}",
            "operator": "subtract",
            "amount": false_amount,
            "transitions": {"NEXT": false_next},
            "ports": ["NEXT"],
        },
        {
            "id": audit_id,
            "kind": "audit",
            "title": "AUDIT",
            "code": f"acc <- acc * 2   GOTO {halt_id}",
            "multiplier": 2,
            "transitions": {"NEXT": halt_id},
            "ports": ["NEXT"],
        },
        {
            "id": halt_id,
            "kind": "halt",
            "title": "EMIT",
            "code": "HALT / EMIT acc",
            "transitions": {},
            "ports": [],
        },
    ]

    positions = list(NODE_POSITIONS)
    rng.shuffle(positions)
    position_by_id = {node_id: positions[index] for index, node_id in enumerate(ids)}
    for node in nodes:
        x, y = position_by_id[str(node["id"])]
        node["x"] = x
        node["y"] = y

    true_candidates = [value for value in range(-8, 25) if _condition_result(condition, value)]
    false_candidates = [value for value in range(-8, 25) if not _condition_result(condition, value)]
    rng.shuffle(true_candidates)
    rng.shuffle(false_candidates)
    if rng.choice((True, False)):
        probe_inputs = [true_candidates[0], true_candidates[1], false_candidates[0]]
    else:
        probe_inputs = [false_candidates[0], false_candidates[1], true_candidates[0]]
    rng.shuffle(probe_inputs)
    probe_runs = [_trace(nodes, entry_id, probe) for probe in probe_inputs]

    expected_edges: list[dict[str, str]] = []
    for node in nodes:
        for label, target in (node.get("transitions") or {}).items():
            expected_edges.append({
                "from_port": f"{node['id']}:{label}",
                "label": label,
                "to_node": str(target),
            })
    expected_edges.sort(key=lambda edge: edge["from_port"])
    public_nodes: list[dict[str, Any]] = []
    for node in nodes:
        visible = {key: value for key, value in node.items() if key not in {"transitions", "code"}}
        if node["kind"] == "entry":
            visible["code"] = "acc <- probe   DISPATCH NEXT"
        elif node["kind"] == "decision":
            visible["code"] = f"IF {condition['display']}   DISPATCH TRUE / FALSE"
        elif node["kind"] == "operation":
            sign = "+" if node["operator"] == "add" else "-"
            visible["code"] = f"acc <- acc {sign} {node['amount']}   DISPATCH NEXT"
        elif node["kind"] == "audit":
            visible["code"] = f"acc <- acc * {node['multiplier']}   DISPATCH NEXT"
        else:
            visible["code"] = "HALT / EMIT acc"
        public_nodes.append(visible)
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Probe the program, then wire its control-flow diagram.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "live_control_flow_wiring_lab_v1", "variant_count": 4_000_000_000},
        "palette": rng.choice(PALETTES),
        "program_id": f"CF-{challenge_id.upper()}",
        "entry_id": entry_id,
        "nodes": public_nodes,
        "probe_inputs": probe_inputs,
        # The static plugin seam has no authenticated per-step endpoint. These
        # future trace frames stay out of the rendered DOM until the operator
        # physically steps the debugger, but browser-internals agents could
        # inspect this field. Ground-truth grading never trusts it.
        "runtime_probe_runs": probe_runs,
        "required_probe_count": 3,
        "submit_label": "VALIDATE HARNESS",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "entry_id": entry_id,
        "nodes": nodes,
        "node_ids": sorted(ids),
        "probe_inputs": probe_inputs,
        "expected_probe_runs": probe_runs,
        "expected_edges": expected_edges,
        "variant_count": 4_000_000_000,
    }
    covered = {step["node_id"] for run in probe_runs for step in run["steps"]}
    assert covered == set(ids)
    assert len(expected_edges) == 6
    assert len({run["input"] for run in probe_runs}) == 3
    return public_state, ground_truth
