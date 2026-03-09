#!/usr/bin/env python3
"""Verifier for remediate_swapped_geocoordinates."""

import json
import math
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/remediate_swapped_geocoordinates_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _close(a, b, eps=1e-4):
    return abs(float(a) - float(b)) <= eps


def verify_remediate_swapped_geocoordinates(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected = metadata.get("expected_coordinates", {})
    required_batch = metadata.get("required_fix_batch", "geo_swap_2026q1")

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    coords = result.get("coordinates", {})
    baseline_coords = result.get("baseline_coordinates", {})

    # Wrong-target rejection: all target coordinates must be exactly repaired.
    for hotel, target in expected.items():
        actual = coords.get(hotel)
        if not actual:
            return {"passed": False, "score": 0, "feedback": f"Missing hotel coordinate: {hotel}"}
        if not (_close(actual.get("Latitude"), target.get("Latitude")) and _close(actual.get("Longitude"), target.get("Longitude"))):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Coordinate mismatch for {hotel}: {actual}",
            }

    score = 0
    feedback = []

    # Criterion 1: Coordinate ranges are valid (15)
    range_ok = True
    for hotel in expected:
        lat = float(coords[hotel]["Latitude"])
        lon = float(coords[hotel]["Longitude"])
        if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
            range_ok = False
            break
    if range_ok:
        score += 15
        feedback.append("Coordinates are in valid geospatial ranges")
    else:
        feedback.append("One or more coordinates are still out of range")

    # Criterion 2: GeoFixAudit schema (30)
    req_props = {
        "HotelName",
        "PreviousLatitude",
        "PreviousLongitude",
        "NewLatitude",
        "NewLongitude",
        "FixBatch",
    }
    props = set(result.get("geo_fix_audit_properties", []))
    mandatory = result.get("geo_fix_audit_mandatory", {})
    schema_ok = result.get("geo_fix_audit_exists") and req_props.issubset(props) and all(mandatory.get(p, False) for p in req_props)
    if schema_ok:
        score += 30
        feedback.append("GeoFixAudit schema is complete")
    else:
        feedback.append("GeoFixAudit schema is incomplete")

    # Criterion 3: Audit row coverage and batch tag (30)
    rows = result.get("geo_fix_audit_rows", [])
    names = sorted(r.get("HotelName") for r in rows if r.get("HotelName"))
    expected_names = sorted(expected.keys())
    batch_ok = all(r.get("FixBatch") == required_batch for r in rows)
    if names == expected_names and batch_ok and len(rows) == len(expected_names):
        score += 30
        feedback.append("GeoFixAudit rows cover all corrected hotels")
    else:
        feedback.append(f"GeoFixAudit row mismatch: names={names}, batch_ok={batch_ok}, rows={len(rows)}")

    # Criterion 4: Audit new-values match repaired coordinates (20)
    audit_match = True
    by_name = {r.get("HotelName"): r for r in rows if r.get("HotelName")}
    for hotel, target in expected.items():
        row = by_name.get(hotel)
        if not row:
            audit_match = False
            break
        if not (_close(row.get("NewLatitude", 0.0), target["Latitude"]) and _close(row.get("NewLongitude", 0.0), target["Longitude"])):
            audit_match = False
            break

    if audit_match:
        score += 20
        feedback.append("GeoFixAudit new-values match repaired coordinates")
    else:
        feedback.append("GeoFixAudit new-values do not match repaired coordinates")

    # Criterion 5: Coordinates changed from baseline corruption (5)
    baseline_changed = True
    for hotel, target in expected.items():
        b = baseline_coords.get(hotel, {})
        if _close(b.get("Latitude", target["Latitude"]), target["Latitude"]) and _close(
            b.get("Longitude", target["Longitude"]), target["Longitude"]
        ):
            baseline_changed = False
            break
    if baseline_changed:
        score += 5
        feedback.append("Detected coordinate repair relative to baseline")
    else:
        feedback.append("Baseline-change evidence missing")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
