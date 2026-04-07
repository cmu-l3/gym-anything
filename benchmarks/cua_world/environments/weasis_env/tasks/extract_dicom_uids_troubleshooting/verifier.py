#!/usr/bin/env python3
"""
Verifier for extract_dicom_uids_troubleshooting task.
Combines programmatic textual verification against true DICOM metadata with VLM visual verification of the trajectory.
"""

import json
import os
import tempfile
import base64
import re
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_value(pattern, text):
    """Safely extract value from text using regex."""
    match = re.search(pattern, text)
    if match:
        return match.group(1).strip()
    return ""

def verify_extract_dicom_uids(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    # Retrieve payload from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    txt_exists = result.get('txt_exists', False)
    txt_valid = result.get('txt_valid_time', False)
    img_exists = result.get('img_exists', False)
    img_valid = result.get('img_valid_time', False)
    txt_b64 = result.get('txt_content_b64', '')
    gt = result.get('ground_truth', {})

    # Decode agent's created text file
    agent_text = ""
    if txt_b64:
        try:
            agent_text = base64.b64decode(txt_b64).decode('utf-8')
        except Exception as e:
            logger.warning(f"Failed to decode text file base64: {e}")

    # Step 1: File Check & Anti-Gaming
    if txt_exists:
        if txt_valid:
            score += 10
            feedback_parts.append("Valid text file created")
        else:
            feedback_parts.append("Text file modified before task (anti-gaming block)")
    else:
        feedback_parts.append("Text file not found")

    # Step 2: Content Validation
    agent_pat_id = extract_value(r'(?i)PatientID:\s*([^\r\n]+)', agent_text)
    agent_stu_uid = extract_value(r'(?i)StudyUID:\s*([^\r\n]+)', agent_text)
    agent_ser_uid = extract_value(r'(?i)SeriesUID:\s*([^\r\n]+)', agent_text)

    gt_pat_id = gt.get('PatientID', '').strip()
    gt_stu_uid = gt.get('StudyInstanceUID', '').strip()
    gt_ser_uid = gt.get('SeriesInstanceUID', '').strip()

    # Score Patient ID (20 pts)
    if gt_pat_id and agent_pat_id == gt_pat_id:
        score += 20
        feedback_parts.append("Patient ID correct")
    elif agent_pat_id:
        feedback_parts.append(f"Patient ID mismatch (Found: {agent_pat_id})")

    # Score Study Instance UID (25 pts)
    if gt_stu_uid and agent_stu_uid == gt_stu_uid:
        score += 25
        feedback_parts.append("Study UID correct")
    elif agent_stu_uid:
        feedback_parts.append("Study UID mismatch")

    # Score Series Instance UID (25 pts)
    if gt_ser_uid and agent_ser_uid == gt_ser_uid:
        score += 25
        feedback_parts.append("Series UID correct")
    elif agent_ser_uid:
        feedback_parts.append("Series UID mismatch")

    # Step 3: Screenshot Validation
    if img_exists and img_valid:
        score += 10
        feedback_parts.append("Screenshot saved")
    elif img_exists:
        feedback_parts.append("Screenshot exists but timing is invalid")

    # Step 4: VLM Trajectory Verification
    vlm_passed = False
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are evaluating an AI agent performing a task in Weasis DICOM Viewer.
The task is to open the "DICOM Information" or "Metadata" window to read DICOM tags.

Look at these trajectory screenshots chronologically.
1. Did the agent open the DICOM Information/Metadata window at any point? (You should see a separate panel or dialog window with a large table of technical DICOM tags like Patient Name, Modality, etc.)
2. Is the DICOM Information window clearly visible in at least one of these screenshots?

Reply in JSON format:
{
    "metadata_window_opened": true/false,
    "confidence": "high/medium/low"
}"""
        try:
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('metadata_window_opened', False):
                    vlm_passed = True
        except Exception as e:
            logger.error(f"VLM verification query failed: {e}")

    if vlm_passed:
        score += 10
        feedback_parts.append("VLM visual verification passed")
    elif VLM_AVAILABLE:
        feedback_parts.append("VLM could not confirm metadata window opened")
    else:
        # Give points if VLM is unavailable offline to prevent unfair failures
        score += 10
        feedback_parts.append("VLM offline; granting visual confirmation points")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }