#!/usr/bin/env python3
"""
Verifier for robotic_too_pipeline_scripting task.

Occupation: Telescope Control Software Engineering
Context: Developing an automated bash script for Target of Opportunity (ToO) alerts.

Criteria (100 pts total, pass >= 75):
1. Script existence and executable                                   - 10 pts
2. Polling implementation (contains while/until & indi_getprop)      - 25 pts
3. Park command explicitly found in script                           - 10 pts
4. Valid FITS file created in the expected directory                 - 15 pts
5. FITS headers correctly match parameters (120s, R-band, RA/Dec)    - 20 pts
6. Telescope actively parked at end                                  - 20 pts

Pass threshold: 75 points + Polling implementation + Correct FITS headers
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_coord(c):
    """Safely parse KStars coordinate string ('19 13 03' or '19.2175') to decimal float."""
    try:
        if isinstance(c, (float, int)):
            return float(c)
        c = str(c).strip()
        if not c:
            return None
        parts = c.split()
        if len(parts) == 3:
            return float(parts[0]) + float(parts[1])/60.0 + float(parts[2])/3600.0
        return float(c)
    except:
        return None

def verify_robotic_too_pipeline_scripting(traj, env_info, task_info):
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

    # ── 1. Script Properties (10 pts) ──────────────────────────────────
    script_exists = result.get('script_exists', False)
    script_executable = result.get('script_executable', False)
    script_content_b64 = result.get('script_content_b64', '')
    script_text = ""
    if script_content_b64:
        script_text = base64.b64decode(script_content_b64).decode('utf-8', errors='ignore')

    if script_exists and script_executable:
        score += 10
        feedback.append("Script exists and is executable (+10)")
    elif script_exists:
        score += 5
        feedback.append("Script exists but is NOT executable (+5)")
    else:
        feedback.append("Script not found at /home/ga/too_capture.sh")

    # ── 2. Polling Implementation (25 pts) ─────────────────────────────
    has_loop = 'while' in script_text or 'until' in script_text
    has_getprop = 'indi_getprop' in script_text

    has_polling = False
    if has_loop and has_getprop:
        score += 25
        has_polling = True
        feedback.append("Polling loops detected in script (+25)")
    elif has_getprop:
        score += 10
        feedback.append("indi_getprop used, but no polling loop found (+10)")
    else:
        feedback.append("No polling implementation detected")

    # Check argument usage (informational, but validates automation)
    uses_args = sum(1 for i in range(1, 6) if f"${i}" in script_text)
    if uses_args < 5:
        feedback.append(f"Note: Script only appears to use {uses_args}/5 positional arguments ($1-$5). Hardcoding is bad practice.")

    # ── 3. Park Command in Script (10 pts) ─────────────────────────────
    has_park_cmd = 'TELESCOPE_PARK' in script_text.upper() or 'PARK_TELESCOPE' in script_text.upper()
    if has_park_cmd:
        score += 10
        feedback.append("Park command found in script (+10)")
    else:
        feedback.append("Park command NOT found in script")

    # ── 4. Test Execution: FITS Files (15 pts) ─────────────────────────
    task_start = result.get('task_start', 0)
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    
    if len(valid_fits) > 0:
        score += 15
        feedback.append(f"Found {len(valid_fits)} valid FITS image(s) created during task (+15)")
    else:
        feedback.append("No valid FITS images produced in /home/ga/Images/too_alerts/GRB221009A/")

    # ── 5. Test Execution: Headers (20 pts) ────────────────────────────
    header_ok = False
    if valid_fits:
        f = valid_fits[0]
        exptime = f.get('exptime', -1)
        filt = f.get('filter', '')
        ra = parse_coord(f.get('ra', ''))
        dec = parse_coord(f.get('dec', ''))

        exp_ok = abs(exptime - 120.0) < 1.0
        filt_ok = 'R' in filt or '4' in filt
        ra_ok = ra is not None and abs(ra - 19.2175) < 0.1
        dec_ok = dec is not None and abs(dec - 19.7733) < 0.5

        if exp_ok and filt_ok and ra_ok and dec_ok:
            score += 20
            header_ok = True
            feedback.append("FITS headers correctly match GRB 221009A parameters (+20)")
        else:
            feedback.append(f"FITS header mismatch (Exp={exptime}==120?, Filt='{filt}'==R?, RA={ra}==19.2?, Dec={dec}==19.7?)")
            if exp_ok and filt_ok:
                score += 10
                feedback.append("Partial credit for correct exposure and filter (+10)")
    else:
        feedback.append("No FITS files to check headers")

    # ── 6. Final Telescope State (20 pts) ──────────────────────────────
    park_state = result.get('telescope_park_state', '').strip()
    if park_state == 'On':
        score += 20
        feedback.append("Telescope is actively parked at end of task (+20)")
    else:
        feedback.append(f"Telescope is NOT parked at end of task (State: '{park_state}')")

    # Pass logic: Must have minimum score, implement polling, and execute correctly.
    key_criteria = has_polling and header_ok
    passed = (score >= 75) and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }