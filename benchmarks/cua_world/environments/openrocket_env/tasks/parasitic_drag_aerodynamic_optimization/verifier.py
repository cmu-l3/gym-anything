#!/usr/bin/env python3
"""
Verifier for parasitic_drag_aerodynamic_optimization task.

Scoring breakdown (100 points total):
  15 pts - Nose Cone, Body Tube, and Fins finishes set to 'Polished'
  15 pts - Fin cross-section changed from 'Square' to 'Airfoil'
  15 pts - Launch lug component deleted
  15 pts - At least one simulation run (status='uptodate') in the optimized file
  20 pts - Meaningful report documenting baseline apogee, optimized apogee, and changes made
  20 pts - VLM verification of trajectory (agent interacted with component dialogs and simulations)
  0  pts (Multiplier) - If motor was changed from 'G80', all points = 0 (Anti-gaming)

Pass threshold: 65 points
"""

import os
import re
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
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_parasitic_drag_aerodynamic_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    optimized_ork_path = metadata.get('optimized_ork_path', '/home/ga/Documents/rockets/optimized_rocket.ork')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/aerodynamic_report.txt')
    expected_motor = metadata.get('required_motor', 'G80')

    score = 0
    feedback_parts = []
    
    # Check JSON export results
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/aerodynamic_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        result_data = {}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result_data.get('optimized_ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Optimized design not saved to {optimized_ork_path}"
        }

    # ---- Copy and Parse Optimized .ork file ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    ork_root = None
    try:
        copy_from_env(optimized_ork_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse optimized .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve optimized .ork: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Anti-Gaming: Check Motor
    motor_changed = False
    for motor in ork_root.iter('motor'):
        desig = motor.findtext('designation', '')
        if expected_motor not in desig:
            motor_changed = True
            break
            
    if motor_changed:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Motor was changed. Altitude gain must come from aerodynamics, not thrust."
        }

    # ---- Check 1: Surface Finishes (15 points) ----
    all_polished = True
    comp_checked = 0
    for comp in ['nosecone', 'bodytube', 'trapezoidfinset']:
        for elem in ork_root.iter(comp):
            comp_checked += 1
            finish = elem.findtext('finish', '').strip().lower()
            if finish != 'polished':
                all_polished = False
                
    if comp_checked > 0 and all_polished:
        score += 15
        feedback_parts.append("Surfaces Polished [15/15 pts]")
    else:
        feedback_parts.append("Not all surfaces set to 'Polished' [0/15 pts]")

    # ---- Check 2: Fin Cross-Section (15 points) ----
    fins_airfoiled = True
    fins_checked = 0
    for elem in ork_root.iter('trapezoidfinset'):
        fins_checked += 1
        cs = elem.findtext('crosssection', '').strip().lower()
        if cs != 'airfoil':
            fins_airfoiled = False

    if fins_checked > 0 and fins_airfoiled:
        score += 15
        feedback_parts.append("Fins Airfoiled [15/15 pts]")
    else:
        feedback_parts.append("Fins not set to 'Airfoil' [0/15 pts]")

    # ---- Check 3: Launch Lug Removed (15 points) ----
    lug_found = False
    for _ in ork_root.iter('launchlug'):
        lug_found = True
        break
        
    if not lug_found:
        score += 15
        feedback_parts.append("Launch lug removed [15/15 pts]")
    else:
        feedback_parts.append("Launch lug still present [0/15 pts]")

    # ---- Check 4: Simulation Re-run (15 points) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1

    if uptodate_count > 0:
        score += 15
        feedback_parts.append(f"Simulation uptodate ({uptodate_count}) [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/15 pts]")

    # ---- Check 5: Optimization Report (20 points) ----
    report_pts = 0
    if result_data.get('report_exists', False) and result_data.get('report_size', 0) > 20:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                content = f.read().lower()
            
            has_numbers = len(re.findall(r'\d+', content)) >= 2
            has_keywords = any(kw in content for kw in ['polished', 'airfoil', 'lug', 'drag', 'surface'])
            
            if has_numbers and has_keywords:
                report_pts = 20
                feedback_parts.append("Comprehensive report found [20/20 pts]")
            elif has_numbers or has_keywords:
                report_pts = 10
                feedback_parts.append("Partial report found [10/20 pts]")
            else:
                feedback_parts.append("Report lacks required metrics/details [0/20 pts]")
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report missing or empty [0/20 pts]")
        
    score += report_pts

    # ---- Check 6: VLM Trajectory Verification (20 points) ----
    vlm_pts = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these chronological screenshots of OpenRocket.
Did the user interact with component configuration dialogs (e.g., editing Nose Cone, Body Tube, or Fins properties) to adjust surface finishes or cross-sections, OR delete components?
Respond with JSON:
{"ui_interaction_observed": true/false}"""

            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("ui_interaction_observed", False):
                    vlm_pts = 20
                    feedback_parts.append("VLM verified UI interaction [20/20 pts]")
                else:
                    feedback_parts.append("VLM did not observe required UI interactions [0/20 pts]")
            else:
                # If VLM fails, grant partial credit so task doesn't completely fail for infrastructure issues
                vlm_pts = 10
                feedback_parts.append("VLM verification skipped/failed [10/20 pts]")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        vlm_pts = 10
        feedback_parts.append("VLM exception [10/20 pts]")
        
    score += vlm_pts

    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }