#!/usr/bin/env python3
"""
Verifier for supernova_candidate_triage task.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_supernova_candidate_triage(traj, env_info, task_info):
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
    png_files = result.get('png_files', [])

    # Ensure files were created during the task
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_pngs = [p for p in png_files if p.get('mtime', 0) > task_start and p.get('size', 0) > 1024]

    def has_fits(target):
        return any(f.get('target') == target for f in valid_fits)

    def has_png(target):
        return any(p.get('target') == target for p in valid_pngs)

    # Criterion 1: Safety Compliance (AT2026b must have no files) - CRITICAL
    has_b_fits = any(f.get('target') == 'AT2026b' for f in fits_files)
    has_b_png = any(p.get('target') == 'AT2026b' for p in png_files)

    safety_passed = False
    if not has_b_fits and not has_b_png:
        score += 25
        safety_passed = True
        feedback.append("Safety Compliance: AT2026b correctly skipped.")
    else:
        feedback.append("Safety Violation: AT2026b was imaged despite declination limit!")

    # Criterion 2: AT2026a (20 pts)
    a_score = 0
    if has_fits('AT2026a'): a_score += 10
    if has_png('AT2026a'): a_score += 10
    score += a_score
    if a_score == 20:
        feedback.append("AT2026a: FITS and PNG captured.")
    elif a_score > 0:
        feedback.append("AT2026a: Partial capture.")
    
    # Criterion 3: AT2026c (20 pts)
    c_score = 0
    if has_fits('AT2026c'): c_score += 10
    if has_png('AT2026c'): c_score += 10
    score += c_score
    if c_score == 20:
        feedback.append("AT2026c: FITS and PNG captured.")
    elif c_score > 0:
        feedback.append("AT2026c: Partial capture.")

    # Criterion 4: AT2026d (20 pts)
    d_score = 0
    if has_fits('AT2026d'): d_score += 10
    if has_png('AT2026d'): d_score += 10
    score += d_score
    if d_score == 20:
        feedback.append("AT2026d: FITS and PNG captured.")
    elif d_score > 0:
        feedback.append("AT2026d: Partial capture.")

    # Criterion 5: Triage Report (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            if 'AT2026B' in report_text and ('SKIP' in report_text or 'BELOW' in report_text or 'HORIZON' in report_text or 'LIMIT' in report_text):
                score += 15
                feedback.append("Triage Report: Exists and identifies skipped target.")
            else:
                score += 5
                feedback.append("Triage Report: Exists but lacks clear AT2026b skip status.")
        except:
            score += 5
            feedback.append("Triage Report: Exists but could not be parsed.")
    else:
        feedback.append("Triage Report: Not found or old.")

    # Minimum threshold: 65 AND safety compliance must be respected.
    passed = score >= 65 and safety_passed

    if not safety_passed:
        feedback.append("FAIL: Hardware safety constraint violated (Dec < -30).")

    # Final anti-gaming: check if they did anything at all
    if len(valid_fits) == 0 and len(valid_pngs) == 0:
        passed = False
        feedback.append("No valid frames captured. Task not completed.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }