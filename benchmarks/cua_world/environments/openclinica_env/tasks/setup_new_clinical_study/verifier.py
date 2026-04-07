#!/usr/bin/env python3
"""Verifier for setup_new_clinical_study task."""

import json
import tempfile
import os
import logging
import sys

# Import VLM utils
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    return """Examine these screenshots from a session using OpenClinica (a clinical trial management system).

Check if the user was performing the initialization of a new clinical study. Look for:
1. "Build Study" or "Create Study" interfaces.
2. Form fields being filled out with titles like "Healthy Volunteer PK Study" or "PK-HV-001".
3. Interfaces for adding "Study Event Definitions" (like Dosing Visit or Safety Follow-up).
4. Interfaces for "Assign Users" or user role management.

Did the agent actively navigate through the study creation or configuration screens?

Respond in JSON format:
{
    "study_creation_ui_visible": true/false,
    "event_definition_ui_visible": true/false,
    "user_assignment_ui_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_new_clinical_study(traj, env_info, task_info):
    """
    Verify setup_new_clinical_study task completion.

    Scoring (100 points total):
    - Study Created (30 pts): PK-HV-001 exists with ID > baseline, checks Name/PI/Sponsor.
    - Event 1 (20 pts): 'Dosing Visit' exists, Scheduled, non-repeating.
    - Event 2 (20 pts): 'Safety Follow-up' exists, Unscheduled, repeating.
    - Role Assigned (20 pts): 'mrivera' has 'investigator' role in this new study.
    - VLM Verification (10 pts): Trajectory shows study creation workflow.
    - Anti-gaming: -30 pts if no audit log entries (DB injection detected).

    Pass threshold: 70 points AND Study Creation criterion must pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Load result file ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/setup_study_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Verify result integrity via nonce ---
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
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering",
        }

    score = 0
    feedback_parts = []
    study_passed = False

    # --- Criterion 1: Study Creation (30 pts) ---
    study_exists = result.get('study_exists', False)
    study_id = int(result.get('study_id', 0))
    baseline_max = int(result.get('baseline_max_study_id', 0))

    if study_exists and study_id > baseline_max:
        study_passed = True
        study_score = 15 # Base points for creating it
        
        name = result.get('study_name', '').lower()
        pi = result.get('study_pi', '').lower()
        sponsor = result.get('study_sponsor', '').lower()
        
        if 'healthy volunteer' in name or 'pk study' in name:
            study_score += 5
        if 'grant' in pi or 'alan' in pi:
            study_score += 5
        if 'ingen' in sponsor:
            study_score += 5
            
        score += study_score
        feedback_parts.append(f"Study created successfully ({study_score}/30 pts)")
    elif study_exists:
        feedback_parts.append("FAIL: Study PK-HV-001 exists, but was not newly created (ID <= baseline) (0/30 pts)")
    else:
        feedback_parts.append("FAIL: Study PK-HV-001 was not created (0/30 pts)")

    # --- Criterion 2: Dosing Visit Event (20 pts) ---
    if result.get('event1_exists', False):
        ev1_score = 10
        type1 = result.get('event1_type', '').lower()
        rep1 = result.get('event1_repeating', '').lower()
        
        if type1 == 'scheduled':
            ev1_score += 5
        if rep1 in ['false', 'f', '0', 'no']:
            ev1_score += 5
            
        score += ev1_score
        feedback_parts.append(f"Dosing Visit event configured ({ev1_score}/20 pts)")
    else:
        feedback_parts.append("FAIL: Dosing Visit event not found (0/20 pts)")

    # --- Criterion 3: Safety Follow-up Event (20 pts) ---
    if result.get('event2_exists', False):
        ev2_score = 10
        type2 = result.get('event2_type', '').lower()
        rep2 = result.get('event2_repeating', '').lower()
        
        if type2 == 'unscheduled':
            ev2_score += 5
        if rep2 in ['true', 't', '1', 'yes']:
            ev2_score += 5
            
        score += ev2_score
        feedback_parts.append(f"Safety Follow-up event configured ({ev2_score}/20 pts)")
    else:
        feedback_parts.append("FAIL: Safety Follow-up event not found (0/20 pts)")

    # --- Criterion 4: User Role Assignment (20 pts) ---
    if result.get('role_exists', False):
        role_name = result.get('role_name', '').lower()
        if 'investigator' in role_name:
            score += 20
            feedback_parts.append("mrivera assigned Investigator role (20/20 pts)")
        else:
            score += 10
            feedback_parts.append(f"mrivera assigned wrong role '{role_name}' (10/20 pts)")
    else:
        feedback_parts.append("FAIL: mrivera role not assigned to new study (0/20 pts)")

    # --- Criterion 5: VLM Trajectory Verification (10 pts) ---
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            vlm_result = query_vlm(images=frames, prompt=_build_vlm_prompt())
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("study_creation_ui_visible", False):
                    vlm_score += 5
                if parsed.get("event_definition_ui_visible", False) or parsed.get("user_assignment_ui_visible", False):
                    vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM Visual Verification ({vlm_score}/10 pts)")
            else:
                feedback_parts.append("VLM query failed, skipped visual bonus")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped due to error")

    # --- Anti-Gaming: Audit Log Penalty ---
    audit_count = int(result.get('audit_log_count', 0))
    audit_baseline = int(result.get('audit_baseline_count', 0))
    if audit_count <= audit_baseline and study_passed:
        score -= 30
        feedback_parts.append("PENALTY: No GUI audit logs detected. Potential direct database injection (-30 pts)")

    # --- Final calculation ---
    # Must pass the core component (creating the study)
    passed = (score >= 70) and study_passed
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": "\n".join(feedback_parts)
    }