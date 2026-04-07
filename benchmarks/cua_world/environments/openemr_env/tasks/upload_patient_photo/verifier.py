#!/usr/bin/env python3
"""
Verifier for Upload Patient Photo task in OpenEMR

Verifies that a patient photograph was successfully uploaded to the correct
patient's medical record.

Verification Strategy:
1. Check if new document was created for the patient during task window
2. Check if patient_data photo field was updated
3. Check for new image files in OpenEMR documents directory
4. Use VLM to verify photo appears in trajectory screenshots
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_upload_patient_photo(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a patient photo was uploaded to the correct patient.

    Scoring (100 points total):
    - Correct patient accessed (pid=3): 15 points
    - Photo upload initiated (evidence in trajectory): 15 points
    - Photo file correctly handled: 15 points
    - Photo saved to patient record: 25 points
    - Photo visible in chart (VLM): 20 points
    - Upload timestamp valid (anti-gaming): 10 points

    Passing threshold: 70 points with "photo saved to patient" criterion met
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

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/upload_patient_photo_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient_accessed": False,
            "photo_upload_initiated": False,
            "photo_file_selected": False,
            "photo_saved_to_patient": False,
            "photo_visible_in_chart": False,
            "upload_timestamp_valid": False
        }

        # Extract data from export
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start', 0)
        task_end = result.get('task_end', 0)
        initial_doc_count = result.get('initial_doc_count', 0)
        current_doc_count = result.get('current_doc_count', 0)
        doc_found = result.get('document_found', False)
        document = result.get('document', {})
        doc_created_during_task = result.get('doc_created_during_task', False)
        photo_field_changed = result.get('photo_field_changed', False)
        new_image_count = result.get('new_image_file_count', 0)
        photo_uploaded = result.get('photo_uploaded', False)
        firefox_running = result.get('firefox_running', False)

        logger.info(f"Result data: pid={patient_pid}, doc_found={doc_found}, "
                   f"doc_created_during_task={doc_created_during_task}, "
                   f"photo_field_changed={photo_field_changed}, "
                   f"new_images={new_image_count}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient_accessed"] = True
            feedback_parts.append(f"✓ Correct patient targeted (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Photo uploaded to wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Photo upload initiated (15 points)
        # Evidence: file browser interaction, document count changed, or new files
        upload_evidence = (
            current_doc_count > initial_doc_count or
            photo_field_changed or
            new_image_count > 0
        )
        if upload_evidence:
            score += 15
            subscores["photo_upload_initiated"] = True
            feedback_parts.append("✓ Photo upload process detected")
        else:
            feedback_parts.append("✗ No evidence of photo upload initiation")

        # CRITERION 3: Photo file correctly handled (15 points)
        # Check if a document or file was actually created/modified
        if doc_found or new_image_count > 0 or photo_field_changed:
            score += 15
            subscores["photo_file_selected"] = True
            if doc_found:
                doc_url = document.get('url', '')
                feedback_parts.append(f"✓ Photo file processed (doc: {doc_url[:50] if doc_url else 'N/A'})")
            elif new_image_count > 0:
                feedback_parts.append(f"✓ {new_image_count} new image file(s) detected")
            else:
                feedback_parts.append("✓ Photo field updated in patient record")
        else:
            feedback_parts.append("✗ No photo file was processed")

        # CRITERION 4: Photo saved to patient record (25 points) - CRITICAL
        photo_saved = False
        
        # Check multiple indicators that photo was saved
        if doc_created_during_task:
            photo_saved = True
            feedback_parts.append("✓ Document record created during task")
        elif photo_field_changed:
            photo_saved = True
            feedback_parts.append("✓ Patient photo field updated")
        elif new_image_count > 0 and current_doc_count > initial_doc_count:
            photo_saved = True
            feedback_parts.append("✓ New image linked to patient")
        elif current_doc_count > initial_doc_count:
            # Document was added, even if we can't confirm exact timing
            photo_saved = True
            feedback_parts.append("✓ New document added to patient record")

        if photo_saved:
            score += 25
            subscores["photo_saved_to_patient"] = True
        else:
            feedback_parts.append("✗ No photo was saved to patient record")

        # CRITERION 5: Photo visible in chart (20 points) - VLM verification
        # Use trajectory frames to verify workflow was followed
        query_vlm = env_info.get('query_vlm')
        vlm_verified = False
        
        if query_vlm:
            try:
                vlm_result = verify_via_vlm(traj, query_vlm)
                if vlm_result.get('photo_workflow_detected', False):
                    vlm_verified = True
                    score += 20
                    subscores["photo_visible_in_chart"] = True
                    feedback_parts.append("✓ VLM confirmed photo workflow in trajectory")
                elif vlm_result.get('partial_workflow', False):
                    # Partial credit for attempting the workflow
                    score += 10
                    feedback_parts.append("~ VLM detected partial photo workflow")
                else:
                    feedback_parts.append(f"✗ VLM could not confirm photo workflow: {vlm_result.get('reasoning', 'N/A')}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append(f"~ VLM verification skipped: {str(e)[:50]}")
                # Give partial credit if other evidence is strong
                if photo_saved and upload_evidence:
                    score += 10
                    feedback_parts.append("~ Partial VLM credit (strong other evidence)")
        else:
            feedback_parts.append("~ VLM not available for visual verification")
            # Give partial credit if we have strong programmatic evidence
            if photo_saved:
                score += 10

        # CRITERION 6: Upload timestamp valid (10 points) - anti-gaming
        if doc_created_during_task:
            score += 10
            subscores["upload_timestamp_valid"] = True
            feedback_parts.append("✓ Upload timestamp verified (created during task)")
        elif photo_field_changed:
            # Field change is also valid evidence
            score += 10
            subscores["upload_timestamp_valid"] = True
            feedback_parts.append("✓ Photo change detected during task window")
        elif new_image_count > 0:
            # New files were created
            score += 10
            subscores["upload_timestamp_valid"] = True
            feedback_parts.append("✓ New image files created during task")
        else:
            feedback_parts.append("✗ Cannot verify upload occurred during task")

        # Determine pass/fail
        # Must have photo_saved AND score >= 70
        passed = photo_saved and score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "doc_count_change": current_doc_count - initial_doc_count,
                "photo_field_changed": photo_field_changed,
                "new_image_files": new_image_count,
                "firefox_running": firefox_running
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """
    Use VLM to verify photo upload workflow from trajectory screenshots.
    
    Checks trajectory frames (not just final screenshot) to detect:
    1. Navigation to patient demographics
    2. File upload dialog interaction
    3. Photo visible in patient record
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"photo_workflow_detected": False, "reasoning": "No screenshots available"}
        
        # Combine trajectory frames with final screenshot
        all_frames = frames + ([final] if final else [])
        
        # VLM prompt for trajectory analysis
        vlm_prompt = """Analyze these sequential screenshots from an OpenEMR (medical records system) session.

TASK: Upload a patient photograph to their medical record.

Look for evidence of EACH of these steps in the screenshots:
1. Patient record/demographics page was accessed
2. File upload dialog or photo selection interface appeared
3. A patient photo/image appears in the patient's record

For each screenshot, identify:
- Is this OpenEMR or a medical records interface?
- Is there a patient photo visible on the page?
- Is there a file browser/upload dialog?
- Is there a patient demographics or photo management section?

Respond in JSON format:
{
    "is_openemr_interface": true/false,
    "patient_demographics_visible": true/false,
    "file_upload_dialog_visible": true/false,
    "patient_photo_visible_in_record": true/false,
    "photo_workflow_detected": true/false,
    "partial_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what workflow steps were observed"
}

A "photo_workflow_detected" should be true if you see clear evidence of patient photo being uploaded or displayed in the patient record.
A "partial_workflow" should be true if you see some steps but not the complete workflow."""
        
        # Query VLM with all frames
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_result.get("success"):
            return {
                "photo_workflow_detected": False,
                "reasoning": f"VLM query failed: {vlm_result.get('error', 'Unknown error')}"
            }
        
        parsed = vlm_result.get("parsed", {})
        return {
            "photo_workflow_detected": parsed.get("photo_workflow_detected", False),
            "partial_workflow": parsed.get("partial_workflow", False),
            "patient_photo_visible": parsed.get("patient_photo_visible_in_record", False),
            "confidence": parsed.get("confidence", "low"),
            "reasoning": parsed.get("reasoning", "")
        }
        
    except ImportError:
        logger.warning("gym_anything.vlm not available")
        return {"photo_workflow_detected": False, "reasoning": "VLM module not available"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"photo_workflow_detected": False, "reasoning": str(e)}