#!/usr/bin/env python3
"""Verifier for link_nearby_restaurants_and_attractions."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/link_nearby_restaurants_and_attractions_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_notunique_city_index(indexes):
    for idx in indexes or []:
        itype = (idx.get("type") or "").upper()
        if itype not in ("NOTUNIQUE", "NOTUNIQUE_HASH_INDEX"):
            continue
        if idx.get("name") == "RecommendationManifest.City":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "City":
            return True
    return False


def verify_link_nearby_restaurants_and_attractions(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_edges = [
        (e["restaurant"], e["attraction"]) for e in metadata.get("expected_edges", [])
    ]
    expected_edge_count = metadata.get("expected_edge_count", 8)
    batch_id = metadata.get("batch_id", "geo_proximity_2026q1")

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    # Wrong-target rejection: any cross-city ProximityLink edge
    cross_city = result.get("cross_city_edges", [])
    if cross_city:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Cross-city ProximityLink edges detected: {cross_city[:3]}",
        }

    score = 0
    feedback = []

    proximity_edges_raw = result.get("proximity_edges", [])
    # Build set of (restaurant, attraction) pairs from edges
    edge_pairs = set()
    for e in proximity_edges_raw:
        if "->" in e:
            parts = e.split("->", 1)
            edge_pairs.add((parts[0], parts[1]))

    manifest_rows = result.get("manifest_rows", [])

    # Criterion 1: ProximityLink edge class with mandatory MatchBasis property (15 pts)
    pl_props = set(result.get("proximity_link_properties", []))
    pl_mandatory = result.get("proximity_link_mandatory", {})
    pl_ok = (
        result.get("proximity_link_exists")
        and "MatchBasis" in pl_props
        and pl_mandatory.get("MatchBasis", False)
    )
    if pl_ok:
        score += 15
        feedback.append("ProximityLink edge class with mandatory MatchBasis present")
    else:
        feedback.append(f"ProximityLink edge class incomplete; props={sorted(pl_props)}")

    # Criterion 2: RecommendationManifest schema with all 5 mandatory properties (20 pts)
    req_props = {"RestaurantName", "AttractionName", "City", "MatchBasis", "BatchId"}
    rm_props = set(result.get("recommendation_manifest_properties", []))
    rm_mandatory = result.get("recommendation_manifest_mandatory", {})
    rm_schema_ok = (
        result.get("recommendation_manifest_exists")
        and req_props.issubset(rm_props)
        and all(rm_mandatory.get(p, False) for p in req_props)
    )
    if rm_schema_ok:
        score += 20
        feedback.append("RecommendationManifest schema correct with all 5 mandatory properties")
    else:
        feedback.append(f"RecommendationManifest schema incomplete; found={sorted(rm_props)}")

    # Criterion 3: NOTUNIQUE index on RecommendationManifest.City (15 pts)
    if _has_notunique_city_index(result.get("recommendation_manifest_indexes", [])):
        score += 15
        feedback.append("RecommendationManifest.City NOTUNIQUE index present")
    else:
        feedback.append("RecommendationManifest.City NOTUNIQUE index missing")

    # Criterion 4: Total edge count = 8 (10 pts)
    edge_count = result.get("proximity_edge_count", 0)
    if edge_count == expected_edge_count:
        score += 10
        feedback.append(f"ProximityLink edge count = {expected_edge_count} correct")
    else:
        feedback.append(f"ProximityLink edge count: expected {expected_edge_count}, got {edge_count}")

    # Criterion 5: Spot-check 3 specific pairs (30 pts — 10 each)
    spot_pairs = [
        ("Da Enzo al 29", "Colosseum"),
        ("Lorenz Adlon Esszimmer", "Brandenburg Gate"),
        ("Le Cinq", "Eiffel Tower"),
    ]
    spot_pts = 0
    spot_feedback = []
    for rest, attr in spot_pairs:
        if (rest, attr) in edge_pairs:
            spot_pts += 10
        else:
            spot_feedback.append(f"Missing: {rest}->{attr}")
    score += spot_pts
    if spot_pts == 30:
        feedback.append("All 3 spot-checked edges present")
    else:
        feedback.append(f"Spot-check failures: {spot_feedback}")

    # Criterion 6: Manifest row count = 8 with correct BatchId (10 pts)
    manifest_count = result.get("manifest_row_count", 0)
    batch_ok = all(r.get("BatchId") == batch_id for r in manifest_rows) if manifest_rows else False
    if manifest_count == expected_edge_count and batch_ok:
        score += 10
        feedback.append(f"Manifest rows count={manifest_count} with correct BatchId")
    elif manifest_count == expected_edge_count:
        score += 5
        feedback.append(f"Manifest count correct ({manifest_count}) but BatchId mismatch")
    else:
        feedback.append(f"Manifest row count: expected {expected_edge_count}, got {manifest_count}")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
