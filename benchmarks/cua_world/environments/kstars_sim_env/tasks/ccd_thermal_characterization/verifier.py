#!/usr/bin/env python3
"""
Verifier for ccd_thermal_characterization task.

Criteria (100 pts total, pass >= 70):
1. 0°C Dark Frames: >= 5 valid frames in 0C/          (25 pts)
2. -10°C Dark Frames: >= 5 valid frames in minus10C/  (25 pts)
3. -20°C Dark Frames: >= 5 valid frames in minus20C/  (25 pts)
4. Directory Structure: all 3 subdirectories exist    (10 pts)
5. Summary Report: exists and created during task     (15 pts)

A frame is valid if:
- created after task start
- size > 2048
- IMAGETYP or FRAME contains 'Dark'
- EXPTIME == 60
- CCD-TEMP within 1.0 of target
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ccd_thermal_characterization(traj, env_info, task_info):
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

    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_valid_frames(target_dir, target_temp):
        count = 0
        for f in valid_fits:
            fdir = f.get('dir', '')
            ftype = f.get('frame_type', '').upper()
            exptime = f.get('exptime', -1)
            ccd_temp = f.get('ccd_temp', -999.0)
            
            if fdir == target_dir and 'DARK' in ftype and abs(exptime - 60) < 1.0 and abs(ccd_temp - target_temp) <= 1.0:
                count += 1
        return count

    count_0c = count_valid_frames('0C', 0.0)
    count_m10c = count_valid_frames('minus10C', -10.0)
    count_m20c = count_valid_frames('minus20C', -20.0)

    # 1. 0C Frames
    if count_0c >= 5:
        score += 25
        feedback.append(f"0°C: {count_0c} valid dark frames")
    elif count_0c >= 2:
        score += 10
        feedback.append(f"0°C: {count_0c}/5 valid dark frames")
    elif count_0c >= 1:
        score += 5
        feedback.append(f"0°C: {count_0c} valid dark frame")
    else:
        feedback.append("0°C: no valid dark frames found")

    # 2. -10C Frames
    if count_m10c >= 5:
        score += 25
        feedback.append(f"-10°C: {count_m10c} valid dark frames")
    elif count_m10c >= 2:
        score += 10
        feedback.append(f"-10°C: {count_m10c}/5 valid dark frames")
    elif count_m10c >= 1:
        score += 5
        feedback.append(f"-10°C: {count_m10c} valid dark frame")
    else:
        feedback.append("-10°C: no valid dark frames found")

    # 3. -20C Frames
    if count_m20c >= 5:
        score += 25
        feedback.append(f"-20°C: {count_m20c} valid dark frames")
    elif count_m20c >= 2:
        score += 10
        feedback.append(f"-20°C: {count_m20c}/5 valid dark frames")
    elif count_m20c >= 1:
        score += 5
        feedback.append(f"-20°C: {count_m20c} valid dark frame")
    else:
        feedback.append("-20°C: no valid dark frames found")

    # 4. Directory Structure
    dirs = result.get('dirs', {})
    if dirs.get('0C') and dirs.get('minus10C') and dirs.get('minus20C'):
        score += 10
        feedback.append("Directory structure complete")
    else:
        feedback.append("Missing required directories")

    # 5. Report
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    if report_exists and report_mtime > task_start:
        score += 15
        feedback.append("Summary report created")
    elif report_exists:
        feedback.append("Summary report exists but pre-dates task start")
    else:
        feedback.append("Summary report not found")

    # Pass logic: at least 70 pts and at least 2 temperatures complete
    temps_complete = sum([count_0c >= 5, count_m10c >= 5, count_m20c >= 5])
    passed = score >= 70 and temps_complete >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }