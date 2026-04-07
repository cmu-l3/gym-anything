#!/usr/bin/env python3
"""
Verifier for Record Smoking Status Change task in OpenEMR

Verifies that:
1. The correct patient (Marcus Weber, pid=6) was modified
2. The smoking status was changed from the initial value
3. The new status indicates "Former Smoker"
4. The change was made during the task (anti-gaming check)
5. Visual evidence supports the workflow was followed

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


def verify_smoking_status_change(traj, env_info, task_info):
    """
    Verify that the patient's smoking status was updated correctly.

    Scoring (100 points total):
    - Correct patient (pid=6): 15 points
    - Status changed from initial: 30 points
    - New status indicates "former smoker": 25 points
    - Record saved/modified during task: 15 points
    - VLM trajectory verification: 15 points

    Passing threshold: 60 points with status_changed criterion met
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 6)
    expected_fname = metadata.get('patient_fname', 'Marcus')
    expected_lname = metadata.get('patient_lname', 'Weber')
    acceptable_former_values = metadata.get('acceptable_former_values', 
        ['former', 'ex-', 'quit', 'past', '8517006', 'former smoker', 'ex smoker', 'ex-smoker'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/smoking_status_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "status_changed": False,
            "correct_former_value": False,
            "record_saved": False,
            "vlm_verification": False
        }

        # Extract data
        patient_pid = result.get('patient_pid', 0)
        patient_fname = result.get('patient_fname', '')
        patient_lname = result.get('patient_lname', '')
        initial_status = result.get('initial_smoking_status', '')
        current_status = result.get('current_smoking_status', '')
        current_history = result.get('current_history_tobacco', '')
        status_changed = result.get('status_changed', False)
        is_former = result.get('is_former_smoker_value', False)
        record_modified = result.get('record_modified_during_task', False)
        history_modified = result.get('history_modified_during_task', False)

        logger.info(f"Result data: pid={patient_pid}, initial='{initial_status}', current='{current_status}'")
        logger.info(f"Status changed: {status_changed}, Is former: {is_former}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            # Also verify name matches
            if (patient_fname.lower() == expected_fname.lower() and 
                patient_lname.lower() == expected_lname.lower()):
                score += 15
                subscores["correct_patient"] = True
                feedback_parts.append(f"✅ Correct patient: {patient_fname} {patient_lname} (pid={patient_pid})")
            else:
                score += 10  # Partial credit - correct pid but name mismatch
                feedback_parts.append(f"⚠️ Patient pid matches but name mismatch: got '{patient_fname} {patient_lname}'")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - return early with zero score
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient modified (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Status changed from initial value (30 points)
        initial_lower = initial_status.lower().strip() if initial_status else ""
        current_lower = current_status.lower().strip() if current_status else ""
        history_lower = current_history.lower().strip() if current_history else ""

        # Check if status actually changed
        actual_change_detected = False
        if current_lower and initial_lower != current_lower:
            actual_change_detected = True
        elif history_lower and history_lower != initial_lower:
            actual_change_detected = True

        if status_changed or actual_change_detected:
            score += 30
            subscores["status_changed"] = True
            feedback_parts.append(f"✅ Smoking status changed: '{initial_status}' → '{current_status}'")
        else:
            feedback_parts.append(f"❌ Smoking status not changed (still: '{current_status}')")
            # This is a critical criterion - without change, task not completed

        # CRITERION 3: New status indicates "former smoker" (25 points)
        def is_former_smoker_value(value):
            """Check if value indicates former smoker status."""
            if not value:
                return False
            value_lower = value.lower()
            for acceptable in acceptable_former_values:
                if acceptable.lower() in value_lower:
                    return True
            return False

        # Check both patient_data.tobacco and history_data.tobacco
        current_is_former = is_former_smoker_value(current_status)
        history_is_former = is_former_smoker_value(current_history)

        if current_is_former or history_is_former or is_former:
            score += 25
            subscores["correct_former_value"] = True
            if current_is_former:
                feedback_parts.append(f"✅ Status correctly set to former smoker: '{current_status}'")
            else:
                feedback_parts.append(f"✅ History status indicates former smoker: '{current_history}'")
        else:
            # Check if status changed to something else (partial credit)
            if status_changed and current_status:
                score += 10  # Partial credit - changed but not to "former"
                feedback_parts.append(f"⚠️ Status changed but not to 'Former Smoker': '{current_status}'")
            else:
                feedback_parts.append(f"❌ Status not set to 'Former Smoker' value")

        # CRITERION 4: Record was saved/modified during task (15 points)
        if record_modified or history_modified:
            score += 15
            subscores["record_saved"] = True
            if record_modified:
                feedback_parts.append("✅ Patient record modified during task")
            else:
                feedback_parts.append("✅ History record created during task")
        else:
            # Check timestamps manually as fallback
            task_start = result.get('task_start_timestamp', 0)
            current_mtime = result.get('current_mtime', 0)
            if current_mtime > task_start:
                score += 15
                subscores["record_saved"] = True
                feedback_parts.append("✅ Record timestamp updated during task")
            else:
                feedback_parts.append("⚠️ Record modification timestamp not updated")
                # Don't penalize heavily - UI may not update timestamp for all changes

        # CRITERION 5: VLM trajectory verification (15 points)
        vlm_score = 0
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            try:
                # Import VLM utilities
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                # Sample frames across the trajectory
                frames = sample_trajectory_frames(traj, n=4)
                final_frame = get_final_screenshot(traj)
                
                if frames or final_frame:
                    all_frames = (frames or []) + ([final_frame] if final_frame else [])
                    
                    vlm_prompt = """You are verifying if a computer agent successfully updated a patient's smoking status in OpenEMR (Electronic Health Records).

TASK: Update patient Marcus Weber's smoking status from "Current Every Day Smoker" to "Former Smoker"

Examine these screenshots and determine:
1. Did the agent log into OpenEMR?
2. Did the agent search for and open patient Marcus Weber's chart?
3. Did the agent navigate to the social history, demographics, or lifestyle section?
4. Did the agent modify the smoking/tobacco status field?
5. Did the agent save the changes?

Look for evidence of:
- OpenEMR interface visible
- Patient search/selection
- Form editing with smoking/tobacco fields
- Save/submit actions

Respond in JSON format:
{
    "openemr_visible": true/false,
    "patient_accessed": true/false,
    "smoking_field_edited": true/false,
    "changes_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                    vlm_result = query_vlm(
                        prompt=vlm_prompt,
                        images=all_frames
                    )
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        openemr_visible = parsed.get('openemr_visible', False)
                        patient_accessed = parsed.get('patient_accessed', False)
                        smoking_edited = parsed.get('smoking_field_edited', False)
                        changes_saved = parsed.get('changes_saved', False)
                        confidence = parsed.get('confidence', 'low')
                        
                        # Calculate VLM score based on workflow evidence
                        vlm_criteria_met = sum([openemr_visible, patient_accessed, smoking_edited, changes_saved])
                        
                        if vlm_criteria_met >= 3 and confidence in ['medium', 'high']:
                            vlm_score = 15
                            subscores["vlm_verification"] = True
                            feedback_parts.append(f"✅ VLM confirms workflow ({vlm_criteria_met}/4 criteria, {confidence} confidence)")
                        elif vlm_criteria_met >= 2:
                            vlm_score = 10
                            feedback_parts.append(f"⚠️ VLM partial confirmation ({vlm_criteria_met}/4 criteria)")
                        elif vlm_criteria_met >= 1:
                            vlm_score = 5
                            feedback_parts.append(f"⚠️ VLM limited evidence ({vlm_criteria_met}/4 criteria)")
                        else:
                            feedback_parts.append("❌ VLM could not confirm workflow")
                    else:
                        feedback_parts.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}")
                else:
                    feedback_parts.append("⚠️ No trajectory frames available for VLM")
            except ImportError:
                feedback_parts.append("⚠️ VLM utilities not available")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM verification error: {str(e)}")
        else:
            feedback_parts.append("⚠️ VLM not available for trajectory verification")
        
        score += vlm_score

        # Determine pass/fail
        # Must have changed status to pass, plus reasonable score
        key_criteria_met = subscores["status_changed"] and subscores["correct_patient"]
        passed = score >= 60 and key_criteria_met

        # Bonus: If status is correctly "former" but wasn't detected by export, give benefit of doubt
        if not passed and subscores["correct_patient"] and score >= 45:
            # Check if there's any indication of progress
            if subscores["correct_former_value"]:
                passed = True
                feedback_parts.append("✓ Passed with correct former smoker status")

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "initial_status": initial_status,
                "current_status": current_status,
                "patient_pid": patient_pid
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Export result file not found - task may not have completed",
            "subscores": {
                "correct_patient": False,
                "status_changed": False,
                "correct_former_value": False,
                "record_saved": False,
                "vlm_verification": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Could not parse result file: {str(e)}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {}
        }


if __name__ == "__main__":
    # Test mode
    print("Smoking Status Change Verifier")
    print("This verifier checks if a patient's smoking status was updated correctly.")
    print("\nExpected changes:")
    print("  - Patient: Marcus Weber (pid=6)")
    print("  - Initial: Current Every Day Smoker")
    print("  - Expected: Former Smoker")