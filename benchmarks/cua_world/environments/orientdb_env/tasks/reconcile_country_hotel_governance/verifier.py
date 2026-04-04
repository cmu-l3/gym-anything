#!/usr/bin/env python3
"""Verifier for reconcile_country_hotel_governance task."""

import json
import os
import tempfile


def _load_result(copy_from_env, remote_path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_countries_name_index(indexes):
    for idx in indexes or []:
        idx_type = (idx.get("type") or "").upper()
        idx_name = idx.get("name") or ""
        fields = idx.get("fields") or []
        if idx_type != "UNIQUE":
            continue
        if idx_name == "Countries.Name":
            return True
        if len(fields) == 1 and fields[0] == "Name":
            return True
    return False


def verify_reconcile_country_hotel_governance(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_country_types = metadata.get("expected_country_types", {})
    expected_hotel_countries = metadata.get("expected_hotel_countries", {})
    expected_issue_keys = sorted(metadata.get("expected_issue_keys", []))
    required_resolved_by = metadata.get("required_resolved_by", "data_governance")

    try:
        result = _load_result(copy_from_env, "/tmp/reconcile_country_hotel_governance_result.json")
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"result unavailable: {exc}"}

    countries = result.get("countries", {})
    hotels = result.get("hotels", {})
    baseline_countries = result.get("baseline_countries", {})
    baseline_hotels = result.get("baseline_hotels", {})

    # Wrong-target rejection: flagship hotels must be corrected exactly.
    if any(hotels.get(k) != v for k, v in expected_hotel_countries.items()):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong hotel-country target state: {hotels}",
        }

    score = 0
    feedback = []

    # Criterion 1: Country type corrections (20)
    if all(countries.get(k) == v for k, v in expected_country_types.items()):
        score += 20
        feedback.append("Country type corrections are complete")
    else:
        feedback.append(f"Country type corrections incomplete: {countries}")

    # Criterion 2: Countries.Name unique index restored (20)
    if _has_unique_countries_name_index(result.get("country_indexes", [])):
        score += 20
        feedback.append("Countries.Name UNIQUE index present")
    else:
        feedback.append("Countries.Name UNIQUE index missing")

    # Criterion 3: GovernanceFixLog schema shape (20)
    required_props = {"IssueKey", "ResolvedBy", "ResolvedAt"}
    props = set(result.get("governance_fixlog_properties", []))
    mandatory = result.get("governance_fixlog_mandatory", {})
    if result.get("governance_fixlog_exists") and required_props.issubset(props) and mandatory.get("IssueKey") and mandatory.get("ResolvedBy"):
        score += 20
        feedback.append("GovernanceFixLog schema is correct")
    else:
        feedback.append("GovernanceFixLog schema is incomplete")

    # Criterion 4: Issue-key audit completeness and ownership (30)
    rows = result.get("governance_log_rows", [])
    keys = sorted(r.get("IssueKey") for r in rows if r.get("IssueKey"))
    owner_ok = all((r.get("ResolvedBy") == required_resolved_by) for r in rows)
    if keys == expected_issue_keys and owner_ok and len(rows) == len(expected_issue_keys):
        score += 30
        feedback.append("Governance fix audit rows are complete")
    else:
        feedback.append(f"Audit rows mismatch: keys={keys}, owner_ok={owner_ok}, rows={len(rows)}")

    # Criterion 5: State changed from captured baseline corruption (10)
    baseline_changed = False
    for k, v in expected_country_types.items():
        if baseline_countries.get(k) != v and countries.get(k) == v:
            baseline_changed = True
    for k, v in expected_hotel_countries.items():
        if baseline_hotels.get(k) != v and hotels.get(k) == v:
            baseline_changed = baseline_changed and True
        else:
            baseline_changed = False
            break
    if baseline_changed:
        score += 10
        feedback.append("Detected repair relative to baseline corruption")
    else:
        feedback.append("Baseline-change evidence missing")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
