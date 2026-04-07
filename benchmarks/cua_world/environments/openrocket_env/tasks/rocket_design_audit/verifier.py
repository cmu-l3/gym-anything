#!/usr/bin/env python3
"""
Verifier for rocket_design_audit task.

Verification Strategy:
1. Parse the actual .ork XML to get ground truth values (dimensions, motor configs).
2. Check if the agent's .ork file has an 'uptodate' simulation.
3. If it does, extract the simulated flight data as ground truth.
4. Read the agent's text report.
5. Extract all numeric values from the report to perform robust matching against
   the ground truth lists (within specified tolerances) to avoid regex brittleness.

Scoring breakdown (100 points total):
  10 pts - Document exists and is substantial (>= 100 chars, contains numbers)
   5 pts - Identifies 3 stages
   8 pts - Body tube diameter match
   7 pts - Body tube length match
   8 pts - Nose cone shape match
   7 pts - Nose cone length match
   7 pts - Fin count match
  15 pts - Motor designations matched (5 pts per correct stage motor)
   8 pts - Recovery devices identified
  10 pts - Simulation was successfully run (status='uptodate' in .ork)
   5 pts - Max altitude match
   5 pts - Max velocity match
   5 pts - Ground hit velocity match

Pass threshold: 60 points
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

def _extract_all_numbers(text):
    """Extract all valid positive numbers (ints and floats) from text."""
    matches = re.findall(r'\b\d+(?:\.\d+)?\b', text)
    return [float(m) for m in matches]

def _match_any_number(targets, extracted_numbers, tolerance_pct):
    """Check if any extracted number matches any target within the tolerance percentage."""
    if not targets or not extracted_numbers:
        return False
    
    for target in targets:
        if target == 0:
            continue
        lower_bound = target * (1.0 - tolerance_pct / 100.0)
        upper_bound = target * (1.0 + tolerance_pct / 100.0)
        for num in extracted_numbers:
            if lower_bound <= num <= upper_bound:
                return True
    return False

def _match_string(targets, text):
    """Check if any target string is present in the text (case-insensitive)."""
    if not targets or not text:
        return False
    text_lower = text.lower()
    for t in targets:
        if t.lower() in text_lower:
            return True
    return False


def verify_rocket_design_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/audit_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/design_audit.txt')
    dim_tol = metadata.get('dimensional_tolerance_pct', 15)
    sim_tol = metadata.get('simulation_tolerance_pct', 20)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the text report
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_text = ""
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_text = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    extracted_numbers = _extract_all_numbers(report_text)

    # 2. Retrieve and parse the ORK file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if not ork_root:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to retrieve or parse rocket file"
        }

    # If document is missing or empty, agent fails entirely.
    if len(report_text) < 50 or not extracted_numbers:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report document missing, empty, or contains no data."
        }
    
    score += 10
    feedback_parts.append("Document exists with data [10/10 pts]")

    # ---- Extract Ground Truth from ORK ----

    # Stages
    stage_count = len(list(ork_root.iter('stage')))
    if _match_any_number([stage_count], extracted_numbers, 0):
        score += 5
        feedback_parts.append("Stage count correct [5/5 pts]")
    elif re.search(r'three|3', report_text, re.IGNORECASE):
        score += 5
        feedback_parts.append("Stage count found in text [5/5 pts]")

    # Body tubes (Diameters and Lengths)
    bt_diams = []
    bt_lengths = []
    for bt in ork_root.iter('bodytube'):
        try:
            bt_diams.append(float(bt.findtext('radius', '0')) * 2000.0) # to mm
            bt_lengths.append(float(bt.findtext('length', '0')) * 1000.0) # to mm
        except ValueError:
            pass
    
    if _match_any_number(bt_diams, extracted_numbers, dim_tol):
        score += 8
        feedback_parts.append("Body tube diameter match [8/8 pts]")
    
    if _match_any_number(bt_lengths, extracted_numbers, dim_tol):
        score += 7
        feedback_parts.append("Body tube length match [7/7 pts]")

    # Nose cones (Shape and Length)
    nc_shapes = []
    nc_lengths = []
    for nc in ork_root.iter('nosecone'):
        shape = nc.findtext('shape', '').lower()
        if shape: nc_shapes.append(shape)
        try:
            nc_lengths.append(float(nc.findtext('length', '0')) * 1000.0) # to mm
        except ValueError:
            pass

    if _match_string(nc_shapes, report_text):
        score += 8
        feedback_parts.append("Nose cone shape match [8/8 pts]")
    
    if _match_any_number(nc_lengths, extracted_numbers, dim_tol):
        score += 7
        feedback_parts.append("Nose cone length match [7/7 pts]")

    # Fins (Count)
    fin_counts = []
    for fin_type in ['trapezoidfinset', 'freeformfinset', 'ellipticalfinset']:
        for fin in ork_root.iter(fin_type):
            try:
                fin_counts.append(float(fin.findtext('fincount', '0')))
            except ValueError:
                pass
    
    if _match_any_number(fin_counts, extracted_numbers, 0):
        score += 7
        feedback_parts.append("Fin count match [7/7 pts]")

    # Motors
    motor_desigs = []
    for m in ork_root.iter('motor'):
        desig = m.findtext('designation', '')
        if desig: motor_desigs.append(desig)
    
    motor_score = 0
    matched_motors = 0
    for desig in set(motor_desigs):
        # Broad match ignoring dashes (e.g., "A8-3" matches if "A8" is in text)
        base_motor = desig.split('-')[0] if '-' in desig else desig
        if base_motor.lower() in report_text.lower():
            motor_score += 5
            matched_motors += 1
            
    # Cap motor score at 15
    motor_score = min(motor_score, 15)
    score += motor_score
    feedback_parts.append(f"Motors identified ({matched_motors}) [{motor_score}/15 pts]")

    # Recovery
    rec_diams = []
    for rec in list(ork_root.iter('parachute')) + list(ork_root.iter('streamer')):
        try:
            rec_diams.append(float(rec.findtext('diameter', '0')) * 1000.0) # to mm
        except ValueError:
            try:
                # Streamers use length
                rec_diams.append(float(rec.findtext('length', '0')) * 1000.0)
            except ValueError:
                pass

    if _match_any_number(rec_diams, extracted_numbers, dim_tol) or _match_string(["parachute", "streamer", "recovery"], report_text):
        score += 8
        feedback_parts.append("Recovery devices mentioned [8/8 pts]")

    # Simulations & Flight Data
    sims = ork_root.find('simulations')
    uptodate_sim_found = False
    max_alts = []
    max_vels = []
    gh_vels = []
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_sim_found = True
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        max_alts.append(float(fd.get('maxaltitude', '0')))
                        max_vels.append(float(fd.get('maxvelocity', '0')))
                        gh_vels.append(float(fd.get('groundhitvelocity', '0')))
                    except ValueError:
                        pass
    
    if uptodate_sim_found:
        score += 10
        feedback_parts.append("Simulation run (uptodate) [10/10 pts]")
        
        if _match_any_number(max_alts, extracted_numbers, sim_tol):
            score += 5
            feedback_parts.append("Max altitude match [5/5 pts]")
        
        if _match_any_number(max_vels, extracted_numbers, sim_tol):
            score += 5
            feedback_parts.append("Max velocity match [5/5 pts]")
            
        if _match_any_number(gh_vels, extracted_numbers, sim_tol):
            score += 5
            feedback_parts.append("Ground hit velocity match [5/5 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/25 pts for sim data]")

    passed = score >= metadata.get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }