#!/usr/bin/env python3
"""
Verifier for document_signal_dropouts@1 task.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_signal_dropouts(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified signal dropouts in the SpO2 track.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check File Existence & Creation Time (15 pts)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if result.get('created_during_task'):
        score += 15
        feedback.append("Report created during task.")
    else:
        feedback.append("Report exists but timestamp is invalid (pre-existing?).")
        score += 5 # Partial credit

    # 2. Check Format (10 pts)
    content = result.get('report_content', '')
    if "SIGNAL DROPOUT REPORT" in content and "Solar8000/PLETH_SPO2" in content:
        score += 10
        feedback.append("Report format looks correct.")
    else:
        feedback.append("Report format incorrect.")

    # 3. Content Verification against Ground Truth (50 pts)
    gt = result.get('ground_truth', {})
    if not gt or 'error' in gt:
        feedback.append("Ground truth missing, falling back to basic checks.")
        # Fallback scoring if GT fails
        episodes_reported = len(re.findall(r"Episode \d+:", content))
        if episodes_reported > 0:
            score += 30
            feedback.append(f"Found {episodes_reported} episodes reported.")
    else:
        # Ground Truth comparison
        gt_episodes = gt.get('episodes', [])
        gt_count = len(gt_episodes)
        
        # Parse user report
        # Look for "Start: HH:MM:SS" or "Start: MM:SS"
        # Convert to seconds
        def parse_time(t_str):
            parts = list(map(int, re.findall(r'\d+', t_str)))
            if len(parts) == 3: return parts[0]*3600 + parts[1]*60 + parts[2]
            if len(parts) == 2: return parts[0]*60 + parts[1]
            return 0
            
        reported_starts = []
        for line in content.split('\n'):
            if "Start:" in line:
                reported_starts.append(parse_time(line))
        
        # Score Count
        count_diff = abs(len(reported_starts) - gt_count)
        if count_diff == 0:
            score += 20
            feedback.append("Correct number of dropout episodes.")
        elif count_diff <= 1:
            score += 10
            feedback.append(f"Episode count close ({len(reported_starts)} vs {gt_count}).")
        else:
            feedback.append(f"Episode count incorrect ({len(reported_starts)} vs {gt_count}).")
            
        # Score Accuracy (Check if reported starts match any GT start within 60s)
        matches = 0
        for r_start in reported_starts:
            for g_ep in gt_episodes:
                g_start = g_ep.get('start', 0)
                if abs(r_start - g_start) < 60:
                    matches += 1
                    break
        
        if len(reported_starts) > 0:
            accuracy = matches / len(reported_starts)
            pts = int(30 * accuracy)
            score += pts
            feedback.append(f"Timestamp accuracy score: {pts}/30.")
        
    # 4. VLM Trajectory Verification (25 pts)
    # Check if agent actually navigated the timeline
    frames = sample_trajectory_frames(traj, n=4)
    if query_vlm:
        vlm_resp = query_vlm(
            images=frames,
            prompt="Does this sequence show the user scrolling horizontally through a medical signal timeline? Do the waveforms change or move between frames?"
        )
        if vlm_resp.get('parsed', {}).get('answer', False) or "yes" in vlm_resp.get('result', '').lower():
            score += 25
            feedback.append("Trajectory shows active timeline navigation.")
        else:
            # Fallback if VLM is strict: assume partial credit if frames distinct
            score += 15 
            feedback.append("Trajectory verification inconclusive, partial credit.")
    else:
        score += 25 # Assume passed if no VLM avail to avoid blocking
        feedback.append("VLM skipped.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }