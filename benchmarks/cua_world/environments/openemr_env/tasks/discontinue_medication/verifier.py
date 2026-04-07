#!/usr/bin/env python3
"""
Verifier for Discontinue Medication task in OpenEMR

ROBUST MULTI-SIGNAL VERIFICATION:
1. Medication status changed to inactive (40 points)
2. Correct patient verified (20 points)
3. Correct medication targeted (15 points)
4. Discontinuation date set (10 points)
5. Reason documented with relevant keywords (10 points)
6. VLM visual confirmation (5 points)

ANTI-GAMING MEASURES:
- Timestamp check: medication must be modified DURING the task
- Correct patient check: must be pid=3 (Jayson Fadel)
- Correct medication check: must contain amLODIPine or Olmesartan

Pass threshold: 75 points with "medication discontinued" criterion met
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_discontinue_medication(traj, env_info, task_info):
    """
    Verify that the medication discontinuation task was completed correctly.
    
    Uses copy_from_env to read pre-exported verification data from container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    medication_pattern = metadata.get('medication_pattern', 'amLODIPine')
    reason_keywords = metadata.get('discontinue_reason_keywords', 
                                    ['edema', 'swelling', 'side effect', 'adverse'])
    
    # Scoring weights from metadata
    score_medication_inactive = metadata.get('score_medication_inactive', 40)
    score_correct_patient = metadata.get('score_correct_patient', 20)
    score_correct_medication = metadata.get('score_correct_medication', 15)
    score_date_set = metadata.get('score_date_set', 10)
    score_reason_documented = metadata.get('score_reason_documented', 10)
    score_visual_confirmation = metadata.get('score_visual_confirmation', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/discontinue_medication_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "medication_inactive": False,
        "correct_patient": False,
        "correct_medication": False,
        "modified_during_task": False,
        "date_set": False,
        "reason_documented": False,
        "visual_confirmation": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    baseline = result.get('baseline', {})
    current_state = result.get('current_state', {})
    verification = result.get('verification', {})
    
    medication_found = current_state.get('medication_found', False)
    drug_name = current_state.get('drug_name', '')
    active_status = str(current_state.get('active_status', '1'))
    modified_during_task = verification.get('modified_during_task', False)
    medication_discontinued = verification.get('medication_discontinued', False)
    reason_documented = verification.get('reason_documented', False)
    reason_text = verification.get('reason_text', '')
    end_date = current_state.get('end_date', '')
    
    logger.info(f"Patient PID: {patient_pid}")
    logger.info(f"Medication found: {medication_found}, Drug: {drug_name}")
    logger.info(f"Active status: {active_status}, Discontinued: {medication_discontinued}")
    logger.info(f"Modified during task: {modified_during_task}")
    
    # ================================================================
    # CRITERION 1: Correct Patient (20 points)
    # ================================================================
    if patient_pid == expected_pid:
        score += score_correct_patient
        subscores["correct_patient"] = True
        feedback_parts.append(f"Correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"WRONG PATIENT: expected pid={expected_pid}, got {patient_pid}")
        # Critical failure - wrong patient
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Task performed on wrong patient (expected pid={expected_pid})",
            "subscores": subscores
        }
    
    # ================================================================
    # CHECK: Medication exists
    # ================================================================
    if not medication_found:
        feedback_parts.append("Medication not found in database")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # ================================================================
    # CRITERION 2: Correct Medication (15 points)
    # ================================================================
    drug_name_lower = drug_name.lower()
    medication_pattern_lower = medication_pattern.lower()
    
    # Check for amLODIPine or olmesartan (components of the combo drug)
    if (medication_pattern_lower in drug_name_lower or 
        'olmesartan' in drug_name_lower or
        'hydrochlorothiazide' in drug_name_lower):
        score += score_correct_medication
        subscores["correct_medication"] = True
        feedback_parts.append(f"Correct medication targeted: {drug_name[:50]}...")
    else:
        feedback_parts.append(f"Wrong medication: expected {medication_pattern}, got {drug_name[:50]}")
    
    # ================================================================
    # CRITERION 3: Medication Status Changed to Inactive (40 points)
    # ================================================================
    # Check if medication is now inactive
    if medication_discontinued or active_status == '0':
        subscores["medication_inactive"] = True
        
        # Verify it was actually modified during the task (anti-gaming)
        if modified_during_task:
            score += score_medication_inactive
            subscores["modified_during_task"] = True
            feedback_parts.append("Medication successfully discontinued during task")
        else:
            # Medication was already inactive before task - partial credit
            score += int(score_medication_inactive * 0.3)
            feedback_parts.append("Medication inactive but may have been pre-existing state")
    else:
        feedback_parts.append(f"Medication still ACTIVE (status={active_status})")
    
    # ================================================================
    # CRITERION 4: Discontinuation Date Set (10 points)
    # ================================================================
    if end_date and end_date not in ['NULL', '', '0000-00-00', None]:
        score += score_date_set
        subscores["date_set"] = True
        feedback_parts.append(f"End date set: {end_date}")
    else:
        feedback_parts.append("No discontinuation date recorded")
    
    # ================================================================
    # CRITERION 5: Reason Documented (10 points)
    # ================================================================
    if reason_documented:
        score += score_reason_documented
        subscores["reason_documented"] = True
        feedback_parts.append(f"Discontinuation reason documented")
    else:
        # Check if any reason keywords are present in notes
        note = current_state.get('note', '').lower()
        reason_lower = reason_text.lower()
        combined_text = f"{note} {reason_lower}"
        
        for keyword in reason_keywords:
            if keyword.lower() in combined_text:
                score += int(score_reason_documented * 0.7)
                subscores["reason_documented"] = True
                feedback_parts.append(f"Reason partially documented (found: {keyword})")
                break
        else:
            feedback_parts.append("No discontinuation reason documented")
    
    # ================================================================
    # CRITERION 6: VLM Visual Confirmation (5 points)
    # ================================================================
    try:
        vlm_result = verify_via_vlm(traj, env_info)
        if vlm_result.get('success', False):
            score += score_visual_confirmation
            subscores["visual_confirmation"] = True
            feedback_parts.append("VLM confirmed medication discontinuation workflow")
        else:
            feedback_parts.append(f"VLM check: {vlm_result.get('reason', 'inconclusive')}")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification unavailable")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = (score_medication_inactive + score_correct_patient + 
                 score_correct_medication + score_date_set + 
                 score_reason_documented + score_visual_confirmation)
    
    # Determine if task passed
    # Must have: correct patient + medication actually discontinued + modified during task
    key_criteria_met = (
        subscores["correct_patient"] and 
        subscores["medication_inactive"] and
        (subscores["modified_during_task"] or subscores["date_set"])
    )
    
    passed = score >= 75 and key_criteria_met
    
    logger.info(f"Final score: {score}/{max_score}, Passed: {passed}")
    logger.info(f"Subscores: {subscores}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "medication_name": drug_name,
            "active_status": active_status,
            "discontinued": medication_discontinued,
            "modified_during_task": modified_during_task
        }
    }


