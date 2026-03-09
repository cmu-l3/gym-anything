#!/usr/bin/env python3
"""Verifier for build_high_value_order_escalations."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/build_high_value_order_escalations_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_orderedid_index(indexes):
    for idx in indexes or []:
        if (idx.get("type") or "").upper() != "UNIQUE":
            continue
        if idx.get("name") == "OrderEscalation.OrderedId":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "OrderedId":
            return True
    return False


def verify_build_high_value_order_escalations(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_orders = metadata.get("expected_orders", {})

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    escalations = result.get("escalations", {})

    # Wrong-target rejection: any escalation outside expected IDs is an immediate fail.
    unexpected = result.get("unexpected_order_ids", [])
    if unexpected:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Off-target escalations detected for OrderedId(s): {unexpected}",
        }

    score = 0
    feedback = []

    # Criterion 1: Schema shape and mandatory fields (20)
    req_props = {"OrderedId", "EscalationTier", "Reason", "OwnerEmail", "SnapshotPrice"}
    props = set(result.get("order_escalation_properties", []))
    mandatory = result.get("order_escalation_mandatory", {})
    schema_ok = (
        result.get("order_escalation_exists")
        and result.get("escalates_order_class_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if schema_ok:
        score += 20
        feedback.append("Escalation schema and edge class are correct")
    else:
        feedback.append("Escalation schema or edge class is incomplete")

    # Criterion 2: Unique index on OrderedId (20)
    if _has_unique_orderedid_index(result.get("order_escalation_indexes", [])):
        score += 20
        feedback.append("OrderEscalation.OrderedId UNIQUE index present")
    else:
        feedback.append("OrderEscalation.OrderedId UNIQUE index missing")

    # Criterion 3: Escalation payload correctness (35)
    payload_ok = True
    if sorted(escalations.keys()) != sorted(expected_orders.keys()):
        payload_ok = False
    else:
        for oid, expected in expected_orders.items():
            actual = escalations.get(oid, {})
            if actual.get("EscalationTier") != expected.get("EscalationTier"):
                payload_ok = False
                break
            if actual.get("Reason") != expected.get("Reason"):
                payload_ok = False
                break
            if actual.get("OwnerEmail") != expected.get("OwnerEmail"):
                payload_ok = False
                break
            if abs(float(actual.get("SnapshotPrice", 0.0)) - float(expected.get("SnapshotPrice", 0.0))) > 0.01:
                payload_ok = False
                break

    if payload_ok:
        score += 35
        feedback.append("Escalation record payloads are correct")
    else:
        feedback.append(f"Escalation payload mismatch: {escalations}")

    # Criterion 4: Escalation-to-order edges (20)
    edges = sorted(result.get("escalation_edges", []))
    expected_edges = sorted([f"{oid}->{oid}" for oid in expected_orders.keys()])
    if edges == expected_edges:
        score += 20
        feedback.append("Escalation edges correctly target source orders")
    else:
        feedback.append(f"Escalation edges mismatch: {edges}")

    # Criterion 5: Baseline delta proves new escalation work (5)
    baseline_count = int(result.get("baseline_escalation_count", 0) or 0)
    baseline_edge_count = int(result.get("baseline_escalation_edge_count", 0) or 0)
    if len(escalations) > baseline_count and len(edges) > baseline_edge_count:
        score += 5
        feedback.append("Escalation rows/edges increased from baseline")
    else:
        feedback.append("Baseline delta check failed")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
