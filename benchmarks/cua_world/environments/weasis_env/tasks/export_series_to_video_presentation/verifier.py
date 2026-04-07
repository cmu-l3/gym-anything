#!/usr/bin/env python3
"""
Verifier for the Video Export presentation task in Weasis.

Verification Criteria:
1. Programmatic File Check (Primary):
   - File exists at correct path (anatomy_scroll.avi or .mp4)
   - Created during the task (timestamp validation)
   - Size heuristic (> 10KB) to ensure it's not empty
   - Magic Bytes validation (ensures it is a real AVI/MP4 video, not a renamed image)

2. VLM Trajectory Verification (Secondary):
   - Confirms the agent interacted with the Video Export dialog.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an agent's trajectory performing a video export in a medical imaging viewer (Weasis).

Analyze the sequence of screenshots.
Look for a dialog box related to "Export Video", "Video Export", or saving an AVI/MP4.
Did the agent open the video export interface and interact with it?

Respond in JSON format:
{
    "video_export_dialog_seen": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_video_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    size_bytes = result.get("output_size_bytes", 0)
    header_hex = result.get("header_hex", "").lower()
    filename_used = result.get("filename_used", "")

    # CRITERION 1: File Existence (20 points)
    if output_exists:
        score += 20
        feedback_parts.append(f"Output found ({filename_used})")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Timestamp validation (10 points)
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during session")
    else:
        feedback_parts.append("File timestamp invalid (pre-existing)")

    # CRITERION 3: Size heuristic (15 points)
    # Even heavily compressed low-res 10-frame videos are usually > 10KB
    if size_bytes >= 10240:
        score += 15
        feedback_parts.append(f"Size OK ({size_bytes//1024} KB)")
    elif size_bytes > 0:
        score += 5
        feedback_parts.append(f"Size surprisingly small ({size_bytes} bytes)")
    else:
        feedback_parts.append("File is empty")

    # CRITERION 4: Header Validation / Magic Bytes (40 points)
    # AVI magic bytes: 52494646 (RIFF) ... 41564920 (AVI ) at offset 8
    # MP4 magic bytes: 66747970 (ftyp) at offset 4
    is_avi = header_hex.startswith("52494646") and len(header_hex) >= 24 and header_hex[16:24] == "41564920"
    is_mp4 = len(header_hex) >= 16 and header_hex[8:16] == "66747970"
    
    valid_header = is_avi or is_mp4
    
    if valid_header:
        score += 40
        format_detected = "AVI" if is_avi else "MP4"
        feedback_parts.append(f"Valid video header ({format_detected})")
    else:
        feedback_parts.append(f"Invalid/Missing video magic bytes: {header_hex[:16]}...")

    # CRITERION 5: VLM Trajectory check (15 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("video_export_dialog_seen", False):
                score += 15
                feedback_parts.append("VLM confirmed video export dialog")
            else:
                feedback_parts.append("VLM did not detect video export dialog")
        else:
            feedback_parts.append("VLM query failed")
    except Exception as e:
        logger.warning(f"VLM evaluation error: {e}")
        feedback_parts.append("VLM check skipped")

    # Pass threshold: 80 points AND the file MUST have a valid video header (no faking images as video)
    passed = (score >= 80) and valid_header

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }