#!/usr/bin/env python3
"""
Verifier for Record Social History task in OpenEMR

MULTI-SIGNAL VERIFICATION:
1. Patient found (correct patient pid=3): 10 points
2. History section accessed and modified: 15 points
3. Smoking status documented as former smoker: 25 points
4. Quit date recorded (2018-06-15): 15 points
5. Alcohol use documented: 10 points
6. Occupation documented (Software Developer): 10 points
7. Record saved (changes persisted): 15 points

BONUS via VLM trajectory verification for workflow confirmation.

Pass threshold: 70 points with smoking_status required
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_record_social_history(traj, env_info, task_info):
    """
    Verify that social history was documented correctly for the patient.
    
    Uses copy_from_env to read exported result JSON from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_smoking = metadata.get('expected_smoking_status', 'former').lower()
    expected_quit_date = metadata.get('expected_quit_date', '2018-06-15')
    expected_alcohol = metadata.get('expected_alcohol', 'social').lower()
    expected_occupation = metadata.get('expected_occupation', 'software developer').lower()
    
    # Score weights from metadata
    score_patient = metadata.get('score_patient_found', 10)
    score_history = metadata.get('score_history_accessed', 15)
    score_smoking = metadata.get('score_smoking_status', 25)
    score_quit = metadata.get('score_quit_date', 15)
    score_alcohol = metadata.get('score_alcohol', 10)
    score_occupation = metadata.get('score_occupation', 10)
    score_saved = metadata.get('score_record_saved', 15)
    
    max_score = score_patient + score_history + score_smoking + score_quit + score_alcohol + score_occupation + score_saved
    
    # Read exported result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/social_history_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    score = 0
    feedback_parts = []
    subscores = {
        "patient_correct": False,
        "history_accessed": False,
        "smoking_status": False,
        "quit_date": False,
        "alcohol": False,
        "occupation": False,
        "record_saved": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    history_record = result.get('history_record', {})
    validation = result.get('validation', {})
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    
    logger.info(f"Verifying social history for patient pid={patient_pid}")
    logger.info(f"History record: {history_record}")
    logger.info(f"Validation flags: {validation}")
    
    # ================================================================
    # CRITERION 1: Correct patient (10 points)
    # ================================================================
    if patient_pid == expected_pid:
        score += score_patient
        subscores["patient_correct"] = True
        feedback_parts.append(f"Correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"Wrong patient: expected pid={expected_pid}, got {patient_pid}")
        # Critical failure - wrong patient
        return {
            "passed": False,
            "score": 0,
            "feedback": "Social history documented for wrong patient",
            "subscores": subscores
        }
    
    # ================================================================
    # CRITERION 2: History record was modified (15 points)
    # ================================================================
    history_modified = validation.get('history_modified_during_task', False)
    tobacco_value = history_record.get('tobacco', '')
    
    if history_modified and tobacco_value:
        score += score_history
        subscores["history_accessed"] = True
        feedback_parts.append("History section accessed and modified")
    elif tobacco_value:
        # Give partial credit if tobacco is populated but we couldn't verify timing
        score += score_history // 2
        feedback_parts.append("History has tobacco data (timing unverified)")
    else:
        feedback_parts.append("No history modifications detected")
    
    # ================================================================
    # CRITERION 3: Smoking status documented as former smoker (25 points)
    # This is the KEY criterion for this task
    # ================================================================
    smoking_valid = validation.get('smoking_status_valid', False)
    
    if smoking_valid:
        score += score_smoking
        subscores["smoking_status"] = True
        feedback_parts.append("Smoking status: Former smoker documented ✓")
    else:
        # Check the actual tobacco field for former smoker keywords
        tobacco_lower = tobacco_value.lower() if tobacco_value else ""
        former_keywords = ['former', 'quit', 'ex-', 'past', 'stopped', 'no longer', 'used to', 'previously']
        
        if any(kw in tobacco_lower for kw in former_keywords):
            score += score_smoking
            subscores["smoking_status"] = True
            feedback_parts.append(f"Smoking status indicates former smoker: '{tobacco_value[:50]}...'")
        elif tobacco_value:
            # Partial credit for documenting something about tobacco
            score += score_smoking // 3
            feedback_parts.append(f"Tobacco documented but not as former smoker: '{tobacco_value[:50]}...'")
        else:
            feedback_parts.append("Smoking status NOT documented")
    
    # ================================================================
    # CRITERION 4: Quit date recorded (15 points)
    # ================================================================
    quit_date_valid = validation.get('quit_date_valid', False)
    
    if quit_date_valid:
        score += score_quit
        subscores["quit_date"] = True
        feedback_parts.append(f"Quit date documented (2018)")
    else:
        # Check for quit date in tobacco or counseling fields
        all_text = f"{tobacco_value} {history_record.get('counseling', '')}".lower()
        
        # Look for various date formats
        if '2018' in all_text and ('06' in all_text or 'jun' in all_text or '15' in all_text):
            score += score_quit
            subscores["quit_date"] = True
            feedback_parts.append("Quit date 2018-06-15 found in record")
        elif '2018' in all_text:
            # Partial credit for year
            score += score_quit // 2
            feedback_parts.append("Quit year 2018 documented (date incomplete)")
        else:
            feedback_parts.append("Quit date NOT documented")
    
    # ================================================================
    # CRITERION 5: Alcohol use documented (10 points)
    # ================================================================
    alcohol_valid = validation.get('alcohol_valid', False)
    alcohol_value = history_record.get('alcohol', '')
    
    if alcohol_valid:
        score += score_alcohol
        subscores["alcohol"] = True
        feedback_parts.append("Alcohol use documented appropriately")
    elif alcohol_value:
        # Check manually
        alcohol_lower = alcohol_value.lower()
        if any(kw in alcohol_lower for kw in ['social', 'moderate', 'occasional', '2-3', 'drinks', 'week']):
            score += score_alcohol
            subscores["alcohol"] = True
            feedback_parts.append(f"Alcohol use: '{alcohol_value[:30]}...'")
        else:
            score += score_alcohol // 2
            feedback_parts.append(f"Alcohol documented but may not match expected: '{alcohol_value[:30]}'")
    else:
        feedback_parts.append("Alcohol use NOT documented")
    
    # ================================================================
    # CRITERION 6: Occupation documented (10 points)
    # ================================================================
    occupation_valid = validation.get('occupation_valid', False)
    occupation_value = history_record.get('occupation', '')
    
    if occupation_valid:
        score += score_occupation
        subscores["occupation"] = True
        feedback_parts.append("Occupation documented (Software Developer)")
    elif occupation_value:
        occupation_lower = occupation_value.lower()
        if any(kw in occupation_lower for kw in ['software', 'developer', 'engineer', 'programmer', 'tech', 'it']):
            score += score_occupation
            subscores["occupation"] = True
            feedback_parts.append(f"Occupation: '{occupation_value}'")
        else:
            score += score_occupation // 2
            feedback_parts.append(f"Occupation documented but different: '{occupation_value}'")
    else:
        feedback_parts.append("Occupation NOT documented")
    
    # ================================================================
    # CRITERION 7: Record saved (15 points)
    # Verify data persisted to database
    # ================================================================
    # If we have meaningful data in the fields, consider it saved
    has_meaningful_data = (
        tobacco_value and 
        len(tobacco_value.strip()) > 2 and
        'null' not in tobacco_value.lower()
    )
    
    if has_meaningful_data and history_modified:
        score += score_saved
        subscores["record_saved"] = True
        feedback_parts.append("Changes persisted to database")
    elif has_meaningful_data:
        score += score_saved // 2
        feedback_parts.append("Data present (save verification partial)")
    else:
        feedback_parts.append("Record save NOT confirmed")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (BONUS)
    # ================================================================
    vlm_bonus = 0
    try:
        # Import VLM utilities if available
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_prompt = """Analyze these screenshots from an OpenEMR electronic health record task.
            
The agent was asked to document social history for a patient, including:
- Smoking status (Former Smoker)
- Quit date (2018)
- Alcohol use
- Occupation

Looking at the sequence of screenshots, determine:
1. Did the agent navigate to a patient's history section?
2. Did the agent appear to fill in form fields?
3. Is there evidence of a save or update action?

Respond in JSON format:
{
    "history_section_visible": true/false,
    "form_filling_observed": true/false,
    "save_action_observed": true/false,
    "confidence": "low"/"medium"/"high",
    "notes": "brief observation"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result:
                try:
                    # Parse VLM response
                    vlm_data = json.loads(vlm_result) if isinstance(vlm_result, str) else vlm_result
                    
                    if vlm_data.get('history_section_visible') and vlm_data.get('form_filling_observed'):
                        vlm_bonus = 5
                        feedback_parts.append("VLM: Workflow confirmed (+5 bonus)")
                    elif vlm_data.get('confidence') == 'high':
                        vlm_bonus = 3
                        feedback_parts.append("VLM: High confidence observation")
                except (json.JSONDecodeError, TypeError):
                    pass
    except ImportError:
        logger.debug("VLM utilities not available for bonus verification")
    except Exception as e:
        logger.debug(f"VLM verification failed: {e}")
    
    # Calculate final score
    final_score = min(score + vlm_bonus, 100)
    
    # Determine pass/fail
    # Must have smoking status documented (key criterion) and score >= 70
    key_criterion_met = subscores["smoking_status"]
    passed = final_score >= 70 and key_criterion_met
    
    # If no smoking status but other things documented, provide helpful feedback
    if not key_criterion_met and score > 0:
        feedback_parts.append("NOTE: Smoking status is REQUIRED for this task")
    
    return {
        "passed": passed,
        "score": final_score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "history_record": history_record,
            "validation": validation,
            "task_duration_seconds": task_end - task_start if task_end and task_start else 0,
            "vlm_bonus": vlm_bonus
        }
    }