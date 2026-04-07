#!/usr/bin/env python3
"""Verifier for double_data_entry_workflow task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _safe_int(value, default=0):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default

def verify_double_data_entry_workflow(traj, env_info, task_info):
    """
    Verify Double Data Entry (DDE) workflow completion.
    
    Scoring Criteria (100 points):
    1. CRF uploaded & exists: 15 pts
    2. DDE Configured (Double Data Entry matrix flag checked): 20 pts
    3. Event Scheduled for DM-101: 10 pts
    4. Valid Initial Entry: event_crf has owner mapping to dep1 or dep2: 20 pts
    5. Valid Double Entry: event_crf is Complete (status=2) AND updater != owner: 20 pts
    6. Data Accuracy: Item values '120' and '80' exist in the record: 15 pts
    
    Pass threshold: 75 points + Valid Double Entry met.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/double_data_entry_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify nonce
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch"}

    score = 0
    feedback_parts = []
    
    # Check Audit Log Bypass
    audit_current = _safe_int(result.get('audit_current', 0))
    audit_baseline = _safe_int(result.get('audit_baseline', 0))
    if audit_current <= audit_baseline:
        return {"passed": False, "score": 0, "feedback": "FAIL: No GUI interaction detected via audit logs (Possible direct DB injection)."}

    # Criterion 1: CRF Exists (15 pts)
    crf_exists = result.get('crf_exists', False)
    if crf_exists:
        score += 15
        feedback_parts.append("Vital Signs CRF uploaded successfully (+15)")
    else:
        feedback_parts.append("FAIL: Vital Signs CRF not found in database (0/15)")

    # Criterion 2: DDE Enabled (20 pts)
    dde_enabled = result.get('dde_enabled', False)
    if dde_enabled:
        score += 20
        feedback_parts.append("Double Data Entry matrix flag enabled (+20)")
    else:
        feedback_parts.append("FAIL: DDE matrix flag not checked (0/20)")

    # Criterion 3: Event Scheduled (10 pts)
    event_scheduled = result.get('event_scheduled', False)
    if event_scheduled:
        score += 10
        feedback_parts.append("Baseline Assessment scheduled for DM-101 (+10)")
    else:
        feedback_parts.append("FAIL: Event not scheduled for DM-101 (0/10)")

    # Status parsing
    status_id = _safe_int(result.get('status_id', 0))
    owner = result.get('owner_name', '').strip()
    updater = result.get('updater_name', '').strip()
    valid_users = ['dep1', 'dep2']
    
    # Criterion 4: Valid Initial Entry (20 pts)
    initial_entry_valid = False
    if owner in valid_users:
        initial_entry_valid = True
        score += 20
        feedback_parts.append(f"Initial entry performed correctly by valid user '{owner}' (+20)")
    elif owner == "root":
        feedback_parts.append("FAIL: Initial entry performed by root instead of dep1/dep2 (0/20)")
    elif owner:
        feedback_parts.append(f"FAIL: Initial entry performed by unknown user '{owner}' (0/20)")
    else:
        feedback_parts.append("FAIL: No data entry started (0/20)")

    # Criterion 5: Valid Double Entry (20 pts)
    # Status 2 = Data Entry Complete. For DDE, this requires the second pass.
    double_entry_valid = False
    if status_id == 2:
        if updater in valid_users and updater != owner:
            double_entry_valid = True
            score += 20
            feedback_parts.append(f"Double entry completed correctly by second user '{updater}' (+20)")
        elif updater == owner:
            feedback_parts.append(f"FAIL: Form completed by the same user '{owner}' who started it, bypassing DDE multi-user intent (0/20)")
        elif updater == "root":
            feedback_parts.append("FAIL: Form completed by root instead of the designated data entry persons (0/20)")
        else:
            feedback_parts.append(f"FAIL: Form completed, but updater '{updater}' is not a valid verification user (0/20)")
    elif status_id == 4:
        feedback_parts.append("PARTIAL: Initial Data Entry Complete, but second verification pass not completed (0/20)")
    elif status_id == 1:
        feedback_parts.append("PARTIAL: Data Entry Started, but not completed (0/20)")

    # Criterion 6: Data Accuracy (15 pts)
    item_values = result.get('item_values', '')
    if '120' in item_values and '80' in item_values:
        score += 15
        feedback_parts.append("Target Vital Signs data (120/80) correctly recorded (+15)")
    elif '120' in item_values or '80' in item_values:
        score += 7
        feedback_parts.append(f"PARTIAL: Only partial target values found. Recorded: {item_values} (7/15)")
    else:
        feedback_parts.append(f"FAIL: Target values not found in database. Recorded: {item_values} (0/15)")

    # VLM verification (Bonus points up to +10 if they show good trajectory)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        prompt = """You are evaluating a clinical data manager AI.
The AI was supposed to complete a Double Data Entry workflow in OpenClinica.
1. Did the agent navigate through OpenClinica?
2. Are there indications of logging in as different users (dep1/dep2) or viewing subject matrices?
Respond in JSON: {"navigated_openclinica": true/false, "multi_user_evidence": true/false}
"""
        images = frames + [final] if final else frames
        if images:
            try:
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("navigated_openclinica"):
                        score = min(100, score + 5)
                        feedback_parts.append("VLM Bonus: Trajectory shows OpenClinica navigation (+5)")
                    if parsed.get("multi_user_evidence"):
                        score = min(100, score + 5)
                        feedback_parts.append("VLM Bonus: Trajectory shows evidence of multi-user workflow (+5)")
            except Exception as e:
                logger.warning(f"VLM bonus check failed: {e}")

    passed = (score >= 75) and double_entry_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }