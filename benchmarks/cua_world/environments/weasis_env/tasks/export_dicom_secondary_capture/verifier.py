#!/usr/bin/env python3
"""
Verifier for Export Annotated Secondary Capture task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Assuming gym_anything vlm utilities are available in the verification environment
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent performing a medical image annotation and export task in Weasis DICOM Viewer.
Please review these chronologically sampled screenshots from the agent's interaction.

Assess the following criteria:
1. ANNOTATION_DRAWN: Did the agent draw a visible annotation (e.g., a colored line, arrow, angle, or rectangle) on the grayscale medical image?
2. EXPORT_DIALOG_OPENED: Did the agent open the "Export Views" dialog?
3. DICOM_FORMAT_SELECTED: In the export dialog, is the format clearly set to "DICOM" (not PNG/JPEG)?

Respond ONLY in valid JSON format exactly matching this structure:
{
    "annotation_drawn": true/false,
    "export_dialog_opened": true/false,
    "dicom_format_selected": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_export_secondary_capture(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sc_sop = metadata.get('secondary_capture_sop', '1.2.840.10008.5.1.4.1.1.7')

    # Read exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    dicom_data = result.get("dicom_analysis", {})
    
    score = 0
    feedback_parts = []
    
    # 1. Basic File Checks (15 points)
    if dicom_data.get("output_exists"):
        if dicom_data.get("file_created_during_task"):
            score += 15
            feedback_parts.append("✅ File exported successfully")
        else:
            feedback_parts.append("❌ File exists but was not created during task (stale)")
    else:
        feedback_parts.append("❌ Target DICOM file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. DICOM Validity & Payload (30 points)
    if dicom_data.get("is_valid_dicom"):
        score += 15
        if dicom_data.get("has_pixel_data"):
            score += 15
            feedback_parts.append("✅ Valid DICOM with pixel data")
        else:
            feedback_parts.append("❌ DICOM is valid but missing PixelData payload")
    else:
        err = dicom_data.get("error", "Unknown error parsing DICOM")
        feedback_parts.append(f"❌ File is not a valid DICOM ({err})")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. View Export verification (Anti-gaming check) (30 points)
    # A true 'View' export capturing annotations typically saves as RGB/YBR (3 samples) or uses the SC SOP Class.
    # Simply copying the source CT file yields MONOCHROME2 (1 sample).
    samples = dicom_data.get("samples_per_pixel", 0)
    pi = dicom_data.get("photometric_interpretation", "")
    sop = dicom_data.get("sop_class_uid", "")
    
    is_view_export = False
    if sop == expected_sc_sop:
        is_view_export = True
        feedback_parts.append("✅ SC Image Storage SOP confirmed")
    elif samples == 3 or pi in ["RGB", "YBR_FULL"]:
        is_view_export = True
        feedback_parts.append("✅ RGB encoding confirmed (captured view)")
    
    if is_view_export:
        score += 30
    else:
        feedback_parts.append(f"❌ Export appears to be source copy, not a captured view (Samples: {samples}, PI: {pi}, SOP: {sop})")

    # 4. VLM Trajectory Analysis (25 points)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                vlm_data = vlm_response.get("parsed", {})
                if vlm_data.get("annotation_drawn"):
                    vlm_score += 10
                    feedback_parts.append("✅ VLM: Annotation visible")
                if vlm_data.get("export_dialog_opened"):
                    vlm_score += 10
                    feedback_parts.append("✅ VLM: Export dialog used")
                if vlm_data.get("dicom_format_selected"):
                    vlm_score += 5
            else:
                feedback_parts.append("⚠️ VLM verification failed or unparseable")
        else:
            feedback_parts.append("⚠️ No trajectory frames for VLM")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append("⚠️ VLM error occurred")

    score += vlm_score

    # Determine Pass/Fail (Must get valid DICOM and verify it is a view export)
    passed = score >= 70 and dicom_data.get("is_valid_dicom") and is_view_export

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }