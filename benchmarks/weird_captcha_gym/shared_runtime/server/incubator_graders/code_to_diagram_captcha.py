from __future__ import annotations

from typing import Any


MECHANIC_ID = "code_to_diagram_captcha"


def _identity_error(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> str | None:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return "mechanic mismatch"
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return "ground-truth mechanic mismatch"
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return "stale challenge"
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return "public-state challenge mismatch"
    return None


def _condition_result(condition: dict[str, Any], value: int) -> bool:
    kind = str(condition.get("kind") or "")
    target = int(condition.get("value"))
    if kind == "gte":
        return value >= target
    if kind == "lt":
        return value < target
    if kind == "even":
        return value % 2 == 0
    if kind == "mod3":
        return value % 3 == target
    raise ValueError("unknown branch condition")


def _simulate(nodes: list[dict[str, Any]], entry_id: str, probe: int) -> dict[str, Any]:
    by_id = {str(node.get("id") or ""): node for node in nodes}
    if not entry_id or entry_id not in by_id or len(by_id) != 6:
        raise ValueError("invalid six-node program")
    current = entry_id
    accumulator = probe
    steps: list[dict[str, Any]] = []
    for sequence in range(1, 10):
        node = by_id.get(current)
        if node is None:
            raise ValueError("transition references an unknown node")
        before = accumulator
        kind = str(node.get("kind") or "")
        if kind == "entry":
            accumulator = probe
            branch = "NEXT"
        elif kind == "decision":
            condition = node.get("condition")
            if not isinstance(condition, dict):
                raise ValueError("decision condition is malformed")
            branch = "TRUE" if _condition_result(condition, probe) else "FALSE"
        elif kind == "operation":
            amount = int(node.get("amount"))
            accumulator = accumulator + amount if node.get("operator") == "add" else accumulator - amount
            branch = "NEXT"
        elif kind == "audit":
            accumulator *= int(node.get("multiplier"))
            branch = "NEXT"
        elif kind == "halt":
            branch = "HALT"
        else:
            raise ValueError("unknown program opcode")
        transitions = node.get("transitions")
        if not isinstance(transitions, dict):
            raise ValueError("program transitions are malformed")
        next_node = transitions.get(branch)
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
        if not isinstance(next_node, str) or not next_node:
            raise ValueError("program transition is missing")
        current = next_node
    raise ValueError("program exceeded replay bound")


def _expected_edges(nodes: list[dict[str, Any]]) -> list[dict[str, str]]:
    edges: list[dict[str, str]] = []
    for node in nodes:
        node_id = str(node.get("id") or "")
        transitions = node.get("transitions")
        if not node_id or not isinstance(transitions, dict):
            raise ValueError("program graph is malformed")
        for label, target in transitions.items():
            edges.append({"from_port": f"{node_id}:{label}", "label": str(label), "to_node": str(target)})
    return sorted(edges, key=lambda edge: edge["from_port"])


def _normalize_wire(item: Any) -> dict[str, str] | None:
    if not isinstance(item, dict):
        return None
    wire = {
        "from_port": str(item.get("from_port") or ""),
        "label": str(item.get("label") or ""),
        "to_node": str(item.get("to_node") or ""),
    }
    return wire if all(wire.values()) else None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    identity_error = _identity_error(payload, ground_truth, public_state)
    if identity_error:
        return {"graded": True, "passed": False, "feedback": identity_error}
    nodes = ground_truth.get("nodes")
    if not isinstance(nodes, list):
        return {"graded": True, "passed": False, "feedback": "missing private program"}
    try:
        expected_inputs = [int(value) for value in ground_truth.get("probe_inputs") or []]
        expected_runs = {
            value: _simulate(nodes, str(ground_truth.get("entry_id") or ""), value)
            for value in expected_inputs
        }
        expected_edges = _expected_edges(nodes)
    except (TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid program contract: {exc}"}

    runs = payload.get("probe_runs")
    if not isinstance(runs, list) or len(runs) != 3 or len(expected_runs) != 3:
        return {"graded": True, "passed": False, "feedback": "exactly three debugger probes are required"}
    seen_inputs: set[int] = set()
    covered_nodes: set[str] = set()
    total_steps = 0
    for index, run in enumerate(runs, start=1):
        if not isinstance(run, dict) or isinstance(run.get("input"), bool):
            return {"graded": True, "passed": False, "feedback": f"probe {index} is malformed"}
        try:
            probe = int(run.get("input"))
        except (TypeError, ValueError):
            return {"graded": True, "passed": False, "feedback": f"probe {index} input is invalid"}
        if probe in seen_inputs or probe not in expected_runs:
            return {"graded": True, "passed": False, "feedback": "probe set is duplicated or unauthorized"}
        expected_run = expected_runs[probe]
        if run != expected_run:
            return {"graded": True, "passed": False, "feedback": f"probe {probe} does not match debugger replay"}
        seen_inputs.add(probe)
        for step in run["steps"]:
            covered_nodes.add(str(step["node_id"]))
            total_steps += 1
    node_ids = {str(node.get("id") or "") for node in nodes}
    if seen_inputs != set(expected_inputs) or covered_nodes != node_ids:
        return {"graded": True, "passed": False, "feedback": "debugger coverage is incomplete"}

    raw_events = payload.get("wire_events")
    if not isinstance(raw_events, list) or len(raw_events) > 120:
        return {"graded": True, "passed": False, "feedback": "wire transcript is missing or too long"}
    valid_ports = {edge["from_port"]: edge["label"] for edge in expected_edges}
    active: dict[str, dict[str, str]] = {}
    connect_count = 0
    for sequence, event in enumerate(raw_events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"wire event {sequence} has invalid sequence"}
        action = str(event.get("action") or "")
        wire = _normalize_wire(event)
        if wire is None:
            return {"graded": True, "passed": False, "feedback": f"wire event {sequence} is malformed"}
        if wire["from_port"] not in valid_ports or wire["label"] != valid_ports[wire["from_port"]]:
            return {"graded": True, "passed": False, "feedback": f"wire event {sequence} uses an invalid output port"}
        if wire["to_node"] not in node_ids or wire["to_node"] == wire["from_port"].split(":", 1)[0]:
            return {"graded": True, "passed": False, "feedback": f"wire event {sequence} uses an invalid destination"}
        if action == "connect":
            if wire["from_port"] in active:
                return {"graded": True, "passed": False, "feedback": f"wire event {sequence} overwrites a live wire"}
            active[wire["from_port"]] = wire
            connect_count += 1
        elif action == "disconnect":
            if active.get(wire["from_port"]) != wire:
                return {"graded": True, "passed": False, "feedback": f"wire event {sequence} disconnect does not match replay"}
            del active[wire["from_port"]]
        else:
            return {"graded": True, "passed": False, "feedback": f"wire event {sequence} has invalid action"}

    submitted_wires = payload.get("final_wires")
    if not isinstance(submitted_wires, list):
        return {"graded": True, "passed": False, "feedback": "final wire inventory is missing"}
    normalized_final: list[dict[str, str]] = []
    for item in submitted_wires:
        wire = _normalize_wire(item)
        if wire is None:
            return {"graded": True, "passed": False, "feedback": "final wire inventory is malformed"}
        normalized_final.append(wire)
    normalized_final.sort(key=lambda wire: wire["from_port"])
    replay_final = sorted(active.values(), key=lambda wire: wire["from_port"])
    if normalized_final != replay_final:
        return {"graded": True, "passed": False, "feedback": "final wires do not match the physical wiring transcript"}
    passed = replay_final == expected_edges and connect_count >= len(expected_edges)
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"debugger probes 3/3; nodes {len(covered_nodes)}/6; steps {total_steps}; "
            f"wires {sum(wire in expected_edges for wire in replay_final)}/{len(expected_edges)}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "probe_runs": ground_truth.get("expected_probe_runs") or [],
        "expected_edges": ground_truth.get("expected_edges") or [],
        "answers": [],
    }
