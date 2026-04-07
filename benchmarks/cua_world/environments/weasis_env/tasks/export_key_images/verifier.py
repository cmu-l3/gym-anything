#!/usr/bin/env python3
"""
Verifier for Export Key Images task in Weasis.

Verification Strategy:
1. PROGRAMMATIC (80 points):
   - Exact count: Checks that exactly 2 valid JPEG files exist in the target directory. 
     (If 1 exists, agent exported 'Current'. If 10 exist, agent exported 'All'. Exactly 2 proves use of 'Key Images' filter).
   - Validity: Files > 10KB.
   - Timestamps: Files created after task start time (anti-gaming).
2. VLM TRAJECTORY (20 points):
   - Confirms the agent's process via trajectory frames (navigating, toggling star/bookmark, configuring export).
"""

import sys
import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to analyze the agent's workflow trajectory
VLM_TRAJECTORY_PROMPT = """You are evaluating an AI agent's trajectory for a medical image curation task in Weasis DICOM Viewer.
The agent was asked to:
1. Navigate to specific slices in a CT scan.
2. Bookmark/Flag them using the 'Key Image' tool (typically a star icon).
3. Open the Export Image dialog.
4. Set the export scope to "Key Images".

Look at these sampled trajectory frames and answer the following boolean questions:
1. "used_bookmark_tool": Is there visual evidence the agent clicked the Key Image (Star) icon or context menu item to bookmark a slice?
2. "opened_export_dialog": Did the agent open an "Export Image" dialog window?
3. "selected_key_images_scope": In the Export dialog, is the scope/range dropdown set to "Key Images" (rather than "Current image" or "All images")?

Respond ONLY with a valid JSON object matching exactly this format:
{
    "used_bookmark_tool": true/false,
    "opened_export_dialog": true/false,
    "selected_key_images_scope": true/false,
    "reasoning": "Brief explanation of what is visible in the frames."
}
"""

def verify_export_key_images(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read programmatic results
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

    score = 0
    feedback_parts = []
    
    file_count = result.get('file_count', 0)
    all_files_valid_size = result.get('all_files_valid_size', False)
    all_files_after_start = result.get('all_files_after_start', False)

    # CRITERION 1: Exact File Count (40 points)
    # The mathematical cornerstone of this task to prevent gaming.
    if file_count == 2:
        score += 40
        feedback_parts.append("Correct file count (exactly 2 key images)")
    else:
        feedback_parts.append(f"Incorrect file count (found {file_count}, expected 2). Indicates wrong export scope.")

    # CRITERION 2: File Validity / Format (20 points)
    if file_count > 0:
        if all_files_valid_size:
            score += 20
            feedback_parts.append("Files are valid size/format")
        else:
            feedback_parts.append("Some exported files are suspiciously small (invalid format)")

    # CRITERION 3: Timestamp Anti-Gaming (20 points)
    if file_count > 0:
        if all_files_after_start:
            score += 20
            feedback_parts.append("Files generated during active task session")
        else:
            feedback_parts.append("FAIL: Files predate task start (Anti-gaming triggered)")

    # CRITERION 4: VLM Trajectory Verification (20 points)
    # Uses gym_anything framework tools to sample frames securely
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_result = query_vlm(images=frames, prompt=VLM_TRAJECTORY_PROMPT)
        
        if vlm_result and vlm_result.get("success") and vlm_result.get("parsed"):
            parsed = vlm_result["parsed"]
            if parsed.get("used_bookmark_tool", False):
                vlm_score += 10
            if parsed.get("opened_export_dialog", False) and parsed.get("selected_key_images_scope", False):
                vlm_score += 10
                
            if vlm_score > 0:
                score += vlm_score
                feedback_parts.append(f"VLM verified workflow (+{vlm_score} pts)")
            else:
                feedback_parts.append("VLM did not detect correct workflow steps")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM fails due to environment restrictions, we don't severely penalize if programmatic is perfect
        if score == 80:
            feedback_parts.append("Programmatic checks perfect, VLM skipped")

    # Final logic: 
    # Must have exact count to pass.
    passed = (file_count == 2) and all_files_after_start and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }