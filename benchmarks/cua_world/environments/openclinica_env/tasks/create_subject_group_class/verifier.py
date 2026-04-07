#!/usr/bin/env python3
"""Verifier for create_subject_group_class task."""

import json
import tempfile
import os
import logging
import sys

logger = logging.getLogger(__name__)

def verify_create_subject_group_class(traj, env_info, task_info):
    """
    Verify the agent correctly created the Subject Group Class and associated groups in OpenClinica.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_subject_group_class_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce against setup
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {
            "passed": False,
            "score": 0,
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering"
        }

    score = 0
    feedback_parts = []

    # 1. Class exists with correct name (20 pts)
    class_exists = result.get('class_exists', False)
    class_name = result.get('class_name', '')
    if class_exists and class_name.strip() == "Treatment Arm":
        score += 20
        feedback_parts.append("Class 'Treatment Arm' exists (+20)")
    else:
        feedback_parts.append("FAIL: Class 'Treatment Arm' not found (0/20)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Correct type (Arm) = 1 (10 pts)
    class_type_id = result.get('class_type_id', '')
    if str(class_type_id).strip() == "1":
        score += 10
        feedback_parts.append("Class type is Arm (+10)")
    else:
        feedback_parts.append(f"Class type is incorrect, expected Arm (id 1), got {class_type_id} (0/10)")

    # 3. Linked to correct study (10 pts)
    # The SQL query explicitly searched WHERE study_id corresponds to DM-TRIAL-2024
    score += 10
    feedback_parts.append("Class correctly linked to DM-TRIAL-2024 (+10)")

    # 4. Groups verification (45 pts total)
    groups = result.get('groups', [])
    expected_groups = ["metformin 500mg", "metformin 1000mg", "placebo"]
    
    found_groups = set()
    groups_with_desc = 0

    for g in groups:
        g_name = g.get('name', '').strip().lower()
        if g_name in expected_groups:
            if g_name not in found_groups:
                found_groups.add(g_name)
                score += 15
                feedback_parts.append(f"Group '{g.get('name')}' exists (+15)")
                
                # Validation for Descriptions
                if g.get('description', '').strip():
                    groups_with_desc += 1
            
    for missing in [eg for eg in expected_groups if eg not in found_groups]:
        feedback_parts.append(f"FAIL: Expected group '{missing}' not found (0/15)")

    # 5. Groups have descriptions (10 pts)
    if len(found_groups) > 0 and groups_with_desc == len(found_groups):
        score += 10
        feedback_parts.append("All expected groups have descriptions (+10)")
    elif groups_with_desc > 0:
        score += 5
        feedback_parts.append("Some groups have descriptions (+5)")
    else:
        feedback_parts.append("No descriptions provided for groups (0/10)")

    # 6. Anti-gaming check via class/group count deltas (5 pts)
    initial_class_count = int(result.get('initial_class_count', 0))
    current_class_count = int(result.get('current_class_count', 0))
    if current_class_count > initial_class_count:
        score += 5
        feedback_parts.append("New record count increment confirmed (+5)")
    else:
        feedback_parts.append("WARNING: Total class count did not increase")

    # 7. Audit log penalty
    audit_current = int(result.get('audit_log_count', 0))
    audit_baseline = int(result.get('audit_baseline_count', 0))
    if audit_current <= audit_baseline and audit_baseline != 0:
        score -= 20
        feedback_parts.append("PENALTY: No GUI interaction detected via audit logs (-20)")

    # Ensure class was created and at least 2 of 3 arms were present
    passed = score >= 60 and class_exists and len(found_groups) >= 2

    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }