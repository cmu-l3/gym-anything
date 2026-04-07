#!/usr/bin/env python3
"""
Verifier for stability_analysis_and_repair task.

Scoring breakdown (100 points total):
  35 pts - Fin height restored to >=50mm (was injected at 15mm)
  25 pts - At least one simulation has 'uptodate' status (re-run after fix)
  20 pts - Ground hit velocity <= 8 m/s in an uptodate simulation (stable flight)
  20 pts - Stability report file exists with meaningful content

Pass threshold: 60 points
  Do-nothing max: 0 (fins still 15mm, no uptodate sims, no report)
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


def verify_stability_analysis_and_repair(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/stability_check.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/stability_report.txt')
    min_fin_height = metadata.get('min_acceptable_fin_height_m', 0.050)

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

    # ---- Check 1: Fin height >= 50mm (35 points) ----
    max_fin_height = 0.0
    for fin in ork_root.iter('trapezoidfinset'):
        h_text = fin.findtext('height', '0')
        try:
            h = float(h_text)
            max_fin_height = max(max_fin_height, h)
        except (ValueError, TypeError):
            pass

    details['max_fin_height_m'] = max_fin_height
    if max_fin_height >= min_fin_height:
        score += 35
        feedback_parts.append(f"Fin height {max_fin_height*1000:.1f}mm >= {min_fin_height*1000:.0f}mm [35/35 pts]")
    elif max_fin_height > 0.015:
        score += 15
        feedback_parts.append(f"Fin height {max_fin_height*1000:.1f}mm improved but < {min_fin_height*1000:.0f}mm [15/35 pts]")
    else:
        feedback_parts.append(f"Fin height unchanged at {max_fin_height*1000:.1f}mm [0/35 pts]")

    # ---- Check 2: At least one uptodate simulation (25 points) ----
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
    if uptodate_count >= 1:
        score += 25
        feedback_parts.append(f"{uptodate_count} uptodate simulation(s) [25/25 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/25 pts]")

    # ---- Check 3: Reasonable ground hit velocity (20 points) ----
    details['ghv_values'] = ghv_values
    if ghv_values:
        min_ghv = min(ghv_values)
        if min_ghv <= 8.0:
            score += 20
            feedback_parts.append(f"Ground hit velocity {min_ghv:.1f} m/s <= 8.0 m/s [20/20 pts]")
        elif min_ghv <= 15.0:
            score += 10
            feedback_parts.append(f"Ground hit velocity {min_ghv:.1f} m/s marginal [10/20 pts]")
        else:
            feedback_parts.append(f"Ground hit velocity {min_ghv:.1f} m/s too high [0/20 pts]")
    else:
        feedback_parts.append("No flight data to check GHV [0/20 pts]")

    # ---- Check 4: Stability report (20 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_score = 0
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r', errors='replace') as f:
            report_text = f.read()

        details['report_size'] = len(report_text)
        if len(report_text) >= 150:
            report_score += 10
            has_stability = bool(re.search(
                r'stab|unstable|margin|CG|CP|center.*(pressure|gravity)', report_text, re.IGNORECASE
            ))
            has_fix = bool(re.search(
                r'fix|correct|enlarg|increas|restor|modif|adjust|fin', report_text, re.IGNORECASE
            ))
            if has_stability:
                report_score += 5
            if has_fix:
                report_score += 5
        elif len(report_text) >= 30:
            report_score = 5
        score += report_score
        feedback_parts.append(f"Stability report ({len(report_text)} chars) [{report_score}/20 pts]")
    except Exception:
        feedback_parts.append("Stability report not found [0/20 pts]")
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
