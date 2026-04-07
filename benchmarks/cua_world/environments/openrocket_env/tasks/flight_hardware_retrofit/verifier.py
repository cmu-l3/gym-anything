#!/usr/bin/env python3
"""
Verifier for flight_hardware_retrofit task.

Scoring breakdown (100 points total):
  30 pts - At least 2 Launch Guides (rail buttons) added to the rocket.
  25 pts - An Altimeter mass component (45g +/- 2g) added.
  20 pts - At least one simulation run (status='uptodate').
  25 pts - Integration report exists and contains explanations citing drag and mass.

Pass threshold: 75 points.
Agent must demonstrate proficiency with both aerodynamic and mass components to pass.
"""

import os
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

def verify_flight_hardware_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/flight_ready_retrofit.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/hardware_penalty_report.txt')
    req_launch_guides = metadata.get('required_launch_guides', 2)
    req_mass_kg = metadata.get('required_mass_kg', 0.045)
    mass_tol = metadata.get('mass_tolerance_kg', 0.002)

    score = 0
    feedback_parts = []
    
    # Check export stats first
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/retrofit_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    if not export_data.get("ork_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Target ORK file '{ork_vm_path}' not found. Did you save it to the correct path?"
        }

    if not export_data.get("created_during_task", False):
        feedback_parts.append("WARNING: Output file may not have been saved during this task.")

    # ---- Copy and Parse ORK file ----
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
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve and parse rocket file."
        }

    # ---- Criterion 1: Launch Guides (30 points) ----
    launch_guides = list(ork_root.iter('launchguide'))
    lg_count = len(launch_guides)
    if lg_count >= req_launch_guides:
        score += 30
        feedback_parts.append(f"Added {lg_count} Launch Guides [30/30 pts]")
    elif lg_count > 0:
        score += 15
        feedback_parts.append(f"Added {lg_count} Launch Guide (needs {req_launch_guides}) [15/30 pts]")
    else:
        feedback_parts.append(f"No Launch Guides found [0/30 pts]")

    # ---- Criterion 2: Altimeter Mass (25 points) ----
    mass_found = False
    name_matched = False
    for mc in ork_root.iter('masscomponent'):
        mass_text = mc.findtext('mass', '0')
        name_text = mc.findtext('name', '').lower()
        try:
            mass_val = float(mass_text)
            if abs(mass_val - req_mass_kg) <= mass_tol:
                mass_found = True
                if "altimeter" in name_text:
                    name_matched = True
        except (ValueError, TypeError):
            pass

    if mass_found and name_matched:
        score += 25
        feedback_parts.append(f"45g Altimeter found [25/25 pts]")
    elif mass_found:
        score += 20
        feedback_parts.append(f"45g mass component found, but name doesn't include 'Altimeter' [20/25 pts]")
    else:
        feedback_parts.append("No 45g mass component found [0/25 pts]")

    # ---- Criterion 3: Simulation Uptodate (20 points) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
    
    if uptodate_count > 0:
        score += 20
        feedback_parts.append(f"{uptodate_count} simulation(s) uptodate [20/20 pts]")
    else:
        feedback_parts.append("No uptodate simulations found (re-run simulation after hardware changes) [0/20 pts]")

    # ---- Criterion 4: Integration Report (25 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r') as f:
            content = f.read().lower()
        
        if len(content) > 50:
            # Check for drag and mass keywords
            has_drag_kw = any(k in content for k in ['drag', 'aerodynamic', 'parasitic'])
            has_mass_kw = any(k in content for k in ['mass', 'weight', 'heavy', 'cg'])
            has_components = any(k in content for k in ['altimeter', 'rail', 'guide', 'button'])

            report_score = 0
            if has_drag_kw: report_score += 10
            if has_mass_kw: report_score += 10
            if has_components: report_score += 5
            
            score += report_score
            feedback_parts.append(f"Report analysis: scored {report_score}/25 pts based on content keywords.")
        else:
            feedback_parts.append("Report is empty or too short [0/25 pts]")
    except Exception:
        feedback_parts.append("Could not retrieve integration report [0/25 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    passed = score >= metadata.get('pass_threshold', 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }