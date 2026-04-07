#!/usr/bin/env python3
"""Verifier for update_study_parameters task."""

import json
import tempfile
import os
import logging
import sys

# Import VLM utils if available via path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """You are verifying if an AI agent successfully updated study configuration parameters in OpenClinica.
The agent was asked to update the Study Parameter Configuration for a clinical trial.

Look at these trajectory frames and the final screenshot:
1. Did the agent navigate through the "Update Study" wizard to the "Study Parameter Configuration" page?
2. Did the agent interact with form controls (dropdowns/radio buttons) such as "Collect Subject Date of Birth", "Sex Required", or "Person ID Required"?
3. Is there a confirmation/success banner indicating changes were saved?

Respond in JSON format:
{
    "wizard_navigated": true/false,
    "parameters_interacted": true/false,
    "success_confirmed": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_update_study_parameters(traj, env_info, task_info):
    """
    Verify that the study parameters were correctly updated.

    Scoring (100 points):
    - Collect Subject Date of Birth -> '2' (Only Year of Birth) : 20 pts
    - Sex Required -> False/Not Used : 15 pts
    - Person ID Required -> False/Not Used : 15 pts
    - Interviewer Name Required -> True/Yes : 15 pts
    - Interview Date Required -> True/Yes : 15 pts
    - VLM Visual Verification (bonus/trajectory proof) : up to 20 pts
    - Penalty: if DB changed but no UI interaction (audit logs) -> -30 pts

    Pass threshold: 60 points with at least 3 parameters correct.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_parameters', {
        "collect_dob": "2",
        "gender_required": ["f", "false", "0"],
        "person_id_shown_on_crf": ["f", "false", "0"],
        "interviewer_name_required": ["t", "true", "1"],
        "interview_date_required": ["t", "true", "1"]
    })

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/update_params_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch"}

    score = 0
    feedback_parts = []
    correct_params = 0

    if not result.get('study_exists', False):
        return {"passed": False, "score": 0, "feedback": "FAIL: DM-TRIAL-2024 study not found in database"}

    # Evaluate Collect DOB (20 pts)
    collect_dob = str(result.get('collect_dob', '')).strip().lower()
    if collect_dob == expected['collect_dob'] or "year" in collect_dob or "partial" in collect_dob:
        score += 20
        correct_params += 1
        feedback_parts.append("Collect DOB set correctly (+20)")
    else:
        feedback_parts.append(f"Collect DOB incorrect (got '{collect_dob}', expected '{expected['collect_dob']}')")

    # Evaluate Gender Required (15 pts)
    gender_req = str(result.get('gender_required', '')).strip().lower()
    if gender_req in expected['gender_required']:
        score += 15
        correct_params += 1
        feedback_parts.append("Sex Required set correctly (+15)")
    else:
        feedback_parts.append(f"Sex Required incorrect (got '{gender_req}')")

    # Evaluate Person ID Required (15 pts)
    person_id_req = str(result.get('person_id_shown_on_crf', '')).strip().lower()
    if person_id_req in expected['person_id_shown_on_crf']:
        score += 15
        correct_params += 1
        feedback_parts.append("Person ID Required set correctly (+15)")
    else:
        feedback_parts.append(f"Person ID Required incorrect (got '{person_id_req}')")

    # Evaluate Interviewer Name Required (15 pts)
    interviewer_name = str(result.get('interviewer_name_required', '')).strip().lower()
    if interviewer_name in expected['interviewer_name_required']:
        score += 15
        correct_params += 1
        feedback_parts.append("Interviewer Name Required set correctly (+15)")
    else:
        feedback_parts.append(f"Interviewer Name Required incorrect (got '{interviewer_name}')")

    # Evaluate Interview Date Required (15 pts)
    interview_date = str(result.get('interview_date_required', '')).strip().lower()
    if interview_date in expected['interview_date_required']:
        score += 15
        correct_params += 1
        feedback_parts.append("Interview Date Required set correctly (+15)")
    else:
        feedback_parts.append(f"Interview Date Required incorrect (got '{interview_date}')")

    # Timestamp & Anti-gaming checks
    date_updated = result.get('date_updated_epoch', 0)
    task_start = result.get('task_start_epoch', 0)
    
    # Audit log check to prevent DB injection gaming
    audit_baseline = result.get('audit_baseline', 0)
    current_audit = result.get('current_audit', 0)
    audit_diff = current_audit - audit_baseline

    if audit_diff <= 0 and correct_params > 0:
        score -= 30
        feedback_parts.append("PENALTY: No GUI audit logs detected for changes (-30)")
    elif correct_params > 0:
        feedback_parts.append(f"GUI activity confirmed ({audit_diff} audit entries)")

    if date_updated > 0 and date_updated >= task_start:
        feedback_parts.append("Study record modification timestamp verified")

    # VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm and 'gym_anything.vlm' in sys.modules:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
            
            vlm_res = query_vlm(images=frames, prompt=_build_vlm_prompt())
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('wizard_navigated'):
                    score += 10
                    feedback_parts.append("VLM: Wizard navigation confirmed (+10)")
                if parsed.get('parameters_interacted') or parsed.get('success_confirmed'):
                    score += 10
                    feedback_parts.append("VLM: Parameter interaction confirmed (+10)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Final logic
    # Base score without VLM is 80. VLM adds 20. Max score capped at 100.
    score = min(score, 100)
    passed = score >= 60 and correct_params >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "correct_params_count": correct_params,
            "audit_diff": audit_diff,
            "timestamp_valid": date_updated >= task_start
        }
    }