def verify_via_vlm(traj, env_info) -> Dict[str, Any]:
    """
    Use VLM to verify the medication discontinuation workflow.
    
    Examines trajectory frames to confirm:
    - Agent navigated to patient's medication list
    - Agent interacted with medication record
    - Medication appears marked as discontinued/inactive
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory (not just final screenshot)
        frames = sample_trajectory_frames(traj, n=5)
        
        if not frames:
            return {"success": False, "reason": "No trajectory frames available"}
        
        # Create verification prompt
        prompt = """Analyze these screenshots from an OpenEMR (Electronic Health Records) session.

The task was to DISCONTINUE a patient's medication (specifically an antihypertensive: amLODIPine/Hydrochlorothiazide/Olmesartan).

Look for evidence of:
1. The agent navigated to a patient's chart or medication list
2. The agent opened or selected a medication record
3. The agent performed an action to discontinue/stop/deactivate the medication
4. Any confirmation or success message about medication discontinuation
5. The medication appearing as inactive, stopped, or discontinued

Respond in JSON format:
{
    "patient_chart_visible": true/false,
    "medication_list_visible": true/false,
    "discontinue_action_observed": true/false,
    "medication_marked_inactive": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observed"
}
"""
        
        result = query_vlm(images=frames, prompt=prompt)
        
        if result:
            try:
                # Parse JSON from VLM response
                import re
                json_match = re.search(r'\{[^{}]*\}', result, re.DOTALL)
                if json_match:
                    vlm_data = json.loads(json_match.group())
                    
                    # Determine success based on VLM observations
                    success = (
                        vlm_data.get('medication_list_visible', False) and
                        (vlm_data.get('discontinue_action_observed', False) or
                         vlm_data.get('medication_marked_inactive', False))
                    )
                    
                    return {
                        "success": success,
                        "confidence": vlm_data.get('confidence', 'low'),
                        "reason": vlm_data.get('observations', 'No observations')
                    }
            except json.JSONDecodeError:
                pass
        
        return {"success": False, "reason": "Could not parse VLM response"}
        
    except ImportError:
        return {"success": False, "reason": "VLM utilities not available"}
    except Exception as e:
        return {"success": False, "reason": f"VLM error: {str(e)}"}