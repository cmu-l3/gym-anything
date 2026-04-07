#!/usr/bin/env python3
"""
Verifier for payload_bay_integration task.

Scoring breakdown (100 points total):
  25 pts - Payload bay tube added (length 70-130mm)
  25 pts - Mass component added (mass 20-50g)
  20 pts - At least one simulation has 'uptodate' status
  10 pts - Design file saved and differs from original
  10 pts - Report written with meaningful content/keywords
  10 pts - Report contains numerical metrics (stability, altitude)

Pass threshold: 60 points
  Anti-gaming: If file matches original MD5 or not created after task start, score is 0.
"""

import os
import re
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

def verify_payload_bay_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/payload_integrated_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/payload_report.txt')
    min_len = metadata.get('min_tube_length_m', 0.070)
    max_len = metadata.get('max_tube_length_m', 0.130)
    min_mass = metadata.get('min_mass_kg', 0.020)
    max_mass = metadata.get('max_mass_kg', 0.050)

    score = 0
    feedback_parts = []

    # ---- 1. Check Export JSON & Anti-gaming ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/payload_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get('ork_exists', False):
        return {"passed": False, "score": 0, "feedback": "Target .ork file was not saved"}

    original_md5 = result.get('original_md5', '')
    new_md5 = result.get('new_md5', '')
    start_time = result.get('task_start_time', 0)
    ork_mtime = result.get('ork_mtime', 0)

    if new_md5 == original_md5 and original_md5 != '':
        return {"passed": False, "score": 0, "feedback": "Saved file is identical to original simple rocket. No modifications made."}

    if ork_mtime > 0 and ork_mtime < start_time:
        return {"passed": False, "score": 0, "feedback": "Saved file predates task start (anti-gaming)."}

    score += 10
    feedback_parts.append("Design file saved correctly [10/10 pts]")

    # ---- 2. Parse ORK for components ----
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

    # Evaluate body tubes
    bodytubes = list(ork_root.iter('bodytube'))
    tube_lengths = []
    has_payload_tube = False
    for bt in bodytubes:
        try:
            length = float(bt.findtext('length', '0'))
            tube_lengths.append(length)
            if min_len <= length <= max_len:
                has_payload_tube = True
        except (ValueError, TypeError):
            pass

    if has_payload_tube and len(bodytubes) >= 2:
        score += 25
        feedback_parts.append("Payload bay tube identified [25/25 pts]")
    elif has_payload_tube:
        score += 15
        feedback_parts.append("Tube of correct length found, but total tube count not increased [15/25 pts]")
    else:
        feedback_parts.append(f"No body tube found in range {min_len*1000}-{max_len*1000}mm [0/25 pts]")

    # Evaluate mass components
    has_target_mass = False
    for elem_name in ['masscomponent', 'massoverride']:
        for mc in ork_root.iter(elem_name):
            try:
                mass = float(mc.findtext('mass', '0'))
                if min_mass <= mass <= max_mass:
                    has_target_mass = True
            except (ValueError, TypeError):
                pass

    if has_target_mass:
        score += 25
        feedback_parts.append("Payload mass component identified [25/25 pts]")
    else:
        feedback_parts.append(f"No mass component found in range {min_mass*1000}-{max_mass*1000}kg [0/25 pts]")

    # Evaluate simulations
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1

    if uptodate_count >= 1:
        score += 20
        feedback_parts.append("Simulation is up-to-date [20/20 pts]")
    else:
        feedback_parts.append("No up-to-date simulations found [0/20 pts]")

    # ---- 3. Evaluate Report ----
    if result.get('report_exists', False) and result.get('report_size', 0) > 10:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read().lower()

            # Check keywords
            keywords = ['payload', 'tube', 'mass', 'altimeter', 'electronics', 'camera']
            found_kw = [kw for kw in keywords if kw in report_content]
            if len(found_kw) >= 2:
                score += 10
                feedback_parts.append("Report contains relevant keywords [10/10 pts]")
            else:
                score += 5
                feedback_parts.append("Report exists but missing expected keywords [5/10 pts]")

            # Check metrics
            has_numbers = bool(re.search(r'\d+(\.\d+)?', report_content))
            has_units = bool(re.search(r'(gram| g |m |meter|cal|caliber)', report_content))
            
            if has_numbers and has_units:
                score += 10
                feedback_parts.append("Report contains numerical metrics [10/10 pts]")
            elif has_numbers:
                score += 5
                feedback_parts.append("Report contains numbers but lacks units [5/10 pts]")
            else:
                feedback_parts.append("Report lacks numerical metrics [0/10 pts]")
                
        except Exception as e:
            feedback_parts.append(f"Failed to read report: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report file not found or empty [0/20 pts]")

    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }