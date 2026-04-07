#!/usr/bin/env python3
"""
Verifier for Create Annotated Secondary Capture task.
"""

import sys
import os
import json
import logging
import tempfile

# Attempt to import VLM utilities for trajectory verification
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # If not running in framework context where this is available, fail gracefully
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent performing a medical imaging task in Weasis DICOM Viewer.
The agent was asked to:
1. Draw an arrow annotation pointing to a distinct anatomical structure on the loaded medical image.
2. Export the current view (the 'Displayed image') as a DICOM file using the export dialog.

Look carefully at the provided screenshots from the agent's workflow trajectory and determine:
1. Is there evidence that an annotation (like an arrow) was drawn over the medical image? 
2. Is there evidence that the agent opened an export/save dialog (such as 'DICOM Export') to save the image?

Return your assessment in the following JSON format:
{
    "arrow_annotation_drawn": true/false,
    "export_dialog_opened": true/false,
    "reasoning": "Brief explanation of what you see in the images to justify the booleans."
}
"""

def verify_create_secondary_capture(traj, env_info, task_info):
    """
    Verify that an annotated secondary capture was created and exported correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sop_prefix = metadata.get('expected_sop_class_prefix', '1.2.840.10008.5.1.4.1.1.7')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: File exists and was created during the task (Anti-gaming) (20 points)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and created_during_task:
        score += 20
        feedback_parts.append("Exported file created successfully.")
    elif output_exists:
        feedback_parts.append("Exported file found, but timestamp predates task (stale/gamed).")
    else:
        feedback_parts.append("Target DICOM file was not found.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Valid DICOM (Parsed successfully by pydicom) (20 points)
    parse_error = result.get('parse_error', "")
    sop_class_uid = result.get('sop_class_uid', "")
    
    if not parse_error and sop_class_uid:
        score += 20
        feedback_parts.append("Valid DICOM format confirmed.")
    else:
        feedback_parts.append(f"Invalid DICOM or parsing error: {parse_error}")

    # Criterion 3: SOP Class UID is Secondary Capture (30 points)
    # This proves they exported the "Displayed image" (with annotations burned in) 
    # instead of the "Original" DICOM which would retain MR/CT Image Storage UID.
    if sop_class_uid.startswith(expected_sop_prefix):
        score += 30
        feedback_parts.append(f"Correct SOP Class UID (Secondary Capture).")
    else:
        feedback_parts.append(f"Incorrect SOP Class UID ({sop_class_uid}). The agent likely exported the 'Original' image instead of the 'Displayed image'.")

    # Criterion 4: VLM Verification of workflow (Trajectory check) (30 points)
    try:
        # Sample trajectory frames specifically looking for annotations and dialogs
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_response.get("success") and "parsed" in vlm_response:
            parsed = vlm_response["parsed"]
            
            arrow_drawn = parsed.get("arrow_annotation_drawn", False)
            export_opened = parsed.get("export_dialog_opened", False)
            
            if arrow_drawn and export_opened:
                score += 30
                feedback_parts.append("VLM verified annotation drawn and export dialog used.")
            elif arrow_drawn:
                score += 15
                feedback_parts.append("VLM verified annotation drawn, but missed export dialog evidence.")
            elif export_opened:
                score += 15
                feedback_parts.append("VLM verified export dialog used, but missing annotation evidence.")
            else:
                feedback_parts.append("VLM could not verify annotation or export workflow.")
        else:
            feedback_parts.append("VLM verification failed or unavailable.")
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        feedback_parts.append("VLM verification skipped due to error.")

    # Determine pass/fail
    # Must get at least 70% and successfully export a valid SC file
    passed = score >= 70 and sop_class_uid.startswith(expected_sop_prefix)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }