#!/usr/bin/env python3
"""
Verifier for recovery_system_descent_analysis task.

Scoring breakdown (100 points total):
  25 pts - Main parachute diameter >= 700mm (was injected at 254mm)
  25 pts - Drogue parachute diameter >= 220mm (was injected at 76mm)
  25 pts - Ground hit velocity <= 6.5 m/s in an uptodate simulation
  15 pts - At least one simulation has 'uptodate' status
  10 pts - Descent analysis report exists with meaningful content

Pass threshold: 60 points
  Do-nothing max: 0 (parachutes still undersized, no uptodate sims, no report)
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


def verify_recovery_system_descent_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/recovery_analysis.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/descent_analysis_report.txt')
    min_main = metadata.get('min_main_diameter_m', 0.700)
    min_drogue = metadata.get('min_drogue_diameter_m', 0.220)
    max_ghv = metadata.get('max_ground_hit_velocity_ms', 6.5)

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

    # ---- Find parachute diameters ----
    main_diam = 0.0
    drogue_diam = 0.0
    for para in ork_root.iter('parachute'):
        name_el = para.find('name')
        name = name_el.text if name_el is not None else ''
        try:
            d = float(para.findtext('diameter', '0'))
        except (ValueError, TypeError):
            d = 0.0

        # Check for drogue (including "Drouge" typo in the .ork file)
        if 'drogue' in name.lower() or 'drouge' in name.lower():
            drogue_diam = max(drogue_diam, d)
        else:
            main_diam = max(main_diam, d)

    details['main_diameter_m'] = main_diam
    details['drogue_diameter_m'] = drogue_diam

    # ---- Check 1: Main parachute diameter (25 points) ----
    if main_diam >= min_main:
        score += 25
        feedback_parts.append(f"Main chute {main_diam*1000:.0f}mm >= {min_main*1000:.0f}mm [25/25 pts]")
    elif main_diam > 0.254:
        score += 10
        feedback_parts.append(f"Main chute {main_diam*1000:.0f}mm improved but < {min_main*1000:.0f}mm [10/25 pts]")
    else:
        feedback_parts.append(f"Main chute unchanged at {main_diam*1000:.0f}mm [0/25 pts]")

    # ---- Check 2: Drogue parachute diameter (25 points) ----
    if drogue_diam >= min_drogue:
        score += 25
        feedback_parts.append(f"Drogue chute {drogue_diam*1000:.0f}mm >= {min_drogue*1000:.0f}mm [25/25 pts]")
    elif drogue_diam > 0.076:
        score += 10
        feedback_parts.append(f"Drogue chute {drogue_diam*1000:.0f}mm improved but < {min_drogue*1000:.0f}mm [10/25 pts]")
    else:
        feedback_parts.append(f"Drogue chute unchanged at {drogue_diam*1000:.0f}mm [0/25 pts]")

    # ---- Check 3: GHV from uptodate simulation (25 points) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    ghv_values = []
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        ghv_values.append(float(fd.get('groundhitvelocity', '999')))
                    except (ValueError, TypeError):
                        pass

    details['uptodate_sims'] = uptodate_count
    details['ghv_values'] = ghv_values

    if ghv_values:
        best_ghv = min(ghv_values)
        if best_ghv <= max_ghv:
            score += 25
            feedback_parts.append(f"GHV {best_ghv:.1f} m/s <= {max_ghv} m/s [25/25 pts]")
        elif best_ghv <= 10.0:
            score += 12
            feedback_parts.append(f"GHV {best_ghv:.1f} m/s improved but > {max_ghv} m/s [12/25 pts]")
        else:
            feedback_parts.append(f"GHV {best_ghv:.1f} m/s still too high [0/25 pts]")
    else:
        feedback_parts.append("No flight data for GHV check [0/25 pts]")

    # ---- Check 4: At least one uptodate sim (15 points) ----
    if uptodate_count >= 1:
        score += 15
        feedback_parts.append(f"{uptodate_count} uptodate sim(s) [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/15 pts]")

    # ---- Check 5: Descent analysis report (10 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_score = 0
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r', errors='replace') as f:
            report_text = f.read()

        details['report_size'] = len(report_text)
        if len(report_text) >= 100:
            report_score = 5
            has_descent = bool(re.search(
                r'descent|velocity|parachute|chute|m/s|recovery', report_text, re.IGNORECASE
            ))
            if has_descent:
                report_score += 5
        elif len(report_text) >= 20:
            report_score = 3
        score += report_score
        feedback_parts.append(f"Descent report ({len(report_text)} chars) [{report_score}/10 pts]")
    except Exception:
        feedback_parts.append("Descent report not found [0/10 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
