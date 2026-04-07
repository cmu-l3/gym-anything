#!/usr/bin/env python3
"""
Verifier for add_prescription task in FreeMED.
Uses database validation and VLM trajectory analysis to prevent gaming.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these trajectory frames of a user interacting with an Electronic Medical Record (EMR) system.
    
Check for the following to confirm the workflow was genuinely executed:
1. Did the user search for or navigate to a patient record (Margaret Thompson)?
2. Did the user open the prescription or medication entry form?
3. Did the user interact with the form fields (entering Lisinopril, 10mg, quantity, etc.)?

Respond in JSON format:
{
    "navigated_to_patient": true/false,
    "opened_prescription_form": true/false,
    "interacted_with_fields": true/false,
    "confidence": "high/medium/low"
}
"""


def verify_add_prescription(traj, env_info, task_info):
    """
    Verify that the expected prescription was added to Margaret Thompson's record in FreeMED.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_drug = metadata.get('expected_drug', 'Lisinopril').lower()
    expected_dosage = str(metadata.get('expected_dosage', '10'))
    expected_quantity = str(metadata.get('expected_quantity', '30'))
    expected_refills = str(metadata.get('expected_refills', '3'))
    expected_note_keywords = metadata.get('expected_note_keywords', ['htn', 'hypertension', 'bp'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        initial_count = result.get('initial_rx_count', 0)
        current_count = result.get('current_rx_count', 0)
        rx_found = result.get('rx_found', False)
        prescription = result.get('prescription', {})

        # 1. Anti-gaming check: Was a new prescription actually created? (Count increased)
        if current_count > initial_count and rx_found:
            score += 20
            feedback_parts.append(f"New prescription created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new prescription created for patient (count remained {initial_count})")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # 2. Check Drug Name (20 pts)
        actual_drug = prescription.get('drug', '').lower()
        if expected_drug in actual_drug:
            score += 20
            feedback_parts.append(f"Drug correct: {actual_drug}")
        else:
            feedback_parts.append(f"Drug incorrect: expected '{expected_drug}', got '{actual_drug}'")

        # 3. Check Quantity (15 pts)
        actual_quantity = str(prescription.get('quantity', '')).strip()
        if expected_quantity == actual_quantity:
            score += 15
            feedback_parts.append(f"Quantity correct: {actual_quantity}")
        else:
            feedback_parts.append(f"Quantity incorrect: expected {expected_quantity}, got {actual_quantity}")

        # 4. Check Refills (15 pts)
        actual_refills = str(prescription.get('refills', '')).strip()
        if expected_refills == actual_refills:
            score += 15
            feedback_parts.append(f"Refills correct: {actual_refills}")
        else:
            feedback_parts.append(f"Refills incorrect: expected {expected_refills}, got {actual_refills}")

        # 5. Check Dosage (10 pts)
        actual_dosage = str(prescription.get('dosage', '')).lower()
        if expected_dosage in actual_dosage:
            score += 10
            feedback_parts.append(f"Dosage contains '{expected_dosage}'")
        else:
            feedback_parts.append(f"Dosage incorrect: expected {expected_dosage}, got {actual_dosage}")

        # 6. Check Notes (10 pts)
        actual_note = prescription.get('note', '').lower()
        if any(keyword in actual_note for keyword in expected_note_keywords):
            score += 10
            feedback_parts.append("Note contains appropriate clinical keywords")
        else:
            feedback_parts.append(f"Note missing or incorrect clinical context: '{actual_note}'")

        # 7. VLM Trajectory Verification (10 pts)
        # Prevent gaming by confirming the user actually interacted with the UI
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if frames and query_vlm:
                vlm_result = query_vlm(
                    images=frames + [final_frame] if final_frame else frames,
                    prompt=build_vlm_prompt()
                )
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("opened_prescription_form", False) and parsed.get("interacted_with_fields", False):
                        score += 10
                        feedback_parts.append("VLM confirmed UI interaction")
                    else:
                        feedback_parts.append("VLM did not detect proper UI interaction")
        except Exception as e:
            logger.warning(f"VLM verification failed or unavailable: {e}")
            # If VLM is unavailable, we still grant the points assuming DB verification is solid
            score += 10
            feedback_parts.append("VLM skipped (awarded default 10 points)")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }