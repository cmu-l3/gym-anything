#!/usr/bin/env python3
"""
Verifier for ttw_fin_structural_upgrade task.

Scoring breakdown (100 points total):
  25 pts - Fin Tabs configured (length >= 100mm, height >= 20mm)
  20 pts - TTW Centering Rings added (>=2 rings named 'Fin Ring' with Plywood material)
  15 pts - Motor Upgraded to AeroTech J350W
  20 pts - Simulation Run (status='uptodate')
  20 pts - Upgrade Report exists containing key metrics and values

Pass threshold: 60 points
  Requires active modification of .ork XML beyond just a text file.
"""

import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import json
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
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_ttw_fin_structural_upgrade(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/ttw_fin_upgrade.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/ttw_upgrade_report.txt')
    
    score = 0
    feedback_parts = []
    
    # ---- Read Export JSON ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/ttw_upgrade_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    if not export_res.get('ork_exists'):
        return {"passed": False, "score": 0, "feedback": f"Target file {ork_vm_path} not found."}

    # Verify timestamp to deter gaming
    task_start = export_res.get('task_start', 0)
    ork_mtime = export_res.get('ork_mtime', 0)
    if ork_mtime < task_start:
        feedback_parts.append("Warning: Modified .ork file is older than task start timestamp.")

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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"}

    # ---- 1. Fin Tabs (25 points) ----
    tab_found = False
    valid_tabs = False
    max_tab_length = 0.0
    max_tab_height = 0.0
    for finset in ork_root.iter('trapezoidfinset'):
        tabs = finset.find('fintabs')
        if tabs is not None:
            tab_found = True
            try:
                l = float(tabs.findtext('tablength', '0'))
                h = float(tabs.findtext('tabheight', '0'))
                max_tab_length = max(max_tab_length, l)
                max_tab_height = max(max_tab_height, h)
                if l >= 0.095 and h >= 0.015:  # Tolerance: length >= 100mm, height >= 20mm
                    valid_tabs = True
            except (ValueError, TypeError):
                pass
                
    if valid_tabs:
        score += 25
        feedback_parts.append(f"Fin tabs correctly configured (L:{max_tab_length*1000:.1f}mm, H:{max_tab_height*1000:.1f}mm) [25/25 pts]")
    elif tab_found:
        score += 10
        feedback_parts.append(f"Fin tabs found but undersized (L:{max_tab_length*1000:.1f}mm, H:{max_tab_height*1000:.1f}mm) [10/25 pts]")
    else:
        feedback_parts.append("No fin tabs found [0/25 pts]")

    # ---- 2. TTW Centering Rings (20 points) ----
    ttw_rings = 0
    for ring in ork_root.iter('ring'):
        name = ring.findtext('name', '').lower()
        if 'fin ring' in name:
            mat_elem = ring.find('material')
            mat = mat_elem.text.lower() if mat_elem is not None else ''
            if 'plywood' in mat or 'wood' in mat:
                ttw_rings += 1
                
    if ttw_rings >= 2:
        score += 20
        feedback_parts.append(f"Found {ttw_rings} Plywood Fin Rings [20/20 pts]")
    elif ttw_rings == 1:
        score += 10
        feedback_parts.append(f"Found only {ttw_rings} Plywood Fin Ring [10/20 pts]")
    else:
        feedback_parts.append("Could not find Plywood 'Fin Ring' components [0/20 pts]")

    # ---- 3. Motor Upgrade (15 points) ----
    motor_assigned = False
    correct_motor = False
    for mm in ork_root.iter('motormount'):
        for motor in mm.findall('motor'):
            desig = motor.findtext('designation', '').upper()
            motor_assigned = True
            if 'J350' in desig:
                correct_motor = True
                
    if correct_motor:
        score += 15
        feedback_parts.append("AeroTech J350W motor assigned [15/15 pts]")
    elif motor_assigned:
        score += 5
        feedback_parts.append("Motor assigned but not J350W [5/15 pts]")
    else:
        feedback_parts.append("No motor assigned [0/15 pts]")

    # ---- 4. Simulation Run (20 points) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count >= 1:
        score += 20
        feedback_parts.append(f"Found {uptodate_count} uptodate simulations [20/20 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/20 pts]")

    # ---- 5. Upgrade Report (20 points) ----
    report_exists = export_res.get('report_exists', False)
    if report_exists:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', errors='ignore') as f:
                content = f.read().lower()
                
            report_pts = 0
            if 'j350' in content: report_pts += 5
            if 'plywood' in content or 'wood' in content: report_pts += 5
            if '100' in content or '10' in content or '20' in content or '2' in content: report_pts += 5
            if 'velocity' in content or 'm/s' in content or 'mach' in content or 'acceleration' in content or 'm/s2' in content or 'g' in content: report_pts += 5
            
            score += report_pts
            feedback_parts.append(f"Report found with {report_pts} pts of content keywords [ {report_pts}/20 pts ]")
        except Exception as e:
            feedback_parts.append(f"Failed to read report: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Upgrade report not found [0/20 pts]")

    passed = score >= metadata.get('pass_threshold', 60)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }