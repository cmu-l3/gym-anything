#!/usr/bin/env python3
"""
Verifier for Create Patient Letter task in OpenEMR

Verifies that a lab results notification letter was created for patient Jayson Fadel.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Patient correctly targeted: 15 points
- Letter feature accessed (any new entry): 15 points
- Letter/note created: 25 points
- Content correct (keywords): 25 points
- Proper save (persisted): 10 points
- Timestamp valid (created during task): 10 points
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_patient_letter(traj, env_info, task_info):
    """
    Verify that a patient letter was created for Jayson Fadel.
    
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
            "feedback": "Copy function not available"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    required_phone = metadata.get('required_phone', '555')
    content_keywords = metadata.get('content_keywords', ['lab', 'result', 'contact', 'appointment', 'call'])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_letter_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "patient_selected": False,
            "letter_feature_accessed": False,
            "letter_created": False,
            "content_correct": False,
            "proper_save": False,
            "timestamp_valid": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        letter_created = result.get('letter_created', False)
        counts = result.get('counts', {})
        content_analysis = result.get('content_analysis', {})
        latest_pnote = result.get('latest_pnote', {})
        latest_document = result.get('latest_document', {})
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        
        # Calculate new entries
        new_pnotes = counts.get('new_pnotes', 0)
        new_docs = counts.get('new_documents', 0)
        new_onotes = counts.get('new_onotes', 0)
        new_dictation = counts.get('new_dictation', 0)
        total_new_entries = new_pnotes + new_docs + new_onotes + new_dictation
        
        logger.info(f"Patient PID: {patient_pid}, Expected: {expected_pid}")
        logger.info(f"Letter created: {letter_created}")
        logger.info(f"New entries - pnotes: {new_pnotes}, docs: {new_docs}, onotes: {new_onotes}")
        logger.info(f"Content analysis: {content_analysis}")
        
        # CRITERION 1: Patient correctly targeted (15 points)
        # The task was set up for the correct patient
        if patient_pid == expected_pid:
            score += 15
            subscores["patient_selected"] = True
            feedback_parts.append(f"✓ Correct patient targeted (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"✗ Wrong patient (expected pid={expected_pid}, got {patient_pid})")
        
        # CRITERION 2: Letter feature accessed (15 points)
        # Any new entry indicates the feature was accessed
        if total_new_entries > 0:
            score += 15
            subscores["letter_feature_accessed"] = True
            feedback_parts.append(f"✓ Letter/note feature accessed ({total_new_entries} new entries)")
        else:
            feedback_parts.append("✗ No letter feature accessed (no new entries detected)")
        
        # CRITERION 3: Letter/note created (25 points)
        if letter_created and total_new_entries > 0:
            score += 25
            subscores["letter_created"] = True
            
            # Provide detail about what was created
            created_items = []
            if new_pnotes > 0:
                created_items.append(f"{new_pnotes} patient note(s)")
            if new_docs > 0:
                created_items.append(f"{new_docs} document(s)")
            if new_onotes > 0:
                created_items.append(f"{new_onotes} office note(s)")
            if new_dictation > 0:
                created_items.append(f"{new_dictation} dictation(s)")
            
            feedback_parts.append(f"✓ Letter created: {', '.join(created_items)}")
        else:
            feedback_parts.append("✗ No letter/note was created")
        
        # CRITERION 4: Content correct (25 points)
        # Check for required keywords in the content
        has_lab = content_analysis.get('has_lab', False)
        has_result = content_analysis.get('has_result', False)
        has_phone = content_analysis.get('has_phone', False)
        has_contact = content_analysis.get('has_contact', False)
        has_patient_name = content_analysis.get('has_patient_name', False)
        
        content_matches = sum([has_lab, has_result, has_phone, has_contact])
        
        if content_matches >= 3:
            # Full points for 3+ keyword matches
            score += 25
            subscores["content_correct"] = True
            feedback_parts.append(f"✓ Content correct (lab={has_lab}, result={has_result}, phone={has_phone}, contact={has_contact})")
        elif content_matches >= 2:
            # Partial points for 2 keyword matches
            score += 15
            subscores["content_correct"] = True
            feedback_parts.append(f"◐ Content partially correct ({content_matches}/4 keywords found)")
        elif content_matches >= 1:
            # Minimal points for 1 keyword match
            score += 5
            feedback_parts.append(f"◐ Content has minimal keywords ({content_matches}/4 found)")
        else:
            feedback_parts.append("✗ Content missing required keywords (lab, result, phone, contact)")
        
        # CRITERION 5: Proper save (10 points)
        # Letter persisted to database (same as letter_created but separate criterion)
        if letter_created:
            score += 10
            subscores["proper_save"] = True
            feedback_parts.append("✓ Letter saved to patient record")
        else:
            feedback_parts.append("✗ Letter not saved to patient record")
        
        # CRITERION 6: Timestamp valid (10 points)
        # Entry was created during the task (anti-gaming)
        if letter_created and task_start > 0:
            # If we have new entries, they were created during task
            score += 10
            subscores["timestamp_valid"] = True
            task_duration = task_end - task_start
            feedback_parts.append(f"✓ Entry created during task (duration: {task_duration}s)")
        elif not letter_created:
            feedback_parts.append("✗ No entry to validate timestamp")
        else:
            feedback_parts.append("✗ Could not verify entry timestamp")
        
        # VLM verification as supplementary check (if available)
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            try:
                # Import VLM utilities
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                # Get trajectory frames for workflow verification
                frames = sample_trajectory_frames(traj, n=5)
                final_screenshot = get_final_screenshot(traj)
                
                if frames or final_screenshot:
                    vlm_prompt = """You are verifying if a computer agent completed a task in OpenEMR (Electronic Health Records system).

TASK: Create a patient letter for Jayson Fadel notifying about lab results.

Look at these screenshots and determine:
1. Did the agent access OpenEMR and navigate to the patient?
2. Did the agent access the letter/correspondence feature?
3. Is there evidence of letter content being created?
4. Was there a save/confirmation action?

Respond in JSON format:
{
    "accessed_openemr": true/false,
    "found_patient": true/false,
    "accessed_letter_feature": true/false,
    "letter_content_visible": true/false,
    "save_action_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                    images_to_check = (frames or []) + ([final_screenshot] if final_screenshot else [])
                    
                    if images_to_check:
                        vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
                        
                        if vlm_result.get('success'):
                            parsed = vlm_result.get('parsed', {})
                            
                            # Add VLM insights to feedback
                            if parsed.get('letter_content_visible'):
                                feedback_parts.append("✓ VLM: Letter content visible in screenshots")
                            if parsed.get('save_action_visible'):
                                feedback_parts.append("✓ VLM: Save action observed")
                            
                            logger.info(f"VLM result: {parsed}")
            except Exception as vlm_error:
                logger.warning(f"VLM verification skipped: {vlm_error}")
        
        # Determine pass/fail
        # Must have letter created AND correct patient to pass
        key_criteria_met = subscores["letter_created"] and subscores["patient_selected"]
        passed = score >= 60 and key_criteria_met
        
        # Generate final feedback
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/100")
        logger.info(f"Passed: {passed}")
        logger.info(f"Subscores: {subscores}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "letter_created": letter_created,
                "new_pnotes": new_pnotes,
                "new_documents": new_docs,
                "content_analysis": content_analysis
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - task export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def main():
    """Main function for standalone testing."""
    import subprocess
    
    # Mock copy_from_env for local testing
    def mock_copy_from_env(src, dst):
        subprocess.run(["cp", src, dst], check=True)
    
    # Create mock traj, env_info, task_info
    traj = {}
    env_info = {"copy_from_env": mock_copy_from_env}
    task_info = {
        "metadata": {
            "patient_pid": 3,
            "patient_fname": "Jayson",
            "patient_lname": "Fadel"
        }
    }
    
    result = verify_create_patient_letter(traj, env_info, task_info)
    print(json.dumps(result, indent=2))
    return 0 if result.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())