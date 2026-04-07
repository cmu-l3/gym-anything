#!/usr/bin/env python3
"""
Verifier for ccd_thermal_dark_characterization task.

Criteria (100 pts total, pass >= 65):
1. 0°C Darks Acquired (≥3 FITS in 0C/ with correct temp & exp)        - 25 pts
2. -10°C Darks Acquired (≥3 FITS in minus10C/ with correct temp & exp) - 25 pts
3. -20°C Darks Acquired (≥3 FITS in minus20C/ with correct temp & exp) - 25 pts
4. Directory Structure (all 3 dirs exist and used)                    - 15 pts
5. Calibration Report (exists and mentions temps)                     - 10 pts

Anti-gaming:
- Checks `mtime > task_start` to ignore pre-seeded stale files.
- Inspects actual FITS header `CCD-TEMP` to ensure the agent *waited* for
  stabilization rather than immediately clicking capture.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ccd_thermal_dark_characterization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    req_frames = metadata.get('required_frames_per_temp', 3)
    exp_sec = metadata.get('exposure_sec', 60)
    tol_c = metadata.get('temp_tolerance_celsius', 1.5)

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

    # Filter out decoy/stale files (must be created after task start and not empty)
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]

    def count_valid_darks(target_dir, target_temp):
        count = 0
        issues = []
        for f in valid_fits:
            if f.get('dir') == target_dir:
                # Check frame type
                img_typ = f.get('imagetyp', '').upper()
                is_dark = 'DARK' in img_typ

                # Check exposure time
                exp = f.get('exptime', -1)
                is_right_exp = abs(exp - exp_sec) < 1.0

                # Check temperature
                temp = f.get('ccd_temp', -999)
                is_stable = abs(temp - target_temp) <= tol_c

                if is_dark and is_right_exp and is_stable:
                    count += 1
                else:
                    issue_str = f"{f['name']}: "
                    if not is_dark: issue_str += f"Not DARK (was {img_typ}). "
                    if not is_right_exp: issue_str += f"Wrong Exp ({exp}s). "
                    if not is_stable: issue_str += f"Temp not stable ({temp}°C vs {target_temp}°C). "
                    issues.append(issue_str.strip())
        return count, issues

    # Evaluate 0C Darks
    c_0_count, c_0_issues = count_valid_darks('0C', 0.0)
    if c_0_count >= req_frames:
        score += 25
        feedback.append(f"0°C Setpoint: Success ({c_0_count} valid frames)")
    else:
        feedback.append(f"0°C Setpoint: {c_0_count}/{req_frames} valid frames. Issues: {' | '.join(c_0_issues[:2])}")

    # Evaluate -10C Darks
    c_10_count, c_10_issues = count_valid_darks('minus10C', -10.0)
    if c_10_count >= req_frames:
        score += 25
        feedback.append(f"-10°C Setpoint: Success ({c_10_count} valid frames)")
    else:
        feedback.append(f"-10°C Setpoint: {c_10_count}/{req_frames} valid frames. Issues: {' | '.join(c_10_issues[:2])}")

    # Evaluate -20C Darks
    c_20_count, c_20_issues = count_valid_darks('minus20C', -20.0)
    if c_20_count >= req_frames:
        score += 25
        feedback.append(f"-20°C Setpoint: Success ({c_20_count} valid frames)")
    else:
        feedback.append(f"-20°C Setpoint: {c_20_count}/{req_frames} valid frames. Issues: {' | '.join(c_20_issues[:2])}")

    # Evaluate Directories
    dirs = result.get('dirs', {})
    dirs_exist = sum(1 for v in dirs.values() if v)
    if dirs_exist == 3:
        score += 15
        feedback.append("Directory structure verified")
    else:
        feedback.append(f"Directory structure missing ({dirs_exist}/3 subdirs found)")

    # Evaluate Report
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
            if '0' in report_text and '-10' in report_text and '-20' in report_text:
                score += 10
                feedback.append("Report created and contains target temperatures")
            else:
                score += 5
                feedback.append("Report created but missing some target temperatures")
        except:
            feedback.append("Report created but could not parse contents")
    else:
        feedback.append("No valid report created during task")

    # Final logic
    key_criteria_met = (c_0_count >= req_frames) or (c_10_count >= req_frames) or (c_20_count >= req_frames)
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }