#!/usr/bin/env python3
"""
Verifier for draw_roi_statistics task.

Verification Strategy:
1. Validates that both required files exist and were modified/created during the task.
2. Parses the statistics text file to extract Mean and StdDev.
3. Checks if the recorded Mean is within the expected plausible range.
4. Uses VLM on the trajectory to visually confirm an elliptical ROI was drawn on the center.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing screenshots from a medical imaging application (Weasis).
The user was asked to draw an elliptical/oval Region of Interest (ROI) on the bright circular structure in the center of the CT image.

Look at the sequence of images and determine:
1. Is there an elliptical or oval annotation (ROI) visible on the medical image in any of the frames?
2. Is this ROI annotation positioned on or overlapping the bright circular structure located in the center of the image?

Respond ONLY in valid JSON format:
{
    "roi_drawn": true/false,
    "roi_on_target": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see"
}
"""

def extract_trajectory_frames(traj, num_frames=3):
    """Extract a few evenly spaced frames from the trajectory."""
    frames = []
    if not traj:
        return frames
    steps = len(traj)
    if steps == 0:
        return frames
    
    # Get indices for evenly spaced frames + the final frame
    indices = [int(i * (steps - 1) / (num_frames - 1)) for i in range(num_frames)] if num_frames > 1 else [steps - 1]
    
    for idx in indices:
        obs = traj[idx].get('obs', {})
        # Different environments might key the screenshot differently
        for k, v in obs.items():
            if 'screen' in k.lower() or 'image' in k.lower() or k == 'screenshot':
                frames.append(v)
                break
                
    # Always include the very last frame just in case
    if steps > 0:
        final_obs = traj[-1].get('obs', {})
        for k, v in final_obs.items():
            if 'screen' in k.lower() or 'image' in k.lower() or k == 'screenshot':
                if v not in frames:
                    frames.append(v)
                break
                
    return frames

def verify_draw_roi_statistics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    mean_min = metadata.get('mean_min', 500)
    mean_max = metadata.get('mean_max', 3000)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
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

    task_start_time = result.get('task_start_time', 0)
    stats_exists = result.get('stats_file_exists', False)
    stats_mtime = result.get('stats_file_mtime', 0)
    annot_exists = result.get('annotated_file_exists', False)
    annot_mtime = result.get('annotated_file_mtime', 0)
    stats_content = result.get('stats_content', '')

    # Check File 1: Statistics text
    if stats_exists and stats_mtime >= task_start_time:
        score += 15
        feedback_parts.append("Stats file created")
    else:
        feedback_parts.append("Stats file missing or old")

    # Check File 2: Annotated image
    if annot_exists and annot_mtime >= task_start_time:
        score += 15
        feedback_parts.append("Annotated image exported")
    else:
        feedback_parts.append("Annotated image missing or old")

    # 2. Parse the statistics content
    mean_val = None
    std_val = None
    
    mean_match = re.search(r'Mean:\s*([0-9.-]+)', stats_content, re.IGNORECASE)
    if mean_match:
        try:
            mean_val = float(mean_match.group(1))
            score += 15
            feedback_parts.append(f"Mean parsed ({mean_val})")
        except ValueError:
            feedback_parts.append("Mean is not numeric")
    else:
        feedback_parts.append("Mean not found in text")

    std_match = re.search(r'StdDev:\s*([0-9.-]+)', stats_content, re.IGNORECASE)
    if std_match:
        try:
            std_val = float(std_match.group(1))
            score += 10
            feedback_parts.append("StdDev parsed")
        except ValueError:
            feedback_parts.append("StdDev is not numeric")
    else:
        feedback_parts.append("StdDev not found in text")

    # 3. Check Plausibility of Data
    if mean_val is not None:
        if mean_min <= mean_val <= mean_max:
            score += 15
            feedback_parts.append("Mean is plausible")
        else:
            feedback_parts.append(f"Mean {mean_val} outside plausible range ({mean_min}-{mean_max})")

    # 4. VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    frames = extract_trajectory_frames(traj, num_frames=3)
    
    if query_vlm and frames:
        try:
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                roi_drawn = parsed.get("roi_drawn", False)
                roi_on_target = parsed.get("roi_on_target", False)
                
                if roi_drawn:
                    score += 15
                    feedback_parts.append("VLM confirms ROI drawn")
                else:
                    feedback_parts.append("VLM: No ROI annotation seen")
                    
                if roi_on_target:
                    score += 15
                    feedback_parts.append("VLM confirms ROI on target structure")
                else:
                    feedback_parts.append("VLM: ROI not positioned on target")
            else:
                feedback_parts.append("VLM verification failed to parse")
        except Exception as e:
            logger.error(f"VLM exception: {e}")
            feedback_parts.append("VLM execution error")
    else:
        feedback_parts.append("VLM not available or no frames extracted")

    # Ensure score doesn't exceed 100
    score = min(score, 100)
    
    # Pass condition: Requires at least 60 points, which effectively mandates file creation and either good content or VLM confirmation
    key_criteria_met = stats_exists and (mean_val is not None)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }