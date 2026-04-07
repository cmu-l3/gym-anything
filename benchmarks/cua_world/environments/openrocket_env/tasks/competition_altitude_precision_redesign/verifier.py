#!/usr/bin/env python3
"""
Verifier for competition_altitude_precision_redesign task.

This is a stub verifier. The primary evaluation will be done via vlm_checklist_verifier.
The programmatic checks below provide basic structural validation.

Scoring Breakdown (100 points total):
   8 pts - Fins restored to reasonable size (height >= 50mm)
   8 pts - Main parachute resized (diameter >= 400mm)
   5 pts - Drogue parachute resized (diameter >= 150mm)
  10 pts - Motor installed (at least one motor configuration present)
  12 pts - At least one up-to-date simulation
  20 pts - Apogee in target range (400-500m)
  15 pts - Max acceleration <= 100 m/s^2
  10 pts - Ground hit velocity <= 6 m/s
   4 pts - Design file saved (competition_final.ork exists, different from start)
   4 pts - CSV export exists with meaningful size
   4 pts - Design report exists with relevant keywords

Pass threshold: 65 points
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


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
            return None, f"Could not parse as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def verify_competition_altitude_precision_redesign(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork = metadata.get('target_ork_vm_path',
                              '/home/ga/Documents/rockets/competition_final.ork')
    csv_path = metadata.get('csv_vm_path',
                            '/home/ga/Documents/exports/flight_data.csv')
    report_path = metadata.get('report_vm_path',
                               '/home/ga/Documents/exports/design_report.txt')
    apogee_min = metadata.get('target_apogee_min_m', 400.0)
    apogee_max = metadata.get('target_apogee_max_m', 500.0)
    max_accel = metadata.get('max_acceleration_ms2', 100.0)
    max_ghv = metadata.get('max_ground_hit_velocity_ms', 6.0)

    score = 0
    feedback = []

    # ---- Load exported result JSON ----
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    res_data = {}
    try:
        copy_from_env('/tmp/competition_redesign_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    # ---- Anti-gaming: check file was created during task ----
    task_start_ts = res_data.get('task_start_ts', 0)
    ork_mtime = res_data.get('ork_mtime', 0)
    start_md5 = res_data.get('start_ork_md5', '')
    ork_md5 = res_data.get('ork_md5', '')

    if not res_data.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Target file {target_ork} not found."
        }

    if ork_mtime > 0 and task_start_ts > 0 and ork_mtime < task_start_ts:
        feedback.append("WARNING: .ork file predates task start")

    if start_md5 and ork_md5 and start_md5 == ork_md5:
        feedback.append("WARNING: Output .ork is identical to starting file")

    # ---- Fetch and parse .ork ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(target_ork, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback.append(f"ORK parse error: {parse_err}")
    except Exception as e:
        feedback.append(f"Could not retrieve .ork: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback) or "Failed to parse rocket file"
        }

    # ================================================================
    # Check 1: Fins restored (8 pts)
    # ================================================================
    min_fin_height = 999.0
    fin_count = 0
    for tag in ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']:
        for finset in ork_root.iter(tag):
            h = finset.findtext('height', '0')
            try:
                h_val = float(h)
                min_fin_height = min(min_fin_height, h_val)
                fin_count += 1
            except ValueError:
                pass

    if fin_count > 0 and min_fin_height >= 0.050:
        score += 8
        feedback.append(f"Fins restored: min height {min_fin_height*1000:.0f}mm [8/8]")
    elif fin_count > 0 and min_fin_height > 0.015:
        score += 3
        feedback.append(
            f"Fins partially restored: {min_fin_height*1000:.0f}mm (need >=50mm) [3/8]")
    else:
        feedback.append("Fins still undersized or not found [0/8]")

    # ================================================================
    # Check 2: Main parachute resized (8 pts)
    # ================================================================
    max_para_diam = 0.0
    for para in ork_root.iter('parachute'):
        name = (para.findtext('name', '') or '').lower()
        if 'drogue' in name or 'drouge' in name:
            continue
        d = para.findtext('diameter', '0')
        try:
            max_para_diam = max(max_para_diam, float(d))
        except ValueError:
            pass

    if max_para_diam >= 0.400:
        score += 8
        feedback.append(
            f"Main parachute sized: {max_para_diam*1000:.0f}mm [8/8]")
    elif max_para_diam > 0.150:
        score += 3
        feedback.append(
            f"Main parachute improved: {max_para_diam*1000:.0f}mm (need >=400mm) [3/8]")
    else:
        feedback.append("Main parachute still undersized [0/8]")

    # ================================================================
    # Check 3: Drogue parachute resized (5 pts)
    # ================================================================
    max_drogue_diam = 0.0
    for para in ork_root.iter('parachute'):
        name = (para.findtext('name', '') or '').lower()
        if 'drogue' in name or 'drouge' in name:
            d = para.findtext('diameter', '0')
            try:
                max_drogue_diam = max(max_drogue_diam, float(d))
            except ValueError:
                pass

    if max_drogue_diam >= 0.150:
        score += 5
        feedback.append(
            f"Drogue parachute sized: {max_drogue_diam*1000:.0f}mm [5/5]")
    elif max_drogue_diam > 0.050:
        score += 2
        feedback.append(
            f"Drogue improved: {max_drogue_diam*1000:.0f}mm (need >=150mm) [2/5]")
    else:
        feedback.append("Drogue parachute still undersized [0/5]")

    # ================================================================
    # Check 4: Motor installed (10 pts)
    # ================================================================
    has_motor = False
    motor_desig = ""
    for mm in ork_root.iter('motormount'):
        for motor in mm.findall('motor'):
            desig = motor.findtext('designation', '').strip()
            if desig:
                has_motor = True
                motor_desig = desig
                break
        if has_motor:
            break

    if has_motor:
        score += 10
        feedback.append(f"Motor installed: {motor_desig} [10/10]")
    else:
        feedback.append("No motor installed [0/10]")

    # ================================================================
    # Check 5: Up-to-date simulation (12 pts)
    # ================================================================
    sims = ork_root.find('simulations')
    uptodate_count = 0
    best_sim_data = {}  # Will hold flight data from best matching sim

    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        accel = float(fd.get('maxacceleration', '0'))
                        ghv = float(fd.get('groundhitvelocity', '999'))

                        # Pick the simulation closest to the altitude target
                        target_mid = (apogee_min + apogee_max) / 2.0
                        if not best_sim_data or \
                           abs(alt - target_mid) < abs(
                               best_sim_data.get('alt', 0) - target_mid):
                            best_sim_data = {
                                'alt': alt, 'accel': accel, 'ghv': ghv
                            }
                    except (ValueError, TypeError):
                        pass

    if uptodate_count >= 1:
        score += 12
        feedback.append(f"Up-to-date simulations: {uptodate_count} [12/12]")
    else:
        feedback.append("No up-to-date simulations found [0/12]")

    # ================================================================
    # Check 6: Apogee in target range (20 pts)
    # ================================================================
    sim_alt = best_sim_data.get('alt', 0)
    if sim_alt > 0:
        if apogee_min <= sim_alt <= apogee_max:
            score += 20
            feedback.append(
                f"Apogee {sim_alt:.1f}m in range ({apogee_min}-{apogee_max}m) [20/20]")
        elif (apogee_min - 50) <= sim_alt <= (apogee_max + 50):
            score += 10
            feedback.append(
                f"Apogee {sim_alt:.1f}m close to range [10/20]")
        else:
            feedback.append(
                f"Apogee {sim_alt:.1f}m outside range ({apogee_min}-{apogee_max}m) [0/20]")
    else:
        feedback.append("No altitude data available [0/20]")

    # ================================================================
    # Check 7: Max acceleration within limit (15 pts)
    # ================================================================
    sim_accel = best_sim_data.get('accel', 0)
    if sim_accel > 0:
        if sim_accel <= max_accel:
            score += 15
            feedback.append(
                f"Max acceleration {sim_accel:.1f} m/s^2 <= {max_accel} [15/15]")
        elif sim_accel <= max_accel * 1.2:
            score += 7
            feedback.append(
                f"Acceleration {sim_accel:.1f} m/s^2 slightly over limit [7/15]")
        else:
            feedback.append(
                f"Acceleration {sim_accel:.1f} m/s^2 exceeds limit [0/15]")
    else:
        feedback.append("No acceleration data available [0/15]")

    # ================================================================
    # Check 8: Ground hit velocity within limit (10 pts)
    # ================================================================
    sim_ghv = best_sim_data.get('ghv', 999)
    if sim_ghv < 999:
        if sim_ghv <= max_ghv:
            score += 10
            feedback.append(
                f"Ground hit velocity {sim_ghv:.1f} m/s <= {max_ghv} [10/10]")
        elif sim_ghv <= max_ghv * 1.5:
            score += 4
            feedback.append(
                f"Ground hit velocity {sim_ghv:.1f} m/s partially safe [4/10]")
        else:
            feedback.append(
                f"Ground hit velocity {sim_ghv:.1f} m/s unsafe [0/10]")
    else:
        feedback.append("No ground hit velocity data available [0/10]")

    # ================================================================
    # Check 9: Design file saved properly (4 pts)
    # ================================================================
    file_saved = (res_data.get('ork_exists', False) and
                  ork_md5 != start_md5 and
                  (ork_mtime == 0 or task_start_ts == 0 or
                   ork_mtime >= task_start_ts))
    if file_saved:
        score += 4
        feedback.append("Design file saved correctly [4/4]")
    elif res_data.get('ork_exists', False):
        score += 2
        feedback.append("Design file exists but may not be properly saved [2/4]")
    else:
        feedback.append("Design file not saved [0/4]")

    # ================================================================
    # Check 10: CSV export (4 pts)
    # ================================================================
    csv_size = res_data.get('csv_size', 0)
    if res_data.get('csv_exists', False) and csv_size > 100:
        score += 4
        feedback.append(f"CSV export present ({csv_size} bytes) [4/4]")
    elif res_data.get('csv_exists', False):
        score += 2
        feedback.append("CSV export exists but may be incomplete [2/4]")
    else:
        feedback.append("CSV export not found [0/4]")

    # ================================================================
    # Check 11: Design report with keywords (4 pts)
    # ================================================================
    content_lower = ''
    report_size = res_data.get('report_size', 0)
    if res_data.get('report_exists', False) and report_size > 0:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content_lower = f.read().lower()
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)

    if report_size >= 200 and len(content_lower) > 0:
        keywords = ['motor', 'stability', 'altitude', 'apogee',
                     'acceleration', 'recovery', 'parachute', 'descent']
        keyword_hits = sum(1 for kw in keywords if kw in content_lower)
        if keyword_hits >= 3:
            score += 4
            feedback.append(
                f"Report has good content ({keyword_hits} keywords) [4/4]")
        else:
            score += 2
            feedback.append(
                f"Report exists but lacks detail ({keyword_hits} keywords) [2/4]")
    elif res_data.get('report_exists', False):
        score += 1
        feedback.append("Report exists but is very short [1/4]")
    else:
        feedback.append("Report not found [0/4]")

    # ================================================================
    # Final pass/fail
    # ================================================================
    pass_threshold = metadata.get('pass_threshold', 65)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
