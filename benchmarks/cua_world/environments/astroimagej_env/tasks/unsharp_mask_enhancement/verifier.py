#!/usr/bin/env python3
"""
Verifier for Unsharp Mask Enhancement task.
"""

import os
import json
import math
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing trajectory screenshots of an agent using AstroImageJ to apply an Unsharp Mask.

Assess the following criteria chronologically:
1. Did the agent open an astronomical FITS image showing a nebula structure?
2. Did the agent open the 'Unsharp Mask' dialog (usually via Process > Filters > Unsharp Mask)?
3. Did the agent save a FITS file and/or write to a text editor to record measurements?

Respond strictly in JSON:
{
    "opened_image": true/false,
    "opened_unsharp_mask_dialog": true/false,
    "saved_results": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""

def verify_unsharp_mask(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []
    
    # 1. Retrieve the programmatic result
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task_result.json: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    gt = result.get('gt', {})
    agent_fits_stats = result.get('agent_fits_stats', {})
    parsed_txt = result.get('parsed_txt_stats', {})

    # 2. Score FITS File Creation & Correctness (50 pts total)
    if result.get('agent_fits_exists'):
        if not result.get('agent_fits_newer_than_start'):
            feedback.append("FITS file exists but was NOT modified during the task (Gaming detected).")
        elif agent_fits_stats.get('is_identical_to_orig'):
            feedback.append("FITS file saved but is identical to original (No filter applied).")
        else:
            score += 10
            feedback.append("Enhanced FITS file created and modified.")
            
            # Dimension check
            if agent_fits_stats.get('shape') == gt.get('shape'):
                score += 5
            
            # StdDev check (Tolerance: 15%)
            if 'std' in gt and 'std' in agent_fits_stats:
                gt_std = gt['std']
                ag_std = agent_fits_stats['std']
                if abs(gt_std - ag_std) / gt_std <= 0.15:
                    score += 15
                    feedback.append(f"Image standard deviation within tolerance ({ag_std:.1f} vs {gt_std:.1f}).")
                else:
                    feedback.append(f"Image stddev outside tolerance ({ag_std:.1f} vs {gt_std:.1f}).")
                    
            # Mean check (Tolerance: 10%)
            if 'mean' in gt and 'mean' in agent_fits_stats:
                gt_mean = gt['mean']
                ag_mean = agent_fits_stats['mean']
                if abs(gt_mean - ag_mean) / gt_mean <= 0.10:
                    score += 5
                    feedback.append("Image mean within tolerance.")

            # Peak location check (Tolerance: 20 pixels distance)
            if 'peak_x' in gt and 'peak_x' in agent_fits_stats:
                dist = math.hypot(gt['peak_x'] - agent_fits_stats['peak_x'],
                                  gt['peak_y'] - agent_fits_stats['peak_y'])
                if dist <= 20:
                    score += 15
                    feedback.append(f"Peak location accurate (dist: {dist:.1f}px).")
                else:
                    feedback.append(f"Peak location inaccurate (dist: {dist:.1f}px).")
    else:
        feedback.append("No enhanced FITS file found.")

    # 3. Score Results Text File (25 pts total)
    if result.get('agent_txt_exists'):
        score += 5
        feedback.append("Results text file found.")
        
        # Check required fields (need 3 out of 4 to get points)
        fields_found = sum(1 for v in parsed_txt.values() if v is not None)
        if fields_found >= 3:
            score += 10
            feedback.append(f"Text file contains {fields_found} parsed numeric values.")
        else:
            feedback.append("Text file missing clear numeric measurements.")
            
        # Check ratio correctness (Tolerance: 20%)
        ratio = parsed_txt.get('ratio')
        if not ratio and parsed_txt.get('enh_std') and parsed_txt.get('orig_std'):
            try:
                ratio = parsed_txt['enh_std'] / parsed_txt['orig_std']
            except ZeroDivisionError:
                ratio = None
                
        if ratio and 'expected_ratio' in gt:
            if abs(ratio - gt['expected_ratio']) / gt['expected_ratio'] <= 0.20:
                score += 10
                feedback.append(f"Contrast ratio calculated correctly (~{ratio:.2f}).")
    else:
        feedback.append("No results text file found.")

    # 4. VLM Trajectory Verification (25 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final: frames.append(final)
        
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('opened_image'): vlm_score += 5
            if parsed.get('opened_unsharp_mask_dialog'): vlm_score += 10
            if parsed.get('saved_results'): vlm_score += 10
            
            feedback.append(f"VLM verified workflow: +{vlm_score} pts.")
        else:
            feedback.append("VLM query failed or returned no result.")
    else:
        feedback.append("VLM query function not available.")
        
    score += vlm_score

    # 5. Finalize
    passed = score >= 60 and result.get('agent_fits_exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }