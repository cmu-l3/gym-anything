#!/usr/bin/env python3
"""
Verifier for Aperture Growth Curve task.
Scores based on existence of file, parsed measurements, monotonicity,
accuracy against ground truth, and VLM trajectory check.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_aperture_growth_curve(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
        
    # Read Ground Truth
    gt = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/growth_curve_ground_truth.json", temp.name)
        with open(temp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read ground truth: {e}")
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # Read Task Result
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result read error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # Read Start Time for anti-gaming
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/task_start_time", temp.name)
        with open(temp.name, 'r') as f:
            start_time = int(f.read().strip())
    except:
        start_time = 0
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    if not result.get('results_exist'):
        return {"passed": False, "score": 0, "feedback": "Results file not found"}

    mtime = result.get('mtime', 0)
    if mtime > 0 and start_time > 0 and mtime < start_time:
        return {"passed": False, "score": 0, "feedback": "Results file modified before task start (anti-gaming)"}

    score += 10
    feedback.append("Results file exists")

    measurements = result.get('measurements', {})
    num_meas = len(measurements)
    if num_meas == 0:
        return {"passed": False, "score": score, "feedback": "No valid measurements parsed"}

    if num_meas >= 5:
        score += 15
        feedback.append(f"Parsed {num_meas} measurements (>=5)")
    else:
        score += 5
        feedback.append(f"Parsed {num_meas} measurements (<5)")

    # Sort radii to check monotonicity and shape
    sorted_radii = sorted([float(r) for r in measurements.keys()])
    fluxes = []
    for r in sorted_radii:
        r_str = str(r)
        if r_str in measurements:
            fluxes.append(measurements[r_str])
        else:
            # Fallback for integer formats
            r_str = str(int(r)) if r.is_integer() else str(r)
            fluxes.append(measurements.get(r_str, measurements[min(measurements.keys(), key=lambda k: abs(float(k) - r))]))
            
    # Check Monotonicity
    if len(fluxes) >= 3:
        # Allow slight dips due to noise/sky estimation
        is_monotonic = all(fluxes[i] <= fluxes[i+1] * 1.05 for i in range(len(fluxes)-1))
        if is_monotonic:
            score += 15
            feedback.append("Fluxes show monotonic increase")
        else:
            feedback.append("Fluxes are not monotonic")

    # Compare with ground truth
    gt_fluxes = gt.get('fluxes', {})
    if gt_fluxes:
        # Check small aperture accuracy
        small_r = [r for r in sorted_radii if r <= 8]
        if small_r:
            r_val = small_r[-1]
            gt_key = min(gt_fluxes.keys(), key=lambda k: abs(float(k) - r_val))
            gt_f = gt_fluxes[gt_key]
            
            # Find closest agent measurement
            agent_key = min(measurements.keys(), key=lambda k: abs(float(k) - r_val))
            agent_f = measurements[agent_key]
            
            if gt_f > 0 and abs(agent_f - gt_f) / gt_f < 0.4:
                score += 15
                feedback.append(f"Small aperture flux accurate (r={r_val})")
            else:
                feedback.append(f"Small aperture flux inaccurate (got {agent_f}, expected ~{gt_f})")
                
        # Check large aperture accuracy
        large_r = [r for r in sorted_radii if r >= 20]
        if large_r:
            r_val = large_r[0]
            gt_key = min(gt_fluxes.keys(), key=lambda k: abs(float(k) - r_val))
            gt_f = gt_fluxes[gt_key]
            
            agent_key = min(measurements.keys(), key=lambda k: abs(float(k) - r_val))
            agent_f = measurements[agent_key]
            
            if gt_f > 0 and abs(agent_f - gt_f) / gt_f < 0.3:
                score += 15
                feedback.append(f"Large aperture flux accurate (r={r_val})")
            else:
                feedback.append(f"Large aperture flux inaccurate (got {agent_f}, expected ~{gt_f})")
                
        # Shape / Curve check
        if small_r and large_r:
            small_f = fluxes[sorted_radii.index(small_r[-1])]
            large_f = fluxes[sorted_radii.index(large_r[0])]
            if large_f > 0:
                ratio = small_f / large_f
                # Typically, a 5px aperture holds ~30-60% of the flux compared to a 25px aperture depending on seeing
                if 0.1 < ratio < 0.95:
                    score += 10
                    feedback.append(f"Growth curve shape realistic (ratio={ratio:.2f})")
                else:
                    feedback.append(f"Growth curve shape suspect (ratio={ratio:.2f})")

    # Optimal Aperture
    opt_ap = result.get('optimal_aperture')
    if opt_ap is not None:
        if 8 <= opt_ap <= 25:
            score += 10
            feedback.append(f"Optimal aperture specified: {opt_ap}")
        else:
            feedback.append(f"Optimal aperture {opt_ap} outside typical range (8-25)")
    else:
        feedback.append("Optimal aperture not specified")

    # VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = "Look at these AstroImageJ screenshots. Do you see a grayscale star field image loaded, AND evidence of aperture circles placed on a star? Answer with just 'yes' or 'no'."
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                if 'yes' in vlm_res.get('response', '').lower():
                    score += 10
                    feedback.append("VLM confirmed visual photometry interaction")
                else:
                    feedback.append("VLM did not detect photometry interaction")

    passed = score >= 60 and num_meas >= 3

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }