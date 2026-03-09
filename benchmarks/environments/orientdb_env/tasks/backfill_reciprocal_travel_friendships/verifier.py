#!/usr/bin/env python3
"""Verifier for backfill_reciprocal_travel_friendships."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/backfill_reciprocal_travel_friendships_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def verify_backfill_reciprocal_travel_friendships(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_pairs = sorted(metadata.get("expected_reverse_pairs", []))
    required_rule_version = metadata.get("required_rule_version", "v2026q1")

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    reverse_edges = sorted(result.get("reverse_edges", []))

    # Wrong-target rejection: all expected reverse edges must be present.
    if reverse_edges != expected_pairs:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Reverse-edge backfill target mismatch: {reverse_edges}",
        }

    score = 0
    feedback = []

    # Criterion 1: TravelAffinity schema (25)
    req_props = {"SharedHotels", "CountryOverlap", "RuleVersion"}
    props = set(result.get("travel_affinity_properties", []))
    mandatory = result.get("travel_affinity_mandatory", {})
    schema_ok = (
        result.get("travel_affinity_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if schema_ok:
        score += 25
        feedback.append("TravelAffinity schema is correct")
    else:
        feedback.append("TravelAffinity schema is incomplete")

    # Criterion 2: Expected TravelAffinity edges exist and are complete (45)
    edges = {e.get("pair"): e for e in result.get("travel_affinity_edges", []) if e.get("pair")}
    edge_ok = True
    for pair in expected_pairs:
        e = edges.get(pair)
        if not e:
            edge_ok = False
            break
        if (e.get("SharedHotels") or 0) < 1:
            edge_ok = False
            break
        if (e.get("CountryOverlap") or 0) < 1:
            edge_ok = False
            break
        if e.get("RuleVersion") != required_rule_version:
            edge_ok = False
            break

    if edge_ok and len(edges) >= len(expected_pairs):
        score += 45
        feedback.append("Expected TravelAffinity edges and properties are correct")
    else:
        feedback.append("TravelAffinity edge payload is incomplete or incorrect")

    # Criterion 3: No off-target TravelAffinity edges (20)
    unexpected = result.get("unexpected_travel_affinity_pairs", [])
    if not unexpected:
        score += 20
        feedback.append("No off-target TravelAffinity edges found")
    else:
        feedback.append(f"Off-target TravelAffinity edges found: {unexpected}")

    # Criterion 4: Cardinality alignment with expected reverse pairs (5)
    if len(result.get("travel_affinity_edges", [])) == len(expected_pairs):
        score += 5
        feedback.append("TravelAffinity cardinality matches migration scope")
    else:
        feedback.append("TravelAffinity edge count does not match migration scope")

    # Criterion 5: Baseline delta proves new work (5)
    baseline_reverse = result.get("baseline_reverse_edges", [])
    baseline_aff_count = int(result.get("baseline_travel_affinity_count", 0) or 0)
    if (len(baseline_reverse) == 0 and len(reverse_edges) == len(expected_pairs)
            and len(result.get("travel_affinity_edges", [])) > baseline_aff_count):
        score += 5
        feedback.append("New reverse and affinity edges were created after baseline")
    else:
        feedback.append("Baseline delta check failed")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
