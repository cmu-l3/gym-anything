#!/usr/bin/env python3
"""
Verifier for Corner Illumination Uniformity Assessment task.

Scoring (100 points total):
  - FITS opened & file created properly (10 pts)
  - 4 Corner Medians within 15% tolerance (12 pts each -> 48 pts)
  - StdDevs within 30% tolerance (10 pts total for >= 3 correct)
  - Max fractional difference within 3 percentage points (12 pts)
  - Qualitative Assessment exactly matches (5 pts)
  - VLM Trajectory (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import re
import logging

from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)


def _query_vlm_trajectory(traj, query_vlm):
    """Uses VLM to verify if the agent actually used the rectangular ROI and measurements."""
    if not query_vlm:
        return 0, "VLM function not available"
        
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return 0, "No trajectory frames available"
        
    prompt = """You are analyzing screenshots of an agent using AstroImageJ to measure corner uniformities in a FITS image.
    
    Review the frames and assess:
    1. image_opened: Is a grayscale astronomical image loaded in AstroImageJ?
    2. roi_used: Is a yellow rectangular ROI (Region of Interest) box visible on the image at any point?
    3. measurements_taken: Is the "Results" or "Measurements" table window visible with statistical rows?
    
    Respond in JSON format:
    {
        "image_opened": true/false,
        "roi_used": true/false,
        "measurements_taken": true/false,
        "observations": "brief reasoning"
    }"""
    
    try:
        res = query_vlm(prompt=prompt, images=frames)
        if res.get("success"):
            parsed = res.get("parsed", {})
            vlm_score = 0
            if parsed.get("image_opened"): vlm_score += 5
            if parsed.get("roi_used"): vlm_score += 5
            if parsed.get("measurements_taken"): vlm_score += 5
            return vlm_score, "VLM confirmed workflow"
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        
    return 0, "VLM verification failed or incomplete"


def verify_uniformity_check(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Load results and ground truth
    result = {}
    gt = {}
    
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
            
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/uniformity_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Data load error: {e}"}
    finally:
        if os.path.exists(temp_res.name): os.unlink(temp_res.name)
        if 'temp_gt' in locals() and os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    score = 0
    feedback = []

    # 2. Basic file checks
    if result.get("report_exists"):
        if result.get("created_during_task"):
            score += 10
            feedback.append("Report file created during task (10/10)")
        else:
            feedback.append("Report file exists but appears modified BEFORE task started. Possible gaming.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    else:
        feedback.append("Report file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 3. Parse Report
    raw_content = result.get("report_content_raw", "").replace("|", "\n")
    
    medians = {}
    stddevs = {}
    corners = ['TL', 'TR', 'BL', 'BR']
    
    for c in corners:
        m = re.search(rf'Corner {c}:\s*median=([\d.]+)\s+stddev=([\d.]+)', raw_content, re.IGNORECASE)
        if m:
            medians[c] = float(m.group(1))
            stddevs[c] = float(m.group(2))
            
    m_diff = re.search(r'Max fractional difference:\s*([\d.]+)%?', raw_content, re.IGNORECASE)
    reported_diff = float(m_diff.group(1)) if m_diff else None
    
    m_ass = re.search(r'Assessment:\s*(UNIFORM|MARGINAL|NON-UNIFORM)', raw_content, re.IGNORECASE)
    reported_ass = m_ass.group(1).upper() if m_ass else None

    # 4. Compare Medians (12 pts each)
    for c in corners:
        rep_med = medians.get(c)
        exp_med = gt.get(c, {}).get("median")
        if rep_med is not None and exp_med is not None:
            tol = abs(exp_med) * 0.15
            if abs(rep_med - exp_med) <= tol:
                score += 12
                feedback.append(f"{c} Median correct ({rep_med} vs {exp_med:.1f})")
            else:
                feedback.append(f"{c} Median incorrect ({rep_med} vs expected {exp_med:.1f})")
        else:
            feedback.append(f"{c} Median missing or invalid format")

    # 5. Compare StdDevs (10 pts if >= 3 are close)
    stddev_correct = 0
    for c in corners:
        rep_std = stddevs.get(c)
        exp_std = gt.get(c, {}).get("stddev")
        if rep_std is not None and exp_std is not None:
            tol = abs(exp_std) * 0.30  # StdDev can vary slightly by exact pixel inclusion
            if abs(rep_std - exp_std) <= tol:
                stddev_correct += 1
    
    if stddev_correct >= 3:
        score += 10
        feedback.append(f"StdDevs highly accurate ({stddev_correct}/4) (+10)")
    else:
        feedback.append(f"StdDevs largely incorrect ({stddev_correct}/4 accurate)")

    # 6. Compare Fractional Difference (12 pts)
    exp_diff = gt.get("max_diff_pct")
    if reported_diff is not None and exp_diff is not None:
        if abs(reported_diff - exp_diff) <= 3.0:
            score += 12
            feedback.append(f"Fractional difference correct ({reported_diff}% vs {exp_diff:.1f}%)")
        else:
            feedback.append(f"Fractional difference off ({reported_diff}% vs expected {exp_diff:.1f}%)")
    else:
        feedback.append("Fractional difference missing or invalid")

    # 7. Compare Assessment (5 pts)
    exp_ass = gt.get("assessment")
    if reported_ass == exp_ass:
        score += 5
        feedback.append(f"Assessment correct ({reported_ass})")
    else:
        feedback.append(f"Assessment incorrect (Got {reported_ass}, Expected {exp_ass})")

    # 8. VLM Trajectory (15 pts)
    vlm_score, vlm_fb = _query_vlm_trajectory(traj, query_vlm)
    score += vlm_score
    feedback.append(f"VLM: {vlm_fb} (+{vlm_score})")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }