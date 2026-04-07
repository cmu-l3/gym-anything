#!/usr/bin/env python3
"""
Verifier for sakila_schema_drift_remediation task.

Checks:
1. Schema drifts reverted to match Gold standard.
2. Live transaction data preserved (ensures ALTER used, not DROP/CREATE).
3. Synchronization script generated.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_sakila_schema_drift_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Data Preservation (Critical Anti-Gaming)
    # If this is false, they likely dropped the DB. 
    # We penalize heavily or fail, but let's stick to the scoring rubric.
    if result.get("live_data_preserved", False):
        score += 20
        feedback.append("Live transaction data preserved (20/20)")
    else:
        feedback.append("CRITICAL: Live data missing! Database likely dropped/recreated instead of altered. (0/20)")

    # 2. Verify Customer Column Fix
    # Gold: varchar(45). Drift: varchar(100).
    actual_type = result.get("customer_col_type", "").lower()
    if "varchar(45)" in actual_type:
        score += 20
        feedback.append("Customer table structure repaired (20/20)")
    elif "varchar(100)" in actual_type:
        feedback.append("Customer table still drifted [varchar(100)] (0/20)")
    else:
        feedback.append(f"Customer table state unknown: {actual_type} (0/20)")

    # 3. Verify Address Index Fix
    # Gold: idx exists. Drift: missing.
    if result.get("address_idx_count", 0) > 0:
        score += 20
        feedback.append("Address index restored (20/20)")
    else:
        feedback.append("Address index still missing (0/20)")

    # 4. Verify Store Column Fix
    # Gold: no internal_notes. Drift: has internal_notes.
    if result.get("store_col_count", 1) == 0:
        score += 20
        feedback.append("Store table extra column removed (20/20)")
    else:
        feedback.append("Store table still has unauthorized column (0/20)")

    # 5. Verify View Definition
    # Gold: has country. Drift: missing country.
    if result.get("view_has_country", 0) > 0:
        score += 10
        feedback.append("Customer list view repaired (10/10)")
    else:
        feedback.append("Customer list view still incorrect (0/10)")

    # 6. Verify Script Artifact
    script_exists = result.get("script_exists", False)
    task_start = result.get("task_start", 0)
    file_mtime = result.get("file_mtime", 0)
    
    if script_exists and file_mtime > task_start:
        score += 10
        feedback.append("Remediation script generated (10/10)")
    elif script_exists:
        # Exists but old? Unlikely given setup deletes it, but logic covers it.
        score += 5
        feedback.append("Script file exists but timestamp is suspicious (5/10)")
    else:
        feedback.append("Remediation script file not found (0/10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }