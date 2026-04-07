#!/usr/bin/env python3
"""
Verifier for Record Telephone Encounter task in OpenEMR

Verifies that a telephone encounter was correctly documented for patient
Jayson Fadel (pid=3) regarding dizziness symptoms.

Uses copy_from_env to read pre-exported verification data from the container.
Includes VLM verification of trajectory to confirm proper workflow execution.
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_telephone_encounter(traj, env_info, task_info):
    """
    Verify that a telephone encounter was correctly recorded.

    Scoring (100 points total):
    - Encounter exists for correct patient (pid=3): 25 points
    - Encounter is newly created (id > initial max id): 15 points
    - Encounter categorized as phone call: 20 points
    - Encounter dated today: 10 points
    - Reason contains appropriate keywords: 15 points
    - VLM trajectory verification: 15 points

    Passing threshold: 60 points with encounter existing for correct patient
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    reason_keywords = metadata.get('reason_keywords', ['telephone', 'phone', 'call', 'dizziness'])

    score = 0
    feedback_parts = []
    subscores = {
        "encounter_exists": False,
        "correct_patient": False,
        "newly_created": False,
        "phone_category": False,
        "correct_date": False,
        "reason_documented": False,
        "vlm_verified": False
    }
    result_details = {}

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/telephone_encounter_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy/read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read result file: {e}",
                "subscores": subscores
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        result_details['exported_result'] = result

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_encounter_count', 0)
        current_count = result.get('current_encounter_count', 0)
        highest_prev_id = result.get('highest_previous_encounter_id', 0)
        encounter_found = result.get('new_encounter_found', False)
        encounter = result.get('encounter', {})
        validation = result.get('validation', {})
        today_date = result.get('today_date', '')

        logger.info(f"Result: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"Encounter found: {encounter_found}")
        logger.info(f"Encounter data: {encounter}")

        # CRITERION 1: Correct patient (implicit - data is filtered by pid)
        if patient_pid == expected_pid:
            subscores["correct_patient"] = True
            feedback_parts.append(f"✓ Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient ID in result (expected {expected_pid}, got {patient_pid})")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": result_details
            }

        # CRITERION 2: Encounter exists (25 points)
        if encounter_found:
            score += 25
            subscores["encounter_exists"] = True
            encounter_id = encounter.get('id', 'unknown')
            feedback_parts.append(f"✓ New encounter found (id={encounter_id})")
        else:
            feedback_parts.append("✗ No new encounter found for patient")
            
            # Check if any encounters were added at all
            if current_count > initial_count:
                feedback_parts.append(f"Note: Encounter count increased ({initial_count} -> {current_count}) but not detected as new")
            else:
                feedback_parts.append(f"No new encounters created (count: {current_count})")
            
            # Attempt VLM verification as fallback
            vlm_result = _verify_via_vlm(traj, env_info)
            if vlm_result.get('encounter_visible', False):
                score += 10  # Partial credit for visual evidence
                feedback_parts.append("Partial credit: VLM detected encounter creation activity")
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": result_details
            }

        # CRITERION 3: Newly created (15 points)
        encounter_id_str = encounter.get('id', '0')
        try:
            encounter_id = int(encounter_id_str) if encounter_id_str else 0
            if encounter_id > highest_prev_id:
                score += 15
                subscores["newly_created"] = True
                feedback_parts.append(f"✓ Encounter is newly created (id {encounter_id} > previous max {highest_prev_id})")
            else:
                feedback_parts.append(f"? Encounter may be pre-existing (id={encounter_id}, prev_max={highest_prev_id})")
        except ValueError:
            feedback_parts.append(f"? Could not verify encounter ID ({encounter_id_str})")

        # CRITERION 4: Phone call category (20 points)
        is_phone_category = validation.get('is_phone_category', False)
        category_name = encounter.get('category_name', '')
        
        if is_phone_category:
            score += 20
            subscores["phone_category"] = True
            feedback_parts.append(f"✓ Phone call category selected ({category_name})")
        else:
            # Check category name manually for more flexibility
            if category_name:
                cat_lower = category_name.lower()
                if any(kw in cat_lower for kw in ['phone', 'call', 'tele', 'telephone']):
                    score += 20
                    subscores["phone_category"] = True
                    feedback_parts.append(f"✓ Phone-related category: {category_name}")
                else:
                    # Partial credit if they created an encounter but wrong category
                    score += 5
                    feedback_parts.append(f"⚠ Category not phone-specific: {category_name}")
            else:
                feedback_parts.append("⚠ No category assigned to encounter")

        # CRITERION 5: Correct date (10 points)
        encounter_date = encounter.get('date', '')
        date_is_today = validation.get('date_is_today', False)
        
        if date_is_today:
            score += 10
            subscores["correct_date"] = True
            feedback_parts.append(f"✓ Encounter dated today ({encounter_date})")
        else:
            if encounter_date:
                # Check if date is recent (within a day - timezone tolerance)
                feedback_parts.append(f"⚠ Encounter date ({encounter_date}) differs from today ({today_date})")
            else:
                feedback_parts.append("⚠ No date recorded for encounter")

        # CRITERION 6: Reason contains keywords (15 points)
        reason_has_keywords = validation.get('reason_has_keywords', False)
        encounter_reason = encounter.get('reason', '')
        
        if reason_has_keywords:
            score += 15
            subscores["reason_documented"] = True
            feedback_parts.append(f"✓ Reason documented with relevant keywords")
        else:
            # Manual check with more flexibility
            if encounter_reason:
                reason_lower = encounter_reason.lower()
                matched_keywords = [kw for kw in reason_keywords if kw.lower() in reason_lower]
                if matched_keywords:
                    score += 15
                    subscores["reason_documented"] = True
                    feedback_parts.append(f"✓ Reason contains: {', '.join(matched_keywords)}")
                else:
                    # Partial credit for any reason documented
                    score += 5
                    feedback_parts.append(f"⚠ Reason documented but missing keywords: '{encounter_reason[:50]}...'")
            else:
                feedback_parts.append("✗ No reason documented for encounter")

        # CRITERION 7: VLM trajectory verification (15 points)
        vlm_result = _verify_via_vlm(traj, env_info)
        result_details['vlm_result'] = vlm_result
        
        if vlm_result.get('success', False):
            vlm_score = 0
            vlm_feedback = []
            
            if vlm_result.get('patient_chart_accessed', False):
                vlm_score += 5
                vlm_feedback.append("patient chart")
            if vlm_result.get('encounter_form_visible', False):
                vlm_score += 5
                vlm_feedback.append("encounter form")
            if vlm_result.get('encounter_saved', False):
                vlm_score += 5
                vlm_feedback.append("encounter saved")
            
            if vlm_score > 0:
                score += vlm_score
                subscores["vlm_verified"] = vlm_score >= 10
                feedback_parts.append(f"✓ VLM verified: {', '.join(vlm_feedback)} (+{vlm_score})")
            else:
                feedback_parts.append("⚠ VLM could not verify workflow steps")
        else:
            feedback_parts.append(f"⚠ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")

        # Determine pass/fail
        # Must have encounter for correct patient AND either phone category OR reason keywords
        key_criteria_met = (
            subscores["encounter_exists"] and 
            subscores["correct_patient"] and
            (subscores["phone_category"] or subscores["reason_documented"])
        )
        
        passed = score >= 60 and key_criteria_met

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": result_details
        }

    except Exception as e:
        logger.exception(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": subscores,
            "details": result_details
        }


