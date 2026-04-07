#!/usr/bin/env python3
"""Verifier for remediate_misallocated_clinical_data task."""

import json
import tempfile
import os
import logging
import sys

# Framework imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    sample_trajectory_frames = None
    get_final_screenshot = None

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    return """You are evaluating an agent's completion of a clinical data correction task in OpenClinica.
The agent was asked to delete a misallocated event on one subject and schedule/enter it on another.

Look at these trajectory frames and determine:
1. Is the OpenClinica web interface visible?
2. Is there evidence that the agent navigated to the Subject Matrix or viewed subject records?
3. Is there evidence of data entry (a CRF form, scheduling screen, or success confirmation)?
4. Did the agent successfully interact with the GUI to perform these updates?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "subject_matrix_used": true/false,
    "data_entry_or_success_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_remediation(traj, env_info, task_info):
    """
    Verify the remediation of misallocated clinical data.
    
    Scoring Strategy (100 points):
    1. DM-103 Week 4 Event CRF removed (no row or status=5/7) (30 pts)
    2. DM-102 Week 4 Event exists (15 pts)
    3. DM-102 Event Date is 2024-03-10 (5 pts)
    4. DM-102 Vital Signs item_data entered correctly (30 pts)
    5. Audit log ensures GUI interaction (10 pts)
    6. VLM trajectory check confirms workflow (10 pts)
    
    Pass Threshold: 70
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/remediate_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity verification
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

    if expected_nonce and result.get('result_nonce', '') != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Nonce mismatch"}

    score = 0
    feedback_parts = []
    
    # 1. Evaluate DM-103 Removal (30 pts)
    # Row deleted completely (exists=False) OR row status is removed (5/7) OR event status is removed/stopped (5/6/7)
    dm103_exists = result.get('dm103_event_exists', False)
    dm103_status = result.get('dm103_status_id', 0)
    dm103_ev_status = result.get('dm103_subject_event_status_id', 0)
    
    if not dm103_exists or dm103_status in [5, 7] or dm103_ev_status in [5, 6, 7]:
        score += 30
        feedback_parts.append("DM-103 data successfully removed (+30)")
    else:
        feedback_parts.append(f"FAIL: DM-103 data still active (row status {dm103_status}, event status {dm103_ev_status}) (0/30)")

    # 2. Evaluate DM-102 Existence (15 pts)
    if result.get('dm102_event_exists', False):
        score += 15
        feedback_parts.append("DM-102 Week 4 event created (+15)")
        
        # 3. Evaluate DM-102 Date (5 pts)
        date_val = result.get('dm102_start_date', '')
        if '2024-03-10' in date_val:
            score += 5
            feedback_parts.append("DM-102 event date correct (+5)")
        else:
            feedback_parts.append(f"DM-102 date incorrect: '{date_val}' (expected 2024-03-10)")
            
        # 4. Evaluate DM-102 Item Data Values (30 pts)
        expected_values = task_info.get('metadata', {}).get('expected_values', [142.0, 88.0, 76.0, 37.1, 84.5])
        found_values_str = result.get('dm102_item_values', '')
        found_values = [v.strip() for v in found_values_str.split(',') if v.strip()]
        
        matched_count = 0
        for exp in expected_values:
            for f in found_values:
                try:
                    if abs(float(exp) - float(f)) < 0.01:
                        matched_count += 1
                        break
                except ValueError:
                    pass
        
        val_score = int((matched_count / len(expected_values)) * 30)
        score += val_score
        feedback_parts.append(f"Data entry values matched: {matched_count}/{len(expected_values)} (+{val_score})")
    else:
        feedback_parts.append("FAIL: DM-102 Week 4 event not created (0/50 for schedule/entry)")

    # 5. Audit Log GUI verification (10 pts)
    audit_count = result.get('audit_log_count', 0)
    audit_base = result.get('audit_baseline_count', 0)
    if audit_count > audit_base:
        score += 10
        feedback_parts.append("Audit log confirms GUI activity (+10)")
    else:
        feedback_parts.append("WARNING: No new audit logs detected. Potential GUI bypass.")
        score -= 20 # Severe penalty for direct DB edits

    # 6. VLM Trajectory check (10 pts)
    if query_vlm and sample_trajectory_frames and get_final_screenshot:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            frames.append(get_final_screenshot(traj))
            # filter out Nones
            frames = [f for f in frames if f]
            
            if frames:
                vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('openclinica_visible') and parsed.get('subject_matrix_used'):
                        score += 10
                        feedback_parts.append("VLM confirms UI interaction (+10)")
                    else:
                        feedback_parts.append("VLM did not detect correct UI screens (0/10)")
                else:
                    feedback_parts.append("VLM query failed during verification")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped due to framework error")
    
    # Cap score
    score = max(0, min(100, score))
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }