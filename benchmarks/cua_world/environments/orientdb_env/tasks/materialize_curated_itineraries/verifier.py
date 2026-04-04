#!/usr/bin/env python3
"""Verifier for materialize_curated_itineraries."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/materialize_curated_itineraries_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_email_index(indexes):
    for idx in indexes or []:
        if (idx.get("type") or "").upper() != "UNIQUE":
            continue
        if idx.get("name") == "ItinerarySummary.Email":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "Email":
            return True
    return False


def verify_materialize_curated_itineraries(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_visits = metadata.get("expected_visits", {})
    expected_summary = metadata.get("expected_summary", {})

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    visits = result.get("visits", {})

    # Wrong-target rejection: visit mapping must exactly match target cohort.
    if visits != expected_visits:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"HasVisited mapping mismatch: {visits}",
        }

    score = 0
    feedback = []

    # Criterion 1: ItinerarySummary schema completeness (25)
    req_props = {"Email", "Country", "HotelCount", "RestaurantCount", "AttractionCount", "CurationTag"}
    props = set(result.get("itinerary_summary_properties", []))
    mandatory = result.get("itinerary_summary_mandatory", {})
    schema_ok = result.get("itinerary_summary_exists") and req_props.issubset(props) and all(mandatory.get(p, False) for p in req_props)
    if schema_ok:
        score += 25
        feedback.append("ItinerarySummary schema is complete")
    else:
        feedback.append("ItinerarySummary schema is incomplete")

    # Criterion 2: UNIQUE index on Email (20)
    if _has_unique_email_index(result.get("itinerary_summary_indexes", [])):
        score += 20
        feedback.append("ItinerarySummary.Email UNIQUE index present")
    else:
        feedback.append("ItinerarySummary.Email UNIQUE index missing")

    # Criterion 3: Summary payload exactness (45)
    summary = result.get("summary", {})
    payload_ok = summary == expected_summary
    if payload_ok:
        score += 45
        feedback.append("Summary payloads are exact for all cohort profiles")
    else:
        feedback.append(f"Summary payload mismatch: {summary}")

    # Criterion 4: Row cardinality control + baseline delta (10)
    current_rows = int(result.get("summary_row_count", 0) or 0)
    baseline_rows = int(result.get("baseline_summary_row_count", 0) or 0)
    baseline_visits = int(result.get("baseline_visit_count", 0) or 0)
    current_visits = len(visits)
    if (current_rows == len(expected_summary)
            and current_rows > baseline_rows
            and current_visits > baseline_visits):
        score += 10
        feedback.append("Summary cardinality and baseline delta are correct")
    else:
        feedback.append("Unexpected summary cardinality or no baseline delta")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
