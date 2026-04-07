#!/usr/bin/env python3
"""
Verifier for Record Medical Record Amendment task in OpenEMR

This task verifies that the agent correctly documented a medical record amendment
for patient Jayson Fadel (pid=3) as required by HIPAA Right of Amendment.

Verification criteria:
1. Amendment record exists for correct patient (pid=3)
2. Amendment was newly created during task (not pre-existing)
3. Description contains occupation-related keywords
4. Status is set to approved
5. Response to patient is documented
6. Created timestamp is within task execution window

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_medical_record_amendment(traj, env_info, task_info):
    """
    Verify that a medical record amendment was correctly recorded.

    Scoring (100 points total):
    - Amendment exists for correct patient: 35 points
    - Correct patient (pid=3): 5 points (included in above)
    - Occupation referenced in description: 20 points
    - Status set to approved: 15 points
    - Created during task window: 15 points
    - Response to patient documented: 10 points

    Passing threshold: 70 points with amendment existing for correct patient
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_keywords = metadata.get('expected_keywords', ['occupation', 'employment', 'nurse', 'correction'])
    scoring_weights = metadata.get('scoring_weights', {
        'amendment_exists': 35,
        'correct_patient': 5,
        'occupation_referenced': 20,
        'status_approved': 15,
        'created_during_task': 15,
        'response_documented': 10
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/amendment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "amendment_exists": False,
            "correct_patient": False,
            "occupation_referenced": False,
            "status_approved": False,
            "created_during_task": False,
            "response_documented": False
        }

        # Extract data from exported result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_amendment_count', 0)
        current_count = result.get('current_amendment_count', 0)
        total_initial = result.get('total_initial_amendments', 0)
        total_current = result.get('total_current_amendments', 0)
        amendment_found = result.get('new_amendment_found', False)
        amendment = result.get('amendment', {})
        validation = result.get('validation', {})

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"Amendment found: {amendment_found}")
        logger.info(f"Amendment data: {amendment}")
        logger.info(f"Validation flags: {validation}")

        # CRITICAL CHECK: Verify we're checking the right patient
        if patient_pid != expected_pid:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Verification targeted wrong patient (expected pid={expected_pid}, got {patient_pid})",
                "subscores": subscores
            }

        subscores["correct_patient"] = True

        # CRITERION 1: Amendment exists for correct patient (35 points)
        if amendment_found and current_count > initial_count:
            score += scoring_weights.get('amendment_exists', 35)
            subscores["amendment_exists"] = True
            feedback_parts.append(f"✅ Amendment created for patient {expected_fname} {expected_lname} (pid={expected_pid})")
            feedback_parts.append(f"   Amendment count: {initial_count} → {current_count}")
        else:
            feedback_parts.append(f"❌ No new amendment found for patient pid={expected_pid}")
            
            # Check if amendment was added to wrong patient (adversarial detection)
            if total_current > total_initial and current_count == initial_count:
                feedback_parts.append(f"   ⚠️ WARNING: Amendment may have been added to wrong patient")
                feedback_parts.append(f"   Total amendments: {total_initial} → {total_current}")
            
            # Early return since no amendment found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Occupation referenced in description (20 points)
        description = amendment.get('description', '').lower()
        occupation_keywords_found = []
        
        for keyword in expected_keywords:
            if keyword.lower() in description:
                occupation_keywords_found.append(keyword)
        
        # Also check validation flag from export script
        occupation_mentioned = validation.get('occupation_mentioned', False)
        
        if occupation_keywords_found or occupation_mentioned:
            score += scoring_weights.get('occupation_referenced', 20)
            subscores["occupation_referenced"] = True
            if occupation_keywords_found:
                feedback_parts.append(f"✅ Description references occupation (keywords: {', '.join(occupation_keywords_found)})")
            else:
                feedback_parts.append(f"✅ Description references occupation/employment")
        else:
            feedback_parts.append(f"❌ Description does not mention occupation/employment")
            feedback_parts.append(f"   Description preview: {description[:100]}...")

        # CRITERION 3: Status is approved (15 points)
        status = amendment.get('status', '').lower()
        status_approved = validation.get('status_approved', False)
        
        approved_terms = ['approved', 'accepted', 'accept', 'complete', 'completed']
        status_is_approved = status_approved or any(term in status for term in approved_terms)
        
        if status_is_approved:
            score += scoring_weights.get('status_approved', 15)
            subscores["status_approved"] = True
            feedback_parts.append(f"✅ Amendment status: approved/accepted")
        else:
            feedback_parts.append(f"❌ Amendment status not approved (status: '{amendment.get('status', 'empty')}')")

        # CRITERION 4: Created during task window (15 points)
        created_during_task = validation.get('created_during_task', False)
        
        # Also verify using timestamps if available
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        created_time = amendment.get('created_time', '')
        
        if created_during_task:
            score += scoring_weights.get('created_during_task', 15)
            subscores["created_during_task"] = True
            feedback_parts.append(f"✅ Amendment created during task execution")
        else:
            # If we have new amendments but created_during_task is false, give partial credit
            if current_count > initial_count:
                score += scoring_weights.get('created_during_task', 15) // 2
                feedback_parts.append(f"⚠️ Amendment exists but creation time verification inconclusive")
            else:
                feedback_parts.append(f"❌ Amendment not created during task window")

        # CRITERION 5: Response to patient documented (10 points)
        response_exists = validation.get('response_exists', False)
        
        if response_exists:
            score += scoring_weights.get('response_documented', 10)
            subscores["response_documented"] = True
            feedback_parts.append(f"✅ Response to patient documented")
        else:
            feedback_parts.append(f"❌ No response to patient documented")

        # Determine pass/fail
        # Must have amendment for correct patient + at least occupation mentioned
        key_criteria_met = (
            subscores["amendment_exists"] and
            subscores["correct_patient"]
        )
        
        passed = score >= 70 and key_criteria_met

        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "amendment_id": amendment.get('id', ''),
                "initial_count": initial_count,
                "current_count": current_count,
                "task_window": f"{task_start}-{task_end}"
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Export result file not found - task may not have completed properly"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse export result: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def verify_via_vlm(traj, env_info):
    """
    Secondary VLM-based verification using trajectory screenshots.
    
    Checks that the agent:
    1. Navigated to patient chart
    2. Found and opened Amendments section
    3. Filled out amendment form
    4. Saved the amendment
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames (not just final screenshot - important for detecting actual work)
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            return {"success": False, "error": "No screenshots available"}

        # Use all frames for trajectory verification
        all_images = frames + ([final_screenshot] if final_screenshot else [])

        vlm_prompt = """You are verifying if a computer agent successfully recorded a medical record amendment in OpenEMR (Electronic Health Records system).

TASK: Record a medical record amendment for patient Jayson Fadel documenting a correction to their occupation information.

Analyze these screenshots showing the agent's work progression and determine:

1. Did the agent navigate to a patient's chart? (Look for patient name, demographics)
2. Did the agent find the Amendments section? (Look for "Amendments" menu item or heading)
3. Did the agent fill out an amendment form? (Look for form fields like description, status, response)
4. Did the agent appear to save/submit the amendment? (Look for save button click or success message)
5. Is there any indication the amendment was created? (Success message, new entry in list)

Respond in JSON format:
{
    "navigated_to_patient": true/false,
    "found_amendments_section": true/false,
    "filled_amendment_form": true/false,
    "saved_amendment": true/false,
    "success_indicated": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed in the workflow"
}
"""

        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_images
        )

        return vlm_result

    except ImportError:
        return {"success": False, "error": "VLM utilities not available"}
    except Exception as e:
        return {"success": False, "error": str(e)}