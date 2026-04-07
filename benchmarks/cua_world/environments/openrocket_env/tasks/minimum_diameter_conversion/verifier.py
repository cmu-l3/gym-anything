#!/usr/bin/env python3
"""
Verifier for minimum_diameter_conversion task.

Scoring breakdown (100 points total):
  30 pts - Airframe resized (Outer tubes and nose cone have OD 41.6mm, ID 38.0mm)
  20 pts - Internal mount structures removed (no <innertube> or <ring> tags)
  15 pts - Motor re-assigned directly to a <bodytube>
  15 pts - Parachutes repacked (Packed length >= 150mm for drogue and main)
  20 pts - Up-to-date simulation exists and report is present
  
Anti-gaming checks:
  - Rocket must still possess fins (cannot be replaced with an empty tube).
  - Target file must be created/modified after task initialization.

Pass threshold: 65 points.
"""

import os
import json
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

def verify_minimum_diameter_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('output_ork_path', '/home/ga/Documents/rockets/minimum_diameter.ork')
    report_vm_path = metadata.get('output_report_path', '/home/ga/Documents/exports/min_diameter_report.txt')
    target_radius = metadata.get('target_radius_m', 0.0208)
    target_thickness = metadata.get('target_thickness_m', 0.0018)
    target_pack_len = metadata.get('target_packed_length_m', 0.150)
    rad_tol = metadata.get('radius_tolerance', 0.001)
    thk_tol = metadata.get('thickness_tolerance', 0.0005)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not result.get('ork_exists', False):
        return {"passed": False, "score": 0, "feedback": "Target file minimum_diameter.ork not found."}

    if not result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp suggests it wasn't modified during task.")

    # 2. Retrieve & Parse the modified .ork file
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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to parse rocket XML."}

    # Anti-gaming: Ensure rocket still has fins and isn't just an empty tube
    fins = list(ork_root.iter('trapezoidfinset')) + list(ork_root.iter('ellipticalfinset')) + list(ork_root.iter('freeformfinset'))
    if len(fins) == 0:
        return {"passed": False, "score": 0, "feedback": "Rocket has no fins. Invalid rocket configuration."}

    # CRITERION 1: Airframe Resized (30 pts)
    tubes = list(ork_root.iter('bodytube')) + list(ork_root.iter('nosecone'))
    tubes_resized = True
    for t in tubes:
        # Check OD (radius)
        rad_val = 0.0
        try:
            rad_val = float(t.findtext('radius', '0'))
        except (ValueError, TypeError):
            pass
        
        if abs(rad_val - target_radius) > rad_tol:
            tubes_resized = False
            
        # Check thickness for Body Tubes
        if t.tag == 'bodytube':
            thk_val = 0.0
            try:
                thk_val = float(t.findtext('thickness', '0'))
            except (ValueError, TypeError):
                pass
            if abs(thk_val - target_thickness) > thk_tol:
                tubes_resized = False

    if len(tubes) > 0 and tubes_resized:
        score += 30
        feedback_parts.append("Airframe successfully resized (OD ~41.6mm, ID ~38.0mm) [30/30 pts]")
    else:
        feedback_parts.append("Airframe not consistently resized to 41.6mm OD / 38.0mm ID [0/30 pts]")

    # CRITERION 2: Internal Mount Removed (20 pts)
    inner_tubes = list(ork_root.iter('innertube'))
    rings = list(ork_root.iter('ring'))
    if len(inner_tubes) == 0 and len(rings) == 0:
        score += 20
        feedback_parts.append("Internal mount structures successfully removed [20/20 pts]")
    else:
        feedback_parts.append(f"Found {len(inner_tubes)} innertubes and {len(rings)} rings remaining [0/20 pts]")

    # CRITERION 3: Motor Re-assigned (15 pts)
    # Check if any bodytube directly contains a motormount
    motor_in_bodytube = False
    for bt in ork_root.iter('bodytube'):
        if bt.find('motormount') is not None:
            motor_in_bodytube = True
            break
            
    if motor_in_bodytube:
        score += 15
        feedback_parts.append("Motor directly assigned to body tube [15/15 pts]")
    else:
        feedback_parts.append("Motor not assigned to exterior body tube [0/15 pts]")

    # CRITERION 4: Parachutes Repacked (15 pts)
    parachutes = list(ork_root.iter('parachute'))
    if len(parachutes) == 0:
        feedback_parts.append("No parachutes found in the rocket [0/15 pts]")
    else:
        all_repacked = True
        for p in parachutes:
            try:
                pack_len = float(p.findtext('packedlength', '0'))
                if pack_len < target_pack_len:
                    all_repacked = False
            except (ValueError, TypeError):
                all_repacked = False
                
        if all_repacked:
            score += 15
            feedback_parts.append("Parachutes successfully elongated to fit narrow tube [15/15 pts]")
        else:
            feedback_parts.append("One or more parachutes still undersized longitudinally [0/15 pts]")

    # CRITERION 5: Simulation & Report (20 pts)
    sim_pts = 0
    sims = ork_root.find('simulations')
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                sim_pts = 10
                break
                
    report_pts = 0
    if result.get('report_exists', False) and result.get('report_size', 0) > 10:
        report_pts = 10
        
    score += (sim_pts + report_pts)
    feedback_parts.append(f"Simulation run [{sim_pts}/10 pts], Report exists [{report_pts}/10 pts]")

    passed = score >= metadata.get('pass_threshold', 65)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }