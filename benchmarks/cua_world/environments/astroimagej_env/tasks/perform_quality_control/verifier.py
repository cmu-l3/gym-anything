#!/usr/bin/env python3
"""
Verifier for Quality Control task.

Verifies that the agent correctly identified the 3 artificially degraded
images from the sequence of 25 real FITS files.

Scoring (100 points total):
  - Report exists and valid (10 pts)
  - Frame 06 identified (20 pts)
  - Frame 14 identified (20 pts)
  - Frame 21 identified (20 pts)
  - No False Positives (15 pts)
  - VLM Process Verification (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def verify_quality_control(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Copy ground truth JSON from container
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/qc_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    score = 0
    feedback = []
    
    report_exists = result.get("report_exists", False)
    if not report_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "bad_frames.txt not found on Desktop"
        }
        
    score += 10
    feedback.append("Report file created")
    
    # Check modification time to prevent gaming
    task_start = result.get("task_start_time", 0)
    report_mtime = result.get("report_mtime", 0)
    if report_mtime > 0 and report_mtime < task_start:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file is from before task started - potential gaming"
        }
    
    # Parse report content
    report_content = result.get("report_content", "")
    bad_frames_gt = gt.get("bad_frames", [])
    
    # Expected frame numbers (e.g., 6, 14, 21)
    expected_numbers = []
    for bf in bad_frames_gt:
        match = re.search(r'\d+', bf)
        if match:
            expected_numbers.append(int(match.group()))
            
    # Extract found frame numbers from report
    found_frames = []
    for line in report_content.split('\n'):
        line = line.strip().lower()
        if not line:
            continue
            
        # Extract all numbers from the line
        nums = re.findall(r'\b\d+\b', line)
        for num_str in nums:
            n = int(num_str)
            # Only consider numbers in the valid frame range (1 to 25)
            if 1 <= n <= 25:
                found_frames.append(n)
                
    found_frames = list(set(found_frames))
    
    # Special case: don't penalize if the user writes "3 bad frames" and 3 is not a target frame
    if 3 in found_frames and 3 not in expected_numbers:
        if re.search(r'3\s*(bad|degraded)?\s*frames?', report_content.lower()):
            found_frames.remove(3)
            
    # Check for True Positives
    tps = 0
    for exp_num in expected_numbers:
        if exp_num in found_frames:
            score += 20
            tps += 1
            feedback.append(f"Identified bad frame: {exp_num}")
            
    # Check for False Positives
    fps = 0
    for fnum in found_frames:
        if fnum not in expected_numbers:
            fps += 1
            
    if fps > 0:
        penalty = min(15, fps * 5)
        score -= penalty
        feedback.append(f"False positives found ({fps}). Penalty: -{penalty}")
    else:
        score += 15
        feedback.append("No false positives")

    # VLM Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images_to_check = frames + [final] if final else frames
            
            if images_to_check:
                prompt = """You are verifying an agent performing Quality Control in AstroImageJ.
The agent should load an image sequence (virtual stack) and inspect the images to find bad frames.
Look at these chronological trajectory frames.
Did the agent open the image sequence window and inspect the images?
Respond in JSON format:
{
    "process_observed": true/false,
    "reasoning": "what you see"
}
"""
                vlm_result = query_vlm(prompt=prompt, images=images_to_check)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("process_observed"):
                        vlm_score = 15
                        feedback.append("VLM confirmed image sequence inspection")
                    else:
                        feedback.append("VLM did not detect image sequence inspection")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            
    score += vlm_score

    score = max(0, min(100, score))
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "expected_frames": expected_numbers,
            "found_frames": found_frames,
            "true_positives": tps,
            "false_positives": fps
        }
    }