def _verify_via_vlm(traj, env_info):
    """
    Use VLM to verify trajectory shows proper workflow.
    
    Checks trajectory frames for:
    - Patient chart being accessed (Jayson Fadel visible)
    - Encounter form/dialog being opened
    - Phone call category selection
    - Encounter being saved
    """
    result = {
        "success": False,
        "patient_chart_accessed": False,
        "encounter_form_visible": False,
        "encounter_saved": False,
        "error": None
    }
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        result["error"] = "VLM query function not available"
        return result
    
    # Try to import trajectory frame sampling
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        result["error"] = "Could not import VLM utilities"
        return result
    
    # Sample frames from trajectory
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            result["error"] = "No frames available from trajectory"
            return result
        
        # Combine frames for analysis
        all_frames = frames + ([final_screenshot] if final_screenshot else [])
        
    except Exception as e:
        result["error"] = f"Failed to sample frames: {e}"
        return result
    
    # VLM prompt for workflow verification
    vlm_prompt = """Analyze these screenshots from an OpenEMR (Electronic Health Records) session.

The task was to create a telephone encounter for patient "Jayson Fadel" who called about dizziness symptoms.

Look for evidence of the following workflow steps:
1. Was patient Jayson Fadel's chart accessed? (Look for name in patient banner/header)
2. Was an encounter creation form or dialog visible? (New encounter, encounter form)
3. Was "Phone Call" or similar telephone category selected?
4. Was the encounter saved? (Success message, return to patient chart)

Respond in JSON format:
{
    "patient_chart_accessed": true/false,
    "jayson_fadel_visible": true/false,
    "encounter_form_visible": true/false,
    "phone_category_visible": true/false,
    "encounter_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
    
    try:
        vlm_response = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            result["success"] = True
            result["patient_chart_accessed"] = (
                parsed.get("patient_chart_accessed", False) or 
                parsed.get("jayson_fadel_visible", False)
            )
            result["encounter_form_visible"] = (
                parsed.get("encounter_form_visible", False) or
                parsed.get("phone_category_visible", False)
            )
            result["encounter_saved"] = parsed.get("encounter_saved", False)
            result["confidence"] = parsed.get("confidence", "low")
            result["observations"] = parsed.get("observations", "")
        else:
            result["error"] = vlm_response.get("error", "VLM query failed")
            
    except Exception as e:
        result["error"] = f"VLM query error: {e}"
    
    return result


if __name__ == "__main__":
    # Test with mock data
    print("Telephone Encounter Verifier - Test Mode")
    print("This verifier checks for:")
    print("  1. New encounter exists for patient pid=3 (Jayson Fadel)")
    print("  2. Encounter is newly created (not pre-existing)")
    print("  3. Encounter categorized as phone call")
    print("  4. Encounter dated today")
    print("  5. Reason contains keywords (phone, dizziness, etc.)")
    print("  6. VLM trajectory verification")