#!/usr/bin/env python3
"""
Verifier for targeted_lepc_portfolio_export task.

Verification Strategy:
1. Ensure the output .t2s file was created.
2. Programmatically open the exported SQLite database.
3. Check for TARGET facility ("Columbus").
4. Check absence of DISTRACTOR 1 ("Cleveland" - wrong county).
5. Check absence of DISTRACTOR 2 ("Dublin" - wrong chemical).

Scoring (100 points total, Pass threshold: 80):
- 10 pts: Export file created.
- 30 pts: Target facility successfully exported.
- 30 pts: Distractor 1 successfully excluded.
- 30 pts: Distractor 2 successfully excluded.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_targeted_lepc_export(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\targeted_lepc_export_result.json")
    pass_threshold = metadata.get("pass_threshold", 80)

    # Copy the exported result JSON from the container
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found or could not be parsed: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Exported .t2s file not found at expected location (Do-nothing detected)."
        }

    if result.get("error"):
        return {
            "passed": False,
            "score": 10,
            "feedback": f"FAIL: File created but encountered error parsing contents: {result.get('error')}"
        }

    score = 10  # Base points for creating the valid file
    feedback_parts = ["PASS: Export file successfully created (+10)"]

    columbus = result.get("columbus_found", False)
    cleveland = result.get("cleveland_found", False)
    dublin = result.get("dublin_found", False)

    # 1. Check Target Facility (Columbus DC)
    if columbus:
        score += 30
        feedback_parts.append("PASS: Target Facility 'Columbus DC' included in export (+30)")
    else:
        feedback_parts.append("FAIL: Target Facility 'Columbus DC' missing from export")

    # 2. Check Distractor 1 (Cleveland DC - Wrong County)
    if not cleveland:
        score += 30
        feedback_parts.append("PASS: Distractor 'Cleveland DC' correctly excluded (Jurisdiction filter) (+30)")
    else:
        feedback_parts.append("FAIL: Distractor 'Cleveland DC' incorrectly included (Failed County filter)")

    # 3. Check Distractor 2 (Dublin DC - Wrong Chemical)
    if not dublin:
        score += 30
        feedback_parts.append("PASS: Distractor 'Dublin DC' correctly excluded (Hazard filter) (+30)")
    else:
        feedback_parts.append("FAIL: Distractor 'Dublin DC' incorrectly included (Failed Chemical filter)")

    passed = score >= pass_threshold

    # Special logic: If they exported none of them, it might be an empty file.
    if not columbus and not cleveland and not dublin:
        passed = False
        feedback_parts.append("CRITICAL: The exported file appears to be completely empty of facility data.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }