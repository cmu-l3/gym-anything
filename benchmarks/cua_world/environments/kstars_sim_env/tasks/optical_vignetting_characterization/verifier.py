#!/usr/bin/env python3
"""
Verifier for optical_vignetting_characterization task.

Criteria (100 pts total, pass >= 70):
1. Bias Acquisition (15 pts): >=5 frames in Bias/ with IMAGETYP=Bias or EXPTIME=0
2. Flat Acquisition (15 pts): >=5 frames in Flats/ with IMAGETYP=Flat or FILTER=Luminance
3. Script Exists (10 pts): analyze_sensor.py exists and ran
4. Math: Vignetting Ratio (30 pts): Script outputs EXACT mathematically correct ratio on hidden test FITS.
5. Math: RMS Noise (20 pts): Script outputs EXACT mathematically correct noise on hidden test FITS.
6. Report Generation (10 pts): sensor_report.txt exists and contains text.

Anti-gaming: The verification executes the agent's code against a dynamically generated 
FITS file with known mathematical parameters. Harcoding numbers will fail.
"""

import json
import os
import re
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vignetting_characterization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_bias = metadata.get('expected_bias_count', 5)
    expected_flat = metadata.get('expected_flat_count', 5)

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

    # ── 1 & 2. Hardware: FITS Acquisition ────────────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    bias_count = 0
    flat_count = 0
    for f in valid_fits:
        path_upper = f.get('path', '').upper()
        frame_type = f.get('frame_type', '').upper()
        filt = f.get('filter', '').upper()
        exptime = f.get('exptime', -1)

        # Identify Bias (Dir contains BIAS, or EXPTIME=0, or IMAGETYP=Bias)
        if 'BIAS' in path_upper or frame_type == 'BIAS' or exptime == 0.0:
            bias_count += 1
        # Identify Flat (Dir contains FLAT, or FILTER=Luminance, or IMAGETYP=Flat)
        elif 'FLAT' in path_upper or frame_type == 'FLAT' or 'LUM' in filt:
            flat_count += 1

    if bias_count >= expected_bias:
        score += 15
        feedback.append(f"Bias Frames: {bias_count} captured.")
    elif bias_count > 0:
        score += 7
        feedback.append(f"Bias Frames: {bias_count}/{expected_bias} captured.")
    else:
        feedback.append("Bias Frames: None found.")

    if flat_count >= expected_flat:
        score += 15
        feedback.append(f"Flat Frames: {flat_count} captured.")
    elif flat_count > 0:
        score += 7
        feedback.append(f"Flat Frames: {flat_count}/{expected_flat} captured.")
    else:
        feedback.append("Flat Frames: None found.")

    # ── 3. Script Exists ──────────────────────────────────────────────────────
    if result.get('script_exists') and result.get('script_ran'):
        score += 10
        feedback.append("Script: analyze_sensor.py exists and executed.")
    else:
        feedback.append("Script: Missing or failed to execute.")

    # ── 4 & 5. Software: Math Output Evaluation ───────────────────────────────
    true_vignetting = result.get('true_vignetting', -1)
    true_rms = result.get('true_rms', -1)
    agent_stdout = result.get('agent_stdout', '')

    vig_match = re.search(r'Vignetting Ratio:\s*([\d.]+)', agent_stdout, re.IGNORECASE)
    rms_match = re.search(r'RMS Noise:\s*([\d.]+)', agent_stdout, re.IGNORECASE)

    agent_vig = float(vig_match.group(1)) if vig_match else None
    agent_rms = float(rms_match.group(1)) if rms_match else None

    # Score Vignetting (Math must be exact, relative tolerance 1%)
    if agent_vig is not None and math.isclose(agent_vig, true_vignetting, rel_tol=0.01):
        score += 30
        feedback.append("Math (Vignetting): Correct!")
    elif agent_vig is not None:
        feedback.append(f"Math (Vignetting): Incorrect (Got {agent_vig:.4f}, expected ~{true_vignetting:.4f})")
    else:
        feedback.append("Math (Vignetting): Could not parse output format.")

    # Score RMS Noise (Tolerance 1%)
    if agent_rms is not None and math.isclose(agent_rms, true_rms, rel_tol=0.01):
        score += 20
        feedback.append("Math (RMS Noise): Correct!")
    elif agent_rms is not None:
        feedback.append(f"Math (RMS Noise): Incorrect (Got {agent_rms:.2f}, expected ~{true_rms:.2f})")
    else:
        feedback.append("Math (RMS Noise): Could not parse output format.")

    # ── 6. Report Generation ──────────────────────────────────────────────────
    if result.get('report_exists') and result.get('report_size', 0) > 10:
        score += 10
        feedback.append("Report: sensor_report.txt generated.")
    else:
        feedback.append("Report: Missing or empty.")

    # ── Final Determination ───────────────────────────────────────────────────
    # The math for vignetting MUST be correct to pass the task context.
    math_passed = (agent_vig is not None and math.isclose(agent_vig, true_vignetting, rel_tol=0.01))
    passed = (score >= 70) and math_passed

    if passed:
        feedback.insert(0, "SUCCESS: Sensor characterized mathematically correctly.")
    else:
        feedback.insert(0, "FAILED: Core requirements or math validation not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }