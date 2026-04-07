#!/usr/bin/env python3
"""
Verifier for Document Medical Device task in OpenEMR

Verifies that a cardiac pacemaker was properly documented for patient Jayson Fadel.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.

Scoring (100 points total):
- Entry exists for correct patient: 25 points
- Device type identified (pacemaker): 15 points
- Manufacturer documented (Medtronic): 15 points
- Model documented (Azure/SureScan): 10 points
- Serial number recorded (PJN847291): 15 points
- Implant date correct (2024-09-15): 10 points
- MRI status noted: 5 points
- Created after task start (anti-gaming): 5 points

Pass threshold: 60 points with entry_exists required
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_medical_device(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a cardiac pacemaker was documented correctly for the patient.

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_manufacturer = metadata.get('device_manufacturer', 'Medtronic').lower()
    expected_serial = metadata.get('device_serial', 'PJN847291').lower()
    expected_date = metadata.get('device_implant_date', '2024-09-15')
    
    # Scoring weights from metadata
    weights = metadata.get('scoring_weights', {
        'entry_exists': 25,
        'device_type_identified': 15,
        'manufacturer_documented': 15,
        'model_documented': 10,
        'serial_recorded': 15,
        'implant_date_correct': 10,
        'mri_status_noted': 5,
        'created_after_start': 5
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/document_device_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Failed to copy/read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification data: {str(e)}"
        }

    score = 0
    feedback_parts = []
    subscores = {
        "entry_exists": False,
        "device_type_identified": False,
        "manufacturer_documented": False,
        "model_documented": False,
        "serial_recorded": False,
        "implant_date_correct": False,
        "mri_status_noted": False,
        "created_after_start": False
    }

    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    entry_found = result.get('entry_found', False)
    entry = result.get('entry', {})
    validation = result.get('validation', {})
    initial_max_id = result.get('initial_max_list_id', 0)
    current_max_id = result.get('current_max_list_id', 0)

    logger.info(f"Verifying device documentation for patient PID={patient_pid}")
    logger.info(f"Entry found: {entry_found}")
    logger.info(f"Entry data: {entry}")
    logger.info(f"Validation: {validation}")

    # Verify correct patient
    if patient_pid != expected_pid:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong patient! Expected PID={expected_pid}, got {patient_pid}",
            "subscores": subscores
        }

    # CRITERION 1: Entry exists (25 points)
    if entry_found:
        entry_id = entry.get('id', '')
        try:
            entry_id_int = int(entry_id) if entry_id else 0
            # Verify it's a new entry (ID > initial max)
            if entry_id_int > initial_max_id:
                score += weights.get('entry_exists', 25)
                subscores["entry_exists"] = True
                feedback_parts.append(f"✅ New entry created (ID={entry_id})")
            else:
                # Entry exists but may be pre-existing - give partial credit
                score += weights.get('entry_exists', 25) // 2
                feedback_parts.append(f"⚠️ Entry found but may be pre-existing (ID={entry_id})")
        except (ValueError, TypeError):
            score += weights.get('entry_exists', 25) // 2
            feedback_parts.append(f"⚠️ Entry found but ID unclear")
    else:
        feedback_parts.append("❌ No device entry found for patient")
        # Early return - nothing else to check
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # CRITERION 2: Device type identified - pacemaker (15 points)
    if validation.get('pacemaker_mentioned', False):
        score += weights.get('device_type_identified', 15)
        subscores["device_type_identified"] = True
        feedback_parts.append("✅ Pacemaker/cardiac device identified")
    else:
        # Check entry title/comments directly as backup
        combined_text = f"{entry.get('title', '')} {entry.get('comments', '')}".lower()
        if any(term in combined_text for term in ['pacemaker', 'pacer', 'cardiac device', 'cardiac implant']):
            score += weights.get('device_type_identified', 15)
            subscores["device_type_identified"] = True
            feedback_parts.append("✅ Pacemaker/cardiac device identified")
        else:
            feedback_parts.append("❌ Pacemaker/cardiac device type not clearly identified")

    # CRITERION 3: Manufacturer documented - Medtronic (15 points)
    if validation.get('medtronic_mentioned', False):
        score += weights.get('manufacturer_documented', 15)
        subscores["manufacturer_documented"] = True
        feedback_parts.append("✅ Manufacturer (Medtronic) documented")
    else:
        combined_text = f"{entry.get('title', '')} {entry.get('comments', '')}".lower()
        if expected_manufacturer in combined_text:
            score += weights.get('manufacturer_documented', 15)
            subscores["manufacturer_documented"] = True
            feedback_parts.append("✅ Manufacturer (Medtronic) documented")
        else:
            feedback_parts.append("❌ Manufacturer (Medtronic) not documented")

    # CRITERION 4: Model documented - Azure/SureScan (10 points)
    if validation.get('model_mentioned', False):
        score += weights.get('model_documented', 10)
        subscores["model_documented"] = True
        feedback_parts.append("✅ Model (Azure/SureScan) documented")
    else:
        combined_text = f"{entry.get('title', '')} {entry.get('comments', '')}".lower()
        if 'azure' in combined_text or 'surescan' in combined_text:
            score += weights.get('model_documented', 10)
            subscores["model_documented"] = True
            feedback_parts.append("✅ Model (Azure/SureScan) documented")
        else:
            feedback_parts.append("❌ Model not documented")

    # CRITERION 5: Serial number recorded - PJN847291 (15 points)
    if validation.get('serial_mentioned', False):
        score += weights.get('serial_recorded', 15)
        subscores["serial_recorded"] = True
        feedback_parts.append("✅ Serial number (PJN847291) recorded")
    else:
        combined_text = f"{entry.get('title', '')} {entry.get('comments', '')} {entry.get('diagnosis', '')}".lower()
        if expected_serial in combined_text:
            score += weights.get('serial_recorded', 15)
            subscores["serial_recorded"] = True
            feedback_parts.append("✅ Serial number (PJN847291) recorded")
        else:
            feedback_parts.append("❌ Serial number (PJN847291) not recorded")

    # CRITERION 6: Implant date correct - 2024-09-15 (10 points)
    if validation.get('date_correct', False):
        score += weights.get('implant_date_correct', 10)
        subscores["implant_date_correct"] = True
        feedback_parts.append("✅ Implant date correct (2024-09-15)")
    else:
        begdate = entry.get('begdate', '')
        if begdate == expected_date:
            score += weights.get('implant_date_correct', 10)
            subscores["implant_date_correct"] = True
            feedback_parts.append("✅ Implant date correct (2024-09-15)")
        elif begdate:
            # Partial credit for having a date
            score += weights.get('implant_date_correct', 10) // 2
            feedback_parts.append(f"⚠️ Implant date set but incorrect: {begdate} (expected 2024-09-15)")
        else:
            feedback_parts.append("❌ Implant date not set")

    # CRITERION 7: MRI status noted (5 points)
    if validation.get('mri_mentioned', False):
        score += weights.get('mri_status_noted', 5)
        subscores["mri_status_noted"] = True
        feedback_parts.append("✅ MRI status noted")
    else:
        combined_text = f"{entry.get('title', '')} {entry.get('comments', '')}".lower()
        if 'mri' in combined_text or 'magnetic' in combined_text:
            score += weights.get('mri_status_noted', 5)
            subscores["mri_status_noted"] = True
            feedback_parts.append("✅ MRI status noted")
        else:
            feedback_parts.append("⚠️ MRI status not noted (optional)")

    # CRITERION 8: Created after task start - anti-gaming (5 points)
    if validation.get('created_during_task', False) or validation.get('new_entry_by_id', False):
        score += weights.get('created_after_start', 5)
        subscores["created_after_start"] = True
        feedback_parts.append("✅ Entry created during task execution")
    else:
        feedback_parts.append("⚠️ Could not verify entry was created during task")

    # Determine pass/fail
    # Must have entry_exists (25 points) as a key criterion
    # Pass threshold: 60 points
    key_criteria_met = subscores["entry_exists"]
    passed = score >= 60 and key_criteria_met

    # Generate final feedback
    feedback = " | ".join(feedback_parts)

    logger.info(f"Final score: {score}/100, passed: {passed}")
    logger.info(f"Subscores: {subscores}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "entry_found": entry_found,
            "entry_id": entry.get('id', ''),
            "entry_title": entry.get('title', '')[:100] if entry.get('title') else '',
            "entry_begdate": entry.get('begdate', ''),
            "validation": validation
        }
    }


def verify_with_vlm_backup(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Optional VLM verification using trajectory frames.
    
    This can be used as supplementary verification to confirm the agent
    actually navigated through the UI rather than just modifying the database.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
    except ImportError:
        logger.warning("VLM utilities not available for backup verification")
        return {"vlm_available": False}

    # Sample frames from trajectory
    frames = sample_trajectory_frames(traj, n=5)
    
    if not frames:
        return {"vlm_available": True, "frames_found": False}

    query_vlm_func = env_info.get('query_vlm')
    if not query_vlm_func:
        return {"vlm_available": True, "query_func_available": False}

    prompt = """You are verifying if a computer agent completed a medical record documentation task in OpenEMR.

TASK: Document an implanted cardiac pacemaker for patient Jayson Fadel.
Device: Medtronic Azure XT DR MRI SureScan, Serial: PJN847291

Look at these screenshots from the agent's work session and determine:
1. Did the agent navigate to a patient record for Jayson Fadel?
2. Did the agent access a form to add medical problems/issues?
3. Did the agent enter information about a pacemaker or medical device?
4. Did the agent save/submit the entry?

Respond in JSON format:
{
    "patient_accessed": true/false,
    "form_opened": true/false,
    "device_info_entered": true/false,
    "entry_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

    try:
        result = query_vlm_func(
            prompt=prompt,
            images=frames
        )
        return {
            "vlm_available": True,
            "vlm_result": result
        }
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return {"vlm_available": True, "vlm_error": str(e)}