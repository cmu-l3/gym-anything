#!/usr/bin/env python3
"""Verifier for assign_hotel_maintenance_priorities."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/assign_hotel_maintenance_priorities_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_hotel_name_index(indexes):
    for idx in indexes or []:
        if (idx.get("type") or "").upper() != "UNIQUE":
            continue
        if idx.get("name") == "HotelMaintenanceFlag.HotelName":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "HotelName":
            return True
    return False


def verify_assign_hotel_maintenance_priorities(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_counts = metadata.get("expected_priority_counts", {})
    spot_check = metadata.get("spot_check", {})
    maintenance_batch = metadata.get("maintenance_batch", "maint_q1_2026")
    last_inspection_year = metadata.get("last_inspection_year", 2024)

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    # Wrong-target rejection: any hotel assigned wrong priority
    wrong_priority = result.get("wrong_priority_hotels", [])
    if wrong_priority:
        examples = wrong_priority[:3]
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Hotels with incorrect priority: {examples}",
        }

    score = 0
    feedback = []
    flag_rows = result.get("flag_rows", {})
    priority_counts = result.get("priority_counts", {})

    # Criterion 1: HotelMaintenanceFlag schema + mandatory properties (15 pts)
    req_props = {"HotelName", "Priority", "LastInspectionYear", "MaintenanceBatch"}
    props = set(result.get("maintenance_flag_properties", []))
    mandatory = result.get("maintenance_flag_mandatory", {})
    schema_ok = (
        result.get("maintenance_flag_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if schema_ok:
        score += 15
        feedback.append("HotelMaintenanceFlag schema correct with all mandatory properties")
    else:
        feedback.append(f"Schema incomplete; props={sorted(props)}, mandatory={mandatory}")

    # Criterion 2: RequiresMaintenance edge class exists (10 pts)
    if result.get("requires_maintenance_exists"):
        score += 10
        feedback.append("RequiresMaintenance edge class exists")
    else:
        feedback.append("RequiresMaintenance edge class missing")

    # Criterion 3: UNIQUE index on HotelName (15 pts)
    if _has_unique_hotel_name_index(result.get("maintenance_flag_indexes", [])):
        score += 15
        feedback.append("HotelMaintenanceFlag.HotelName UNIQUE index present")
    else:
        feedback.append("HotelMaintenanceFlag.HotelName UNIQUE index missing")

    # Criterion 4: Total row count = 15 (5 pts)
    flag_count = result.get("flag_row_count", 0)
    if flag_count == 15:
        score += 5
        feedback.append("Flag row count = 15 correct")
    else:
        feedback.append(f"Flag row count: expected 15, got {flag_count}")

    # Criterion 5: CRITICAL count = 6 (15 pts)
    critical_actual = priority_counts.get("CRITICAL", 0)
    if critical_actual == expected_counts.get("CRITICAL", 6):
        score += 15
        feedback.append("CRITICAL count = 6 correct")
    else:
        feedback.append(f"CRITICAL count: expected 6, got {critical_actual}")

    # Criterion 6: HIGH count = 6 (15 pts)
    high_actual = priority_counts.get("HIGH", 0)
    if high_actual == expected_counts.get("HIGH", 6):
        score += 15
        feedback.append("HIGH count = 6 correct")
    else:
        feedback.append(f"HIGH count: expected 6, got {high_actual}")

    # Criterion 7: STANDARD count = 3 (10 pts)
    standard_actual = priority_counts.get("STANDARD", 0)
    if standard_actual == expected_counts.get("STANDARD", 3):
        score += 10
        feedback.append("STANDARD count = 3 correct")
    else:
        feedback.append(f"STANDARD count: expected 3, got {standard_actual}")

    # Criterion 8: RequiresMaintenance edge count = 15 (10 pts)
    edge_count = result.get("edge_count", 0)
    if edge_count == 15:
        score += 10
        feedback.append("RequiresMaintenance edge count = 15 correct")
    else:
        feedback.append(f"RequiresMaintenance edge count: expected 15, got {edge_count}")

    # Criterion 9: MaintenanceBatch and LastInspectionYear on all rows (5 pts)
    batch_ok = all(
        v.get("MaintenanceBatch") == maintenance_batch
        and int(v.get("LastInspectionYear", 0) or 0) == last_inspection_year
        for v in flag_rows.values()
    ) if flag_rows else False
    if batch_ok:
        score += 5
        feedback.append(f"MaintenanceBatch='{maintenance_batch}' and LastInspectionYear={last_inspection_year} on all rows")
    else:
        feedback.append("MaintenanceBatch or LastInspectionYear incorrect on some rows")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
