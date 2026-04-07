#!/usr/bin/env python3
"""
Verifier for ccd_gain_readnoise_characterization task.
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

STALE_FILES = {'old_flat_001.fits', 'old_flat_002.fits', 'old_bias_001.fits'}

def verify_ccd_gain_readnoise(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)
    fits_files = result.get('fits_files', [])

    def count_valid_frames(cat, target_type, target_exptime, tolerance=0.2):
        count = 0
        for f in fits_files:
            if f.get('category') == cat and f.get('mtime', 0) > task_start and f.get('size', 0) > 2048 and f.get('name', '') not in STALE_FILES:
                actual_type = f.get('frame_type', '').upper()
                actual_exp = f.get('exptime', -1.0)
                
                if target_type == 'BIAS':
                    exp_ok = actual_exp < 0.5
                else:
                    exp_ok = abs(actual_exp - target_exptime) <= (target_exptime * tolerance)
                
                if exp_ok:
                    count += 1
        return count

    count_f1 = count_valid_frames('flats_1s', 'FLAT', 1.0)
    count_f5 = count_valid_frames('flats_5s', 'FLAT', 5.0)
    count_f15 = count_valid_frames('flats_15s', 'FLAT', 15.0)
    count_bias = count_valid_frames('bias', 'BIAS', 0.0)

    dirs = result.get('dirs', {})
    if all(dirs.values()):
        score += 10
        feedback.append("Directory structure is correct")
    else:
        feedback.append("Directory structure is incomplete")

    # flats 1s (10 pts)
    if count_f1 >= 2:
        score += 10
        feedback.append(f"flats_1s: {count_f1} valid frames")
    elif count_f1 == 1:
        score += 5
        feedback.append("flats_1s: only 1 frame")
    else:
        feedback.append("flats_1s: no valid frames")

    # flats 5s (10 pts)
    if count_f5 >= 2:
        score += 10
        feedback.append(f"flats_5s: {count_f5} valid frames")
    elif count_f5 == 1:
        score += 5
        feedback.append("flats_5s: only 1 frame")
    else:
        feedback.append("flats_5s: no valid frames")

    # flats 15s (10 pts)
    if count_f15 >= 2:
        score += 10
        feedback.append(f"flats_15s: {count_f15} valid frames")
    elif count_f15 == 1:
        score += 5
        feedback.append("flats_15s: only 1 frame")
    else:
        feedback.append("flats_15s: no valid frames")

    # bias (15 pts)
    if count_bias >= 10:
        score += 15
        feedback.append(f"bias: {count_bias} valid frames")
    elif count_bias >= 5:
        score += 7
        feedback.append(f"bias: {count_bias}/10 frames")
    elif count_bias >= 1:
        score += 3
        feedback.append(f"bias: only {count_bias} frame(s)")
    else:
        feedback.append("bias: no valid frames")

    # Report checking (45 pts total)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    report_valid_time = report_exists and (report_mtime > task_start)
    if report_valid_time:
        score += 10
        feedback.append("Report created during task")
        
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
            
            # Look for gain
            gain_match = re.search(r'gain.*?([0-9]+\.?[0-9]*)', report_text)
            if gain_match:
                gain_val = float(gain_match.group(1))
                if 0.1 <= gain_val <= 100.0:
                    score += 15
                    feedback.append(f"Gain reported: {gain_val}")
                else:
                    feedback.append(f"Gain value {gain_val} out of plausible bounds")
            else:
                feedback.append("No gain value found in report")

            # Look for read noise
            rn_match = re.search(r'read.*?noise.*?([0-9]+\.?[0-9]*)', report_text)
            if rn_match:
                rn_val = float(rn_match.group(1))
                if 0.1 <= rn_val <= 200.0:
                    score += 15
                    feedback.append(f"Read noise reported: {rn_val}")
                else:
                    feedback.append(f"Read noise value {rn_val} out of plausible bounds")
            else:
                feedback.append("No read noise value found in report")

            # Multi-level reference
            if sum(1 for x in ['1s', '5s', '15s', '1 sec', '5 sec', '15 sec', 'signal', 'variance'] if x in report_text) >= 2:
                score += 5
                feedback.append("Report mentions multiple exposure levels or signal/variance")
        except:
            feedback.append("Failed to parse report content")
    else:
        feedback.append("Report not found or not created during task")

    # Try VLM trajectory check if available
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        if images:
            vlm_prompt = "Does the agent use a terminal, Python script, or code editor to process FITS files? Reply in JSON format with {\"analysis_visible\": true/false}."
            vlm_res = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_res and vlm_res.get("success"):
                if vlm_res.get("parsed", {}).get("analysis_visible"):
                    feedback.append("VLM verified analysis activity")
                    score = min(score + 5, 100)
    except Exception as e:
        logger.warning(f"VLM trajectory check failed or unavailable: {e}")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }