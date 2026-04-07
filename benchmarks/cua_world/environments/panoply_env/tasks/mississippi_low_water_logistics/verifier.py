#!/usr/bin/env python3
"""
Verifier for mississippi_low_water_logistics task.

Scoring criteria (100 pts total, pass threshold = 80):
  1. Difference Plot exported (20 pts): midwest_precip_deficit_may_sep.png exists.
  2. Standard Plot exported (20 pts): midwest_precip_september.png exists.
  3. Logistics report logic - May wetter than Sep (20 pts): correctly identified the data trend.
  4. Operational impact context (15 pts): correctly mentions logistical keywords.
  5. VLM Trajectory Verification (25 pts): Verifies a Panoply combine plot was actually generated.
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames

def verify_mississippi_low_water_logistics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/mississippi_low_water_logistics_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # Criterion 1: Difference plot exported (20 pts)
    diff_exists = result.get('diff_plot_exists', False)
    diff_mtime = int(result.get('diff_plot_mtime', 0))
    diff_size = int(result.get('diff_plot_size', 0))

    if diff_exists and diff_mtime >= task_start and diff_size >= 15000:
        score += 20
        feedback.append(f"Difference plot exported ({diff_size} bytes)")
    elif diff_exists and diff_mtime >= task_start and diff_size >= 5000:
        score += 10
        feedback.append(f"Difference plot present but small ({diff_size} bytes)")
    else:
        feedback.append(f"Difference plot missing or invalid")

    # Criterion 2: Standard plot exported (20 pts)
    std_exists = result.get('std_plot_exists', False)
    std_mtime = int(result.get('std_plot_mtime', 0))
    std_size = int(result.get('std_plot_size', 0))

    if std_exists and std_mtime >= task_start and std_size >= 15000:
        score += 20
        feedback.append(f"Standard plot exported ({std_size} bytes)")
    elif std_exists and std_mtime >= task_start and std_size >= 5000:
        score += 10
        feedback.append(f"Standard plot present but small ({std_size} bytes)")
    else:
        feedback.append(f"Standard plot missing or invalid")

    # Criterion 3: Report parsing - May wetter than Sep (20 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    may_wetter = result.get('may_wetter', '').strip().upper()
    operational_impact = result.get('operational_impact', '').strip().lower()

    may_wetter_correct = False
    if report_exists and report_mtime >= task_start:
        if 'YES' in may_wetter or 'TRUE' in may_wetter or 'Y' == may_wetter:
            score += 20
            may_wetter_correct = True
            feedback.append("Correctly identified May is wetter than September")
        else:
            feedback.append(f"Failed to identify May > Sep (got: '{may_wetter}')")
            
        # Criterion 4: Operational impact keywords (15 pts)
        keywords = ['draft', 'restriction', 'grounding', 'weight', 'load', 'shallow']
        if any(k in operational_impact for k in keywords):
            score += 15
            feedback.append("Identified appropriate operational impacts")
        else:
            feedback.append(f"Operational impact missing key logistics terms (got: '{operational_impact}')")
    else:
        feedback.append("Report missing or not created during task")
        
    # Criterion 5: VLM Verification of Combine Plot workflow (25 pts)
    vlm_score = 0
    query_vlm_func = env_info.get('query_vlm')
    
    if query_vlm_func and (diff_exists or std_exists):
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """
                You are verifying if an agent successfully created a "Combine Plot" in NASA Panoply.
                Look at these frames from their session.
                
                Did the agent:
                1. Open a Combine Plot window (typically shows "Array 1" and "Array 2" options)?
                2. Set it up to calculate a difference (e.g., A - B, Array 1 - Array 2)?
                3. Show a map with a color scale indicating positive/negative difference values?
                
                Respond in JSON format:
                {
                    "combine_plot_visible": true/false,
                    "difference_mode_selected": true/false,
                    "map_rendered": true/false,
                    "confidence": "low/medium/high"
                }
                """
                vlm_result = query_vlm_func(
                    prompt=prompt,
                    images=frames
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("combine_plot_visible"): vlm_score += 10
                    if parsed.get("difference_mode_selected"): vlm_score += 5
                    if parsed.get("map_rendered"): vlm_score += 10
                    
                    score += vlm_score
                    feedback.append(f"VLM verified workflow: +{vlm_score} pts")
                else:
                    feedback.append(f"VLM check failed: {vlm_result.get('error')}")
                    # Give partial credit if we couldn't run VLM but robust outputs exist
                    if diff_exists and diff_size >= 15000:
                        score += 15
                        feedback.append("Assigned partial VLM points based on file presence")
            else:
                if diff_exists and diff_size >= 15000:
                    score += 15
                    feedback.append("No frames for VLM, assigned partial points based on file presence")
        except Exception as e:
            feedback.append(f"VLM error: {e}")
            if diff_exists and diff_size >= 15000:
                score += 15
    else:
        # Fallback if VLM is unavailable
        if diff_exists and diff_size >= 15000:
            score += 25
            feedback.append("VLM unavailable, awarded points based on robust file presence")

    passed = score >= 80 and diff_exists and may_wetter_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }