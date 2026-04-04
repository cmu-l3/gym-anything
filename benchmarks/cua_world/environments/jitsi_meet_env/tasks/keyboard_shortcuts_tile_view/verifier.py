#!/usr/bin/env python3
"""
Verifier for keyboard_shortcuts_tile_view task.

Verification Criteria:
1. File Existence & Timing (15 pts): ~/shortcuts_reference.txt exists and created during task.
2. File Content (35 pts): Contains >= 5 lines, each with a valid Jitsi shortcut key.
3. VLM Process (25 pts): Trajectory shows the shortcuts help dialog was opened.
4. VLM Result (25 pts): Final screenshot shows meeting in Tile View.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_keyboard_shortcuts_tile_view(traj, env_info, task_info):
    """
    Verifies that the agent documented shortcuts and toggled tile view.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    valid_keys = set(metadata.get('valid_keys', ["T", "M", "V", "C", "R", "F", "S", "D", "?", "SPACE"]))
    
    score = 0
    feedback_parts = []
    
    # ====================================================================
    # 1. Programmatic Verification: File Checks
    # ====================================================================
    
    # Fetch result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf_json:
        try:
            copy_from_env("/tmp/task_result.json", tf_json.name)
            tf_json.seek(0)
            result_data = json.load(tf_json)
        except Exception as e:
            logger.error(f"Failed to load task result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}

    file_exists = result_data.get("file_exists", False)
    created_during = result_data.get("file_created_during_task", False)
    
    # Check 1: File Existence & Anti-Gaming (15 pts)
    if file_exists:
        if created_during:
            score += 15
            feedback_parts.append("File created successfully during task.")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp is old (possible pre-existing file).")
    else:
        feedback_parts.append("Output file shortcuts_reference.txt not found.")

    # Check 2: File Content Validation (35 pts)
    # We need to pull the actual text file to check content
    valid_shortcuts_found = 0
    lines_checked = 0
    
    if file_exists:
        with tempfile.NamedTemporaryFile(mode='w+', suffix='.txt') as tf_txt:
            try:
                copy_from_env("/home/ga/shortcuts_reference.txt", tf_txt.name)
                tf_txt.seek(0)
                content = tf_txt.readlines()
                
                for line in content:
                    line = line.strip()
                    if not line:
                        continue
                    lines_checked += 1
                    
                    # Expected format: "K - Description"
                    # We check if the line starts with a valid key followed by separator
                    parts = line.split('-', 1)
                    if len(parts) < 2:
                        parts = line.split(' ', 1) # Fallback for space separator
                    
                    if len(parts) >= 2:
                        key_part = parts[0].strip().upper()
                        if key_part in valid_keys:
                            valid_shortcuts_found += 1
                        # Handle "SHIFT+T" or similar if agent writes modifiers
                        elif any(vk in key_part for vk in valid_keys):
                             # Lenient check: if "T" is in "Shift+T", count it
                             valid_shortcuts_found += 1
            except Exception as e:
                logger.error(f"Failed to read text file content: {e}")
                feedback_parts.append("Error reading output file content.")

    # Scoring content
    # Cap at 5 shortcuts, 7 points each = 35 pts
    counted_shortcuts = min(valid_shortcuts_found, 5)
    content_score = counted_shortcuts * 7
    score += content_score
    
    if valid_shortcuts_found > 0:
        feedback_parts.append(f"Found {valid_shortcuts_found} valid shortcuts documented.")
    elif file_exists:
        feedback_parts.append("File exists but contains no recognizable valid shortcuts.")

    # ====================================================================
    # 2. VLM Verification
    # ====================================================================
    
    # Sample trajectory frames for process verification
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    # VLM Check 1: Did they open the help dialog? (25 pts)
    process_prompt = """
    Review these screenshots of a Jitsi Meet session.
    I am looking for evidence that the user opened the 'Keyboard Shortcuts' help dialog/overlay.
    
    1. Do you see a modal or popup window listing keyboard shortcuts (e.g., listing keys like 'M', 'T', 'V' with descriptions)?
    2. Do you see the meeting interface?
    
    Return JSON:
    {
        "shortcuts_dialog_seen": true/false,
        "meeting_interface_seen": true/false
    }
    """
    
    vlm_process_score = 0
    try:
        # We pass the sequence of frames to check for the dialog appearing at any point
        res_process = query_vlm(prompt=process_prompt, images=frames)
        if res_process and res_process.get("success"):
            parsed = res_process.get("parsed", {})
            if parsed.get("shortcuts_dialog_seen"):
                vlm_process_score = 25
                feedback_parts.append("VLM confirmed shortcuts dialog was opened.")
            elif parsed.get("meeting_interface_seen"):
                # Partial credit if they were in the meeting but didn't show dialog (maybe they know shortcuts by heart? 
                # Task required 'open... dialog', but we give 5 pts for being in meeting)
                vlm_process_score = 5
                feedback_parts.append("VLM saw meeting but NOT the shortcuts dialog.")
            else:
                feedback_parts.append("VLM did not see Jitsi meeting interface.")
    except Exception as e:
        logger.error(f"VLM process check failed: {e}")
    
    score += vlm_process_score

    # VLM Check 2: Is Tile View active at the end? (25 pts)
    # This must be checked on the FINAL frame
    layout_prompt = """
    Analyze this final screenshot of a Jitsi Meet session.
    
    Is the view in 'Tile View' (Grid View)?
    - Tile View: Participants are arranged in a grid of equal-sized rectangles.
    - Speaker View: One large central video with a small row of thumbnails (filmstrip) on the side or bottom.
    - Pre-join screen: Input field for name, 'Join meeting' button.
    
    Return JSON:
    {
        "layout": "tile_view" or "speaker_view" or "pre_join" or "unknown",
        "confidence": "high" or "low"
    }
    """
    
    vlm_layout_score = 0
    try:
        res_layout = query_vlm(prompt=layout_prompt, image=final_frame)
        if res_layout and res_layout.get("success"):
            parsed = res_layout.get("parsed", {})
            layout = parsed.get("layout", "unknown")
            
            if layout == "tile_view":
                vlm_layout_score = 25
                feedback_parts.append("VLM confirmed Tile View is active.")
            elif layout == "speaker_view":
                feedback_parts.append("Meeting is in Speaker View, not Tile View.")
            elif layout == "pre_join":
                feedback_parts.append("Agent remained on pre-join screen.")
    except Exception as e:
        logger.error(f"VLM layout check failed: {e}")
        
    score += vlm_layout_score

    # ====================================================================
    # Final Result
    # ====================================================================
    
    # Pass threshold: 60 points. 
    # Must have file with SOME content (at least 15+7=22) + Tile view (25) + Dialog (25) = 72
    # Or File (15+35=50) + Tile View (25) = 75
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }