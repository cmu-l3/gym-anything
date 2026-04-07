#!/usr/bin/env python3
"""
Verifier for internal_cg_repositioning task.

Scoring breakdown (100 points total):
  15 pts - Motor Upgraded: Aerotech K550W correctly configured in the motor mount
  30 pts - Constraints Respected: Zero added mass components AND unchanged fin/tube dimensions
  25 pts - Components Repositioned: Both parachutes moved forward by >= 150mm
  15 pts - Simulation Run: At least one up-to-date simulation exists in the output file
  15 pts - Report Generated: Report file exists with meaningful size
  
Pass threshold: 65 points.
Agent must pass Constraints Respected AND Components Repositioned to get a passing score.
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

def get_dimensions_sum(root):
    length_sum = 0.0
    radius_sum = 0.0
    for tag in ['nosecone', 'bodytube', 'transition']:
        for el in root.iter(tag):
            try:
                length_sum += float(el.findtext('length', '0'))
                radius_sum += float(el.findtext('aftradius', '0')) + float(el.findtext('foreradius', '0')) + float(el.findtext('radius', '0'))
            except (ValueError, TypeError):
                pass
    for tag in ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']:
        for el in root.iter(tag):
            try:
                length_sum += float(el.findtext('height', '0'))
                radius_sum += float(el.findtext('rootchord', '0'))
            except (ValueError, TypeError):
                pass
    return length_sum, radius_sum

def get_parachutes_list(root):
    paras = []
    for para in root.iter('parachute'):
        pos_el = para.find('position')
        if pos_el is not None:
            try:
                paras.append({
                    'name': para.findtext('name', '').strip(),
                    'val': float(pos_el.text or 0),
                    'type': pos_el.get('type', 'top')
                })
            except ValueError:
                pass
    return paras

def verify_internal_cg_repositioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_output_path = metadata.get('ork_output_path', '/home/ga/Documents/exports/cg_optimized.ork')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/cg_optimization_report.txt')
    gt_ork_path = metadata.get('gt_ork_path', '/tmp/cg_optimization_gt.ork')
    target_motor = metadata.get('target_motor', 'K550')
    required_shift = metadata.get('required_shift_m', 0.145)  # slightly less than 0.150 for float tolerance
    pass_threshold = metadata.get('pass_threshold', 65)

    score = 0
    feedback_parts = []
    
    # Check export JSON
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    result = {}
    try:
        copy_from_env('/tmp/task_result.json', tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    if not result.get('ork_exists', False):
        return {"passed": False, "score": 0, "feedback": "Optimized .ork file not saved to expected location."}

    # Fetch GT and Optimized ORK files
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_opt = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_gt.close()
    tmp_opt.close()
    
    gt_root = None
    opt_root = None
    
    try:
        copy_from_env(gt_ork_path, tmp_gt.name)
        copy_from_env(ork_output_path, tmp_opt.name)
        
        gt_root, _ = _parse_ork(tmp_gt.name)
        opt_root, parse_err = _parse_ork(tmp_opt.name)
        
        if parse_err:
            feedback_parts.append(f"Could not parse optimized .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Error copying files: {e}")
    finally:
        if os.path.exists(tmp_gt.name):
            os.unlink(tmp_gt.name)
        if os.path.exists(tmp_opt.name):
            os.unlink(tmp_opt.name)

    if gt_root is None or opt_root is None:
        return {"passed": False, "score": 0, "feedback": "Failed to load ground truth or optimized rocket designs."}

    # Criterion 1: Motor Upgraded (15 points)
    motor_ok = False
    for motor in opt_root.iter('motor'):
        desig = motor.findtext('designation', '').upper()
        if target_motor in desig:
            motor_ok = True
            break
            
    if motor_ok:
        score += 15
        feedback_parts.append(f"Motor {target_motor} successfully installed [15/15 pts]")
    else:
        feedback_parts.append(f"Target motor {target_motor} not found [0/15 pts]")

    # Criterion 2: Constraints Respected (30 points)
    # 2a. Mass components
    gt_mass_count = len(list(gt_root.iter('masscomponent')))
    opt_mass_count = len(list(opt_root.iter('masscomponent')))
    
    # 2b. External dimensions
    gt_len, gt_rad = get_dimensions_sum(gt_root)
    opt_len, opt_rad = get_dimensions_sum(opt_root)
    
    mass_ok = (opt_mass_count <= gt_mass_count)
    dims_ok = (abs(gt_len - opt_len) < 0.005 and abs(gt_rad - opt_rad) < 0.005)
    
    constraints_respected = False
    if mass_ok and dims_ok:
        score += 30
        constraints_respected = True
        feedback_parts.append("Constraints respected (no ballast, no aero changes) [30/30 pts]")
    else:
        if not mass_ok:
            feedback_parts.append(f"Failed constraint: Added mass component (ballast detected) [0/30 pts]")
        if not dims_ok:
            feedback_parts.append(f"Failed constraint: Modified external aerodynamic dimensions [0/30 pts]")

    # Criterion 3: Components Repositioned (25 points)
    gt_paras = get_parachutes_list(gt_root)
    opt_paras = get_parachutes_list(opt_root)
    
    paras_moved_correctly = 0
    total_paras_checked = min(len(gt_paras), len(opt_paras))
    
    for i in range(total_paras_checked):
        gt_data = gt_paras[i]
        opt_data = opt_paras[i]
        if opt_data['type'] == 'top' and gt_data['type'] == 'top':
            # Moving forward implies distance offset from top decreases
            delta = gt_data['val'] - opt_data['val']
            if delta >= required_shift:
                paras_moved_correctly += 1
            else:
                feedback_parts.append(f"Parachute {i+1} only moved {delta*1000:.0f}mm (needs >=150mm)")
        else:
            # If reference type was changed from top, verification fails 
            feedback_parts.append(f"Parachute {i+1} position 'relative to' changed; verification requires 'top'")
                
    components_repositioned = False
    if total_paras_checked >= 2 and paras_moved_correctly >= 2:
        score += 25
        components_repositioned = True
        feedback_parts.append("Both parachutes moved forward >= 150mm [25/25 pts]")
    elif paras_moved_correctly == 1:
        score += 10
        feedback_parts.append("Only one parachute moved correctly [10/25 pts]")
    else:
        if total_paras_checked < 2:
            feedback_parts.append("Missing one or more parachutes in output [0/25 pts]")
        else:
            feedback_parts.append("Parachutes not moved forward by required distance [0/25 pts]")

    # Criterion 4: Simulation Run (15 points)
    sims = opt_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count > 0:
        score += 15
        feedback_parts.append(f"Found {uptodate_count} up-to-date simulation(s) [15/15 pts]")
    else:
        feedback_parts.append("No up-to-date simulations found [0/15 pts]")

    # Criterion 5: Report Generated (15 points)
    if result.get('report_exists', False) and result.get('report_size', 0) > 20:
        score += 15
        feedback_parts.append("Report file generated [15/15 pts]")
    else:
        feedback_parts.append("Report file missing or empty [0/15 pts]")

    # Final pass/fail gating
    key_criteria_met = constraints_respected and components_repositioned
    passed = (score >= pass_threshold) and key_criteria_met
    
    if not key_criteria_met and score >= pass_threshold:
        feedback_parts.append("FAILED: Must respect constraints AND properly reposition components to pass.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }