#!/usr/bin/env python3
"""
Verifier for tarc_altitude_time_calibration task.

Scoring breakdown (100 points total):
  15 pts - Motor mount increased to 24mm and Estes E12 motor assigned
  10 pts - External airframe constraint respected (body tube length unmodified)
  30 pts - Altitude calibration: maxaltitude between 239m and 249m
  30 pts - Flight time calibration: flighttime between 43.0s and 47.0s
  15 pts - Calibration report exists with accurate simulation data

Pass threshold: 75 points
"""

import os
import re
import tempfile
import zipfile
import json
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def verify_tarc_altitude_time_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/tarc_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/tarc_report.txt')
    target_alt = float(metadata.get('target_alt_m', 244.0))
    target_time = float(metadata.get('target_time_s', 45.0))
    alt_tol = float(metadata.get('alt_tolerance_m', 5.0))
    time_tol = float(metadata.get('time_tolerance_s', 2.0))

    score = 0
    feedback_parts = []

    # 1. Read result JSON
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/tarc_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res = json.load(f)
    except Exception:
        res = {}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not res.get('ork_exists'):
        return {"passed": False, "score": 0, "feedback": "Target ORK file (tarc_rocket.ork) not found."}

    if not res.get('created_during_task', True):
        feedback_parts.append("WARNING: File appears older than task start time.")

    # 2. Extract and Parse ORK
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
    except Exception as e:
        parse_err = str(e)
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if not ork_root:
        return {"passed": False, "score": 0, "feedback": f"Could not parse ORK file: {parse_err}"}

    # 3. Check Motor & Motor Mount (15 pts)
    has_e12 = False
    for motor in ork_root.iter('motor'):
        if 'E12' in motor.findtext('designation', '').upper():
            has_e12 = True

    motor_mount_resized = False
    for elem in list(ork_root.iter('innertube')) + list(ork_root.iter('bodytube')):
        if elem.find('motormount') is not None:
            ir = float(elem.findtext('innerradius', '0'))
            if ir >= 0.0115:  # ~23mm diameter minimum
                motor_mount_resized = True

    if has_e12 and motor_mount_resized:
        score += 15
        feedback_parts.append("E12 motor assigned and mount resized [15/15 pts]")
    elif has_e12:
        score += 10
        feedback_parts.append("E12 motor assigned but mount not explicitly resized [10/15 pts]")
    else:
        feedback_parts.append("E12 motor not found [0/15 pts]")

    # 4. Airframe constraints (10 pts)
    # The base model has 1 body tube, length 0.28m. We ensure they didn't cheat by shrinking it drastically.
    bt_count = len(list(ork_root.iter('bodytube')))
    bt_ok = False
    for bt in ork_root.iter('bodytube'):
        length = float(bt.findtext('length', '0'))
        if length > 0.20:
            bt_ok = True

    if bt_count >= 1 and bt_ok:
        score += 10
        feedback_parts.append("Airframe dimensions maintained [10/10 pts]")
    else:
        feedback_parts.append("Airframe constraint violated (body tube significantly altered) [0/10 pts]")

    # 5. Simulations: Altitude (30 pts) and Time (30 pts)
    sims = ork_root.find('simulations')
    best_alt = 0.0
    best_time = 0.0
    uptodate = False

    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate = True
                fd = sim.find('flightdata')
                if fd is not None:
                    alt = float(fd.get('maxaltitude', '0'))
                    ftime = float(fd.get('flighttime', '0'))
                    # Pick the sim closest to target altitude
                    if abs(alt - target_alt) < abs(best_alt - target_alt) or best_alt == 0:
                        best_alt = alt
                        best_time = ftime

    if not uptodate:
        feedback_parts.append("No up-to-date simulation found [0/60 pts]")
    else:
        alt_diff = abs(best_alt - target_alt)
        if alt_diff <= alt_tol:
            score += 30
            feedback_parts.append(f"Altitude {best_alt:.1f}m within {alt_tol}m target [30/30 pts]")
        elif alt_diff <= alt_tol * 3:
            score += 15
            feedback_parts.append(f"Altitude {best_alt:.1f}m close but out of tolerance [15/30 pts]")
        else:
            feedback_parts.append(f"Altitude {best_alt:.1f}m off target by >{alt_tol*3}m [0/30 pts]")

        time_diff = abs(best_time - target_time)
        if time_diff <= time_tol:
            score += 30
            feedback_parts.append(f"Flight time {best_time:.1f}s within {time_tol}s target [30/30 pts]")
        elif time_diff <= time_tol * 3:
            score += 15
            feedback_parts.append(f"Flight time {best_time:.1f}s close but out of tolerance [15/30 pts]")
        else:
            feedback_parts.append(f"Flight time {best_time:.1f}s off target by >{time_tol*3}s [0/30 pts]")

    # 6. Report verification (15 pts)
    if res.get('report_exists'):
        tmp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_rep.close()
        rep_text = ""
        try:
            copy_from_env(report_vm_path, tmp_rep.name)
            with open(tmp_rep.name, 'r') as f:
                rep_text = f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_rep.name):
                os.unlink(tmp_rep.name)

        if len(rep_text) > 10:
            # Extract numbers and see if they match the best sim values
            nums = re.findall(r'\b\d+\.?\d*\b', rep_text)
            floats = [float(n) for n in nums]
            alt_found = any(abs(f - best_alt) < 2.0 for f in floats) if best_alt > 0 else False
            time_found = any(abs(f - best_time) < 1.0 for f in floats) if best_time > 0 else False

            if alt_found or time_found:
                score += 15
                feedback_parts.append("Report contains accurate calibration data [15/15 pts]")
            else:
                score += 5
                feedback_parts.append("Report exists but data mismatched with .ork sim [5/15 pts]")
        else:
            feedback_parts.append("Report is empty or too short [0/15 pts]")
    else:
        feedback_parts.append("Calibration report not found [0/15 pts]")

    passed = score >= metadata.get('pass_threshold', 75)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }