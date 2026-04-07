#!/usr/bin/env python3
"""
Verifier for motor_selection_parametric_sweep task.

Scoring breakdown (100 points total):
  50 pts - At least 7 simulations with 'uptodate' status AND >=4 distinct motor designations
           Partial: 15pts for >=4 sims with >=2 motors, 5pts for any sims
           NOTE: >=7 sims with <4 motors scores 0 (not a valid parametric sweep)
  20 pts - CSV export file exists with motor/altitude data
  15 pts - Written motor selection report exists with recommendation
  15 pts - Best simulation achieves within 30% of 3048m target altitude

Pass threshold: 60 points
  Do-nothing max: 0 (no sims, no CSV, no report)
"""

import os
import re
import tempfile
import zipfile
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


def _build_motor_map(root):
    """Build configid -> designation map from rocket motormount elements."""
    motor_map = {}
    for motor in root.iter('motor'):
        cid = motor.get('configid', '')
        desig = motor.findtext('designation', '').strip()
        if cid and desig:
            motor_map[cid] = desig
    return motor_map


def _get_simulation_stats(root):
    """Return list of dicts with motor designation and max altitude for uptodate sims."""
    motor_map = _build_motor_map(root)
    stats = []
    sims = root.find('simulations')
    if sims is None:
        return stats
    for sim in sims.findall('simulation'):
        if sim.get('status') != 'uptodate':
            continue
        fd = sim.find('flightdata')
        if fd is None:
            continue
        try:
            max_alt = float(fd.get('maxaltitude', '0'))
        except (ValueError, TypeError):
            max_alt = 0.0

        # Get motor designation via configid link
        conds = sim.find('conditions')
        motor_desig = 'unknown'
        if conds is not None:
            cid = conds.findtext('configid', '').strip()
            if cid and cid in motor_map:
                motor_desig = motor_map[cid]

        stats.append({'motor': motor_desig, 'maxaltitude_m': max_alt})
    return stats


def _count_distinct_motors(sim_stats):
    """Count distinct motor designations across all simulations."""
    motors = set()
    for s in sim_stats:
        m = s['motor'].strip()
        if m and m != 'unknown':
            motors.add(m)
    return len(motors)


def verify_motor_selection_parametric_sweep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/motor_sweep.ork')
    csv_vm_path = metadata.get('csv_vm_path', '/home/ga/Documents/exports/motor_comparison.csv')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/motor_selection_report.txt')
    target_alt = metadata.get('target_altitude_m', 3048)
    min_sims = metadata.get('min_simulations', 7)
    min_motors = metadata.get('min_distinct_motors', 4)

    score = 0
    feedback_parts = []
    details = {}

    # ---- Copy .ork file from VM ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"
        }

    sim_stats = _get_simulation_stats(ork_root)
    distinct_motors = _count_distinct_motors(sim_stats)
    details['uptodate_sim_count'] = len(sim_stats)
    details['distinct_motors'] = distinct_motors
    details['sim_stats'] = sim_stats[:10]

    # ---- Check 1: >=7 simulations, >=4 distinct motors (50 points) ----
    sim_pts = 0
    if len(sim_stats) >= min_sims and distinct_motors >= min_motors:
        sim_pts = 50
        feedback_parts.append(
            f"{len(sim_stats)} sims, {distinct_motors} distinct motors [50/50 pts]"
        )
    elif len(sim_stats) >= min_sims and distinct_motors < min_motors:
        # Enough sims but not enough motor diversity - not a valid parametric sweep
        sim_pts = 0
        feedback_parts.append(
            f"{len(sim_stats)} sims but only {distinct_motors}/{min_motors} distinct motors "
            f"(not a valid sweep) [0/50 pts]"
        )
    elif len(sim_stats) >= 4 and distinct_motors >= 2:
        sim_pts = 15
        feedback_parts.append(
            f"Only {len(sim_stats)}/{min_sims} sims, {distinct_motors} motors [15/50 pts]"
        )
    elif len(sim_stats) >= 1:
        sim_pts = 5
        feedback_parts.append(f"Only {len(sim_stats)} sim(s) run [5/50 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/50 pts]")
    score += sim_pts

    # ---- Check 2: CSV export (20 points) ----
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_csv.close()
    csv_score = 0
    try:
        copy_from_env(csv_vm_path, tmp_csv.name)
        with open(tmp_csv.name, 'r', errors='replace') as f:
            csv_text = f.read()

        details['csv_size'] = len(csv_text)
        if len(csv_text) >= 5:
            csv_score = 8
            if re.search(r'alt|apogee|height|m\b', csv_text, re.IGNORECASE):
                csv_score += 6
            if re.search(r'motor|sim|designation|config', csv_text, re.IGNORECASE):
                csv_score += 4
            if re.search(r'\d{3,}', csv_text):
                csv_score += 2
        score += csv_score
        feedback_parts.append(f"CSV export ({len(csv_text)} chars) [{csv_score}/20 pts]")
    except Exception:
        feedback_parts.append(f"CSV export not found [0/20 pts]")
    finally:
        if os.path.exists(tmp_csv.name):
            os.unlink(tmp_csv.name)

    # ---- Check 3: Motor selection report (15 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_score = 0
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r', errors='replace') as f:
            report_text = f.read()

        details['report_size'] = len(report_text)
        if len(report_text) >= 100:
            report_score = 7
            if re.search(r'recommend|best|optimal|select|choose', report_text, re.IGNORECASE):
                report_score += 4
            if re.search(r'\d{3,}\s*m', report_text, re.IGNORECASE):
                report_score += 2
            if re.search(r'[HIJKL]\d{3,}|aerotech|cesaroni|estes', report_text, re.IGNORECASE):
                report_score += 2
        elif len(report_text) >= 20:
            report_score = 3
        score += report_score
        feedback_parts.append(f"Motor report ({len(report_text)} chars) [{report_score}/15 pts]")
    except Exception:
        feedback_parts.append("Motor report not found [0/15 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    # ---- Check 4: Best altitude within 30% of target (15 points) ----
    if sim_stats:
        best_alt = max(s['maxaltitude_m'] for s in sim_stats)
        details['best_alt_m'] = best_alt
        lower_bound = target_alt * 0.70
        upper_bound = target_alt * 1.30

        if lower_bound <= best_alt <= upper_bound:
            score += 15
            feedback_parts.append(
                f"Best altitude {best_alt:.0f}m within 30% of {target_alt}m [15/15 pts]"
            )
        elif best_alt > target_alt * 0.5:
            score += 7
            feedback_parts.append(
                f"Best altitude {best_alt:.0f}m within 50% of {target_alt}m [7/15 pts]"
            )
        else:
            feedback_parts.append(
                f"Best altitude {best_alt:.0f}m far from {target_alt}m [0/15 pts]"
            )
    else:
        feedback_parts.append("No data for altitude check [0/15 pts]")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
