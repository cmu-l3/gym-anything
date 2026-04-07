#!/usr/bin/env python3
"""
Verifier for analyze_histogram task.
Checks output file contents, timestamps (anti-gaming), and process trajectory.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_histogram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames
        vlm_available = True
    except ImportError:
        vlm_available = False
        logger.warning("VLM utilities not available.")

    score = 0
    feedback_parts = []
    
    # 1. Fetch task result (agent actions)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Fetch ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/ground_truth/pixel_stats.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Criterion 1 & 2: File exists and created during task (10 pts)
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if file_exists and file_created:
        score += 10
        feedback_parts.append("Report file created during task")
    elif file_exists:
        score += 5
        feedback_parts.append("Report file exists (but might be old)")
    else:
        feedback_parts.append("Report file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 3: Format correct and parse values (10 pts)
    content = result.get('file_content', '')
    parsed = {}
    
    match_min = re.search(r'min\s*:\s*([+-]?\d+\.?\d*)', content, re.IGNORECASE)
    match_max = re.search(r'max\s*:\s*([+-]?\d+\.?\d*)', content, re.IGNORECASE)
    match_mean = re.search(r'mean\s*:\s*([+-]?\d+\.?\d*)', content, re.IGNORECASE)
    
    if match_min: parsed['min'] = float(match_min.group(1))
    if match_max: parsed['max'] = float(match_max.group(1))
    if match_mean: parsed['mean'] = float(match_mean.group(1))
    
    if len(parsed) == 3:
        score += 10
        feedback_parts.append("Report format correct")
    else:
        feedback_parts.append(f"Format incomplete (parsed {len(parsed)}/3 values)")
        
    correct_values = 0
    
    # Criterion 4-6: Check Min, Max, Mean Accuracy (60 pts)
    if 'min' in parsed and 'min' in gt:
        if abs(parsed['min'] - gt['min']) <= 50:
            score += 20
            correct_values += 1
            feedback_parts.append("Min accurate")
        else:
            feedback_parts.append(f"Min inaccurate (Got {parsed['min']})")
            
    if 'max' in parsed and 'max' in gt:
        if abs(parsed['max'] - gt['max']) <= 50:
            score += 20
            correct_values += 1
            feedback_parts.append("Max accurate")
        else:
            feedback_parts.append(f"Max inaccurate (Got {parsed['max']})")
            
    if 'mean' in parsed and 'mean' in gt:
        if abs(parsed['mean'] - gt['mean']) <= 100:
            score += 20
            correct_values += 1
            feedback_parts.append("Mean accurate")
        else:
            feedback_parts.append(f"Mean inaccurate (Got {parsed['mean']})")

    # Criterion 7: VLM Verification of Trajectory (20 pts)
    # Proves the agent actually opened the UI rather than guessing values
    if vlm_available and traj:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = (
                "You are verifying if an AI agent opened the 'Histogram' or 'Image Statistics' panel in a medical viewer.\n"
                "Look closely at these screenshots. Is there a visible panel/window displaying a histogram graph/chart "
                "with statistical numbers (like min, max, mean) alongside it?\n"
                "Respond in JSON format with exactly this schema:\n"
                "{\"histogram_visible\": true/false}"
            )
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if isinstance(vlm_res, dict) and vlm_res.get('histogram_visible') is True:
                    score += 20
                    feedback_parts.append("VLM confirmed histogram panel visible")
                else:
                    feedback_parts.append("VLM did not detect histogram panel")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("VLM verification failed")
    else:
        # Give partial credit if VLM unavailable but numbers are perfectly correct
        if correct_values >= 2:
            score += 20
            feedback_parts.append("VLM skipped (credited based on accurate values)")

    # Overall pass criteria: Score >= 65 and at least 2 correct values
    passed = (score >= 65) and (correct_values >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }