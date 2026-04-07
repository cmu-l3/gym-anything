#!/usr/bin/env python3
"""
Verifier for fin_cant_spin_stabilization task.

Scoring Breakdown (100 points total):
  30 pts - Fin cant angle set to 3.0° ± 0.5°
  10 pts - The .ork file was successfully modified and saved
  25 pts - At least one simulation has an 'uptodate' status (indicating a simulation run post-modification)
  10 pts - Spin stabilization report file exists and is reasonably long (>= 100 chars)
  10 pts - Report specifically mentions the "3" or "3.0" degree cant angle
   8 pts - Report discusses spin physics (keywords: spin, roll, cant, rotation)
   7 pts - Report includes simulated altitude data (keywords: altitude, apogee, m, meters, feet)

Pass threshold: 60 points
  Do-nothing max: 0 points (no files saved)
"""

import os
import re
import math
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return the root XML element and an error string if any."""
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

def verify_fin_cant_spin_stabilization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_export_path = metadata.get('ork_export_path', '/home/ga/Documents/rockets/spin_stabilized_rocket.ork')
    report_export_path = metadata.get('report_export_path', '/home/ga/Documents/exports/spin_stabilization_report.txt')
    target_cant_deg = metadata.get('target_cant_deg', 3.0)
    cant_tolerance = metadata.get('cant_tolerance_deg', 0.5)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Retrieve Export Data
    # ---------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    result_data = {}
    try:
        copy_from_env("/tmp/fin_cant_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    ork_exists = result_data.get('ork_exists', False)
    report_exists = result_data.get('report_exists', False)

    if not ork_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Modified .ork file was not saved to the specified location. Task failed."
        }
        
    # ---------------------------------------------------------
    # Assess .ork file (Cant angle and simulations)
    # ---------------------------------------------------------
    score += 10
    feedback_parts.append("Modified .ork file exists [10/10 pts]")
    
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_export_path, tmp_ork.name)
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
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Find the maximum cant angle across all fin sets
    max_cant_deg = 0.0
    fin_tags = ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']
    
    for tag in fin_tags:
        for fin in ork_root.iter(tag):
            cant_text = fin.findtext('cant', '0')
            try:
                # OpenRocket stores cant in radians internally
                cant_rad = float(cant_text)
                cant_deg = abs(math.degrees(cant_rad))
                max_cant_deg = max(max_cant_deg, cant_deg)
            except (ValueError, TypeError):
                pass

    if abs(max_cant_deg - target_cant_deg) <= cant_tolerance:
        score += 30
        feedback_parts.append(f"Fin cant angle successfully set to {max_cant_deg:.2f}° [30/30 pts]")
    elif max_cant_deg > 0.0:
        feedback_parts.append(f"Fin cant angle is {max_cant_deg:.2f}° (expected ~{target_cant_deg}°) [0/30 pts]")
    else:
        feedback_parts.append("Fin cant angle is 0.0° (unchanged) [0/30 pts]")

    # Verify at least one simulation is up-to-date
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1

    if uptodate_count >= 1:
        score += 25
        feedback_parts.append(f"{uptodate_count} simulation(s) uptodate [25/25 pts]")
    else:
        feedback_parts.append("No uptodate simulations found (not run after modification) [0/25 pts]")

    # ---------------------------------------------------------
    # Assess Report text
    # ---------------------------------------------------------
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_content = ""
    
    if report_exists:
        try:
            copy_from_env(report_export_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)

    if report_content and len(report_content.strip()) >= 100:
        score += 10
        feedback_parts.append("Meaningful report created [10/10 pts]")
        
        content_lower = report_content.lower()
        
        # Check for angle reference
        if "3" in report_content or "3.0" in report_content:
            score += 10
            feedback_parts.append("Report mentions cant angle [10/10 pts]")
        else:
            feedback_parts.append("Report missing specific cant angle [0/10 pts]")
            
        # Check for physics discussion
        if any(w in content_lower for w in ['spin', 'roll', 'cant', 'rotation', 'stabilization']):
            score += 8
            feedback_parts.append("Report discusses spin/roll physics [8/8 pts]")
        else:
            feedback_parts.append("Report missing spin/roll discussion [0/8 pts]")
            
        # Check for performance/altitude data
        if any(w in content_lower for w in ['altitude', 'apogee', 'meters', 'feet', 'm', 'loss', 'drag']):
            score += 7
            feedback_parts.append("Report includes performance/altitude details [7/7 pts]")
        else:
            feedback_parts.append("Report missing altitude/performance data [0/7 pts]")
    else:
        if report_exists:
            feedback_parts.append("Report is empty or too short (< 100 chars) [0/35 pts]")
        else:
            feedback_parts.append("Report file not found [0/35 pts]")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    pass_threshold = metadata.get('pass_threshold', 60)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }