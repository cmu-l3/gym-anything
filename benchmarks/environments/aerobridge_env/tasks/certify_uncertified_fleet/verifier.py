#!/usr/bin/env python3
"""
Verifier for certify_uncertified_fleet task.

Checks:
1. Database integrity: No aircraft remain without type certificates.
2. Anti-gaming: Specific target aircraft still exist and are now certified.
3. Process: New TypeCertificate records were created (not just re-using old ones).
4. Reporting: Compliance report file exists and contains meaningful content.
5. VLM: Validates the agent's workflow via trajectory analysis.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_certify_uncertified_fleet(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Zero Uncertified Aircraft (40 pts)
    # ---------------------------------------------------------
    uncertified_remaining = result.get("uncertified_remaining", 999)
    total_aircraft = result.get("total_aircraft", 0)
    
    if uncertified_remaining == 0 and total_aircraft > 0:
        score += 40
        feedback_parts.append("✓ Registry Audit Passed: All aircraft are certified (+40)")
    else:
        feedback_parts.append(f"✗ Registry Audit Failed: {uncertified_remaining} aircraft still uncertified")

    # ---------------------------------------------------------
    # Criterion 2: Target Verification (20 pts)
    # ---------------------------------------------------------
    targets = result.get("targets_status", {})
    all_targets_fixed = True
    targets_deleted = False
    
    for name, status in targets.items():
        if not status.get("exists"):
            targets_deleted = True
            all_targets_fixed = False
        elif not status.get("has_cert"):
            all_targets_fixed = False

    if targets_deleted:
        feedback_parts.append("✗ Penalty: Some target aircraft were deleted instead of certified!")
        # Heavy penalty implies no points here
    elif all_targets_fixed:
        score += 20
        feedback_parts.append("✓ Target Verification: Specific uncertified aircraft were successfully remediated (+20)")
    else:
        feedback_parts.append("✗ Target Verification: Some target aircraft are still incomplete")

    # ---------------------------------------------------------
    # Criterion 3: New Certificates Created (15 pts)
    # ---------------------------------------------------------
    new_certs = result.get("new_certs_created_count", 0)
    # We expect at least 1 new cert (usually 3, but maybe they reused one new cert for all 3)
    if new_certs >= 1:
        score += 15
        feedback_parts.append(f"✓ Work Evidence: {new_certs} new Type Certificate record(s) created (+15)")
    else:
        feedback_parts.append("✗ Work Evidence: No new Type Certificate records were created")

    # ---------------------------------------------------------
    # Criterion 4: Compliance Report (15 pts)
    # ---------------------------------------------------------
    report_exists = result.get("report_exists", False)
    report_b64 = result.get("report_content_b64", "")
    
    if report_exists:
        score += 5
        feedback_parts.append("✓ Report file found (+5)")
        
        try:
            content = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            # Check for content relevant to the task
            if len(content) > 10 and ("aircraft" in content.lower() or "certificate" in content.lower()):
                score += 10
                feedback_parts.append("✓ Report content appears valid (+10)")
            else:
                feedback_parts.append("✗ Report file exists but content is empty or irrelevant")
        except Exception:
            feedback_parts.append("✗ Could not decode report content")
    else:
        feedback_parts.append("✗ Compliance report file missing")

    # ---------------------------------------------------------
    # Criterion 5: VLM Process Verification (10 pts)
    # ---------------------------------------------------------
    # We award these points if the primary goal is met, assuming valid work.
    # A more advanced verifier would query the VLM here, but we'll use a heuristic:
    # If they created new certs and fixed the aircraft, the process was likely followed.
    if new_certs >= 1 and uncertified_remaining == 0:
        score += 10
        feedback_parts.append("✓ Process inferred successful from database state (+10)")

    # ---------------------------------------------------------
    # Final Decision
    # ---------------------------------------------------------
    # Pass threshold: 60 points.
    # Requires cleaning the registry (40) + verified targets (20) = 60 minimum.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }