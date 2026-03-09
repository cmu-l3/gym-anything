#!/usr/bin/env python3
"""
Verifier for airport_schema_normalization task.

Scoring (100 points):
- DBeaver 'Airports' connection exists: 10 pts
- 'countries' table created with correct count: 20 pts
- 'timezones' table created with correct count: 15 pts
- 'airports' table created, data migrated (count matches original): 25 pts
- normalization_report.txt exists at correct path with required fields: 20 pts
- Report MIGRATION_VALID = YES: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

REPORT_PATH = "/home/ga/Documents/exports/normalization_report.txt"


def verify_airport_schema_normalization(traj, env_info, task_info):
    """Verify airport schema normalization task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/airport_schema_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    score = 0
    feedback = []
    subscores = {}

    gt_original = result.get("gt_original_count", 7000)
    gt_countries = result.get("gt_country_count", 230)
    gt_timezones = result.get("gt_tz_count", 400)

    # --- Criterion 1: DBeaver 'Airports' connection (10 pts) ---
    if result.get("airports_conn_found"):
        score += 10
        subscores["connection"] = 10
        feedback.append("'Airports' DBeaver connection found")
    else:
        subscores["connection"] = 0
        feedback.append("MISSING: DBeaver 'Airports' connection not found")

    # --- Criterion 2: 'countries' table created with correct count (20 pts) ---
    if result.get("countries_table_exists"):
        countries_count = result.get("countries_count", 0)
        if gt_countries > 0:
            pct_diff = abs(countries_count - gt_countries) / gt_countries
            if pct_diff <= 0.10:
                score += 20
                subscores["countries_table"] = 20
                feedback.append(f"'countries' table has {countries_count} rows (GT: {gt_countries})")
            elif pct_diff <= 0.30:
                score += 12
                subscores["countries_table"] = 12
                feedback.append(f"'countries' table exists with {countries_count} rows (GT: {gt_countries}, diff {pct_diff*100:.0f}%)")
            else:
                score += 6
                subscores["countries_table"] = 6
                feedback.append(f"'countries' table exists but count {countries_count} far from GT {gt_countries}")
        elif countries_count > 100:
            score += 16
            subscores["countries_table"] = 16
            feedback.append(f"'countries' table has {countries_count} rows (GT unavailable)")
        else:
            score += 5
            subscores["countries_table"] = 5
            feedback.append(f"'countries' table exists but appears empty ({countries_count} rows)")
    else:
        subscores["countries_table"] = 0
        feedback.append("MISSING: 'countries' table not found in database")

    # --- Criterion 3: 'timezones' table created with correct count (15 pts) ---
    if result.get("timezones_table_exists"):
        tz_count = result.get("timezones_count", 0)
        if gt_timezones > 0:
            pct_diff = abs(tz_count - gt_timezones) / gt_timezones
            if pct_diff <= 0.15:
                score += 15
                subscores["timezones_table"] = 15
                feedback.append(f"'timezones' table has {tz_count} rows (GT: {gt_timezones})")
            elif pct_diff <= 0.40:
                score += 9
                subscores["timezones_table"] = 9
                feedback.append(f"'timezones' table exists with {tz_count} rows (GT: {gt_timezones})")
            else:
                score += 5
                subscores["timezones_table"] = 5
                feedback.append(f"'timezones' table exists but count {tz_count} far from GT {gt_timezones}")
        elif tz_count > 50:
            score += 12
            subscores["timezones_table"] = 12
            feedback.append(f"'timezones' table has {tz_count} rows (GT unavailable)")
        else:
            score += 4
            subscores["timezones_table"] = 4
            feedback.append(f"'timezones' table exists but appears minimal ({tz_count} rows)")
    else:
        subscores["timezones_table"] = 0
        feedback.append("MISSING: 'timezones' table not found in database")

    # --- Criterion 4: 'airports' table created and data migrated (25 pts) ---
    if result.get("airports_table_exists"):
        airports_count = result.get("airports_table_count", 0)
        raw_count = result.get("airports_raw_count", gt_original)

        if raw_count > 0 and airports_count > 0:
            pct_diff = abs(airports_count - raw_count) / raw_count
            if pct_diff <= 0.02:  # within 2% = essentially complete migration
                score += 25
                subscores["airports_migrated"] = 25
                feedback.append(f"'airports' table fully migrated: {airports_count}/{raw_count} rows")
            elif pct_diff <= 0.10:
                score += 18
                subscores["airports_migrated"] = 18
                feedback.append(f"'airports' table mostly migrated: {airports_count}/{raw_count} rows")
            elif airports_count > raw_count * 0.5:
                score += 10
                subscores["airports_migrated"] = 10
                feedback.append(f"'airports' table partially migrated: {airports_count}/{raw_count} rows")
            else:
                score += 5
                subscores["airports_migrated"] = 5
                feedback.append(f"'airports' table created but minimal data: {airports_count}/{raw_count}")
        elif airports_count > 0:
            score += 12
            subscores["airports_migrated"] = 12
            feedback.append(f"'airports' table has {airports_count} rows (original count unavailable)")
        else:
            score += 5
            subscores["airports_migrated"] = 5
            feedback.append("'airports' table created but empty")
    else:
        subscores["airports_migrated"] = 0
        feedback.append("MISSING: 'airports' table not found in database")

    # --- Criterion 5: Report file exists with required fields (20 pts) ---
    if result.get("report_exists"):
        fields_present = sum([
            result.get("report_has_original", False),
            result.get("report_has_airports", False),
            result.get("report_has_countries", False),
            result.get("report_has_timezones", False)
        ])
        if fields_present == 4:
            score += 20
            subscores["report_content"] = 20
            feedback.append(f"Report has all 4 required fields")
        elif fields_present >= 2:
            pts = int(20 * fields_present / 4)
            score += pts
            subscores["report_content"] = pts
            feedback.append(f"Report has {fields_present}/4 required fields")
        else:
            score += 5
            subscores["report_content"] = 5
            feedback.append(f"Report exists but missing required fields ({fields_present}/4)")

        if not result.get("report_created_after_start"):
            feedback.append("Warning: report may be pre-existing (timestamp check)")
    else:
        subscores["report_content"] = 0
        feedback.append(f"MISSING: normalization_report.txt not found at {REPORT_PATH}")

    # --- Criterion 6: Report says MIGRATION_VALID = YES (10 pts) ---
    if result.get("report_migration_valid"):
        score += 10
        subscores["migration_valid"] = 10
        feedback.append("Report confirms MIGRATION_VALID: YES")
    else:
        subscores["migration_valid"] = 0
        if result.get("report_exists"):
            feedback.append("Report does not confirm MIGRATION_VALID = YES")
        else:
            feedback.append("Report missing — cannot check MIGRATION_VALID")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "countries_count": result.get("countries_count"),
            "timezones_count": result.get("timezones_count"),
            "airports_table_count": result.get("airports_table_count"),
            "airports_raw_count": result.get("airports_raw_count"),
            "gt_original": gt_original
        }
    }
