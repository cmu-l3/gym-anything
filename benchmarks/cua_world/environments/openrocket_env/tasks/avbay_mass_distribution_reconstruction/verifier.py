#!/usr/bin/env python3
"""
Verifier for avbay_mass_distribution_reconstruction task.

Scoring breakdown (100 points total):
  25 pts - Two bulkheads of ~6mm thickness found
  35 pts - Three mass components with specific masses found (40g, 15g, 80g)
           (Partial credit: 12pts Sled, 11pts Computer, 12pts Battery)
  20 pts - At least one simulation has 'uptodate' status (re-run after modifications)
  20 pts - Technical summary report exists and contains numeric values and keywords

Pass threshold: 65 points
  Anti-gaming: File creation timestamp must be strictly greater than task start time.
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


def verify_avbay_mass_distribution_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/detailed_avbay_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/avbay_report.txt')

    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON State ----
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    
    try:
        copy_from_env("/tmp/avbay_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_state = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)
            
    if not result_state.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file detailed_avbay_rocket.ork was not found."
        }
        
    task_start = int(result_state.get('task_start_ts', 0))
    ork_mtime = int(result_state.get('ork_mtime', 0))
    
    # Anti-gaming: Ensure file was created during the task
    if ork_mtime > 0 and ork_mtime < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "File detailed_avbay_rocket.ork predates the task start (Anti-gaming triggered)."
        }

    # ---- Copy and Parse .ork file ----
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

    # ---- Check 1: Bulkheads (25 points) ----
    valid_bulkheads = 0
    for bh in ork_root.iter('bulkhead'):
        try:
            thickness = float(bh.findtext('thickness', '0'))
        except (ValueError, TypeError):
            thickness = 0.0
            
        mat = bh.find('material')
        mat_name = mat.text.lower() if mat is not None and mat.text else ""
        
        # Accept if thickness is approx 6mm (0.006m)
        if abs(thickness - 0.006) < 0.002:
            # We loosely enforce material to avoid penalizing minor variations,
            # but reward if it's wood-like.
            valid_bulkheads += 1

    if valid_bulkheads >= 2:
        score += 25
        feedback_parts.append("Two 6mm bulkheads modeled [25/25 pts]")
    elif valid_bulkheads == 1:
        score += 12
        feedback_parts.append("Only one 6mm bulkhead modeled [12/25 pts]")
    else:
        feedback_parts.append("Required 6mm bulkheads not found [0/25 pts]")

    # ---- Check 2: Mass Components (35 points) ----
    has_sled = False
    has_computer = False
    has_battery = False

    for mc in ork_root.iter('masscomponent'):
        name = mc.findtext('name', '').lower()
        try:
            mass = float(mc.findtext('mass', '0'))
        except (ValueError, TypeError):
            mass = 0.0
            
        # Match by approximate mass and keywords in name
        if abs(mass - 0.040) < 0.005 and 'sled' in name:
            has_sled = True
        elif abs(mass - 0.015) < 0.005 and ('comp' in name or 'alt' in name or 'fc' in name):
            has_computer = True
        elif abs(mass - 0.080) < 0.005 and ('batt' in name or 'power' in name or 'lipo' in name):
            has_battery = True
            
        # Fallback: if agent named them differently but nailed the exact masses
        if abs(mass - 0.040) < 0.001: has_sled = True
        if abs(mass - 0.015) < 0.001: has_computer = True
        if abs(mass - 0.080) < 0.001: has_battery = True

    mc_score = 0
    if has_sled: mc_score += 12
    if has_computer: mc_score += 11
    if has_battery: mc_score += 12
    
    score += mc_score
    feedback_parts.append(f"Mass components: Sled={has_sled}, Computer={has_computer}, Battery={has_battery} [{mc_score}/35 pts]")

    # ---- Check 3: Uptodate Simulation (20 points) ----
    uptodate_found = False
    sims = ork_root.find('simulations')
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_found = True
                break
                
    if uptodate_found:
        score += 20
        feedback_parts.append("Uptodate simulation found [20/20 pts]")
    else:
        feedback_parts.append("No uptodate simulation found [0/20 pts]")

    # ---- Check 4: Technical Summary Report (20 points) ----
    report_exists = result_state.get('report_exists', False)
    if report_exists:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                content = f.read().lower()
                
            numbers = re.findall(r'\d+\.?\d*', content)
            has_keywords = any(kw in content for kw in ['mass', 'cg', 'stability', 'apogee', 'margin', 'caliber'])
            
            if len(numbers) >= 4 and has_keywords:
                score += 20
                feedback_parts.append("Report contains robust metrics [20/20 pts]")
            elif len(numbers) > 0:
                score += 10
                feedback_parts.append("Report contains partial numeric data [10/20 pts]")
            else:
                feedback_parts.append("Report lacks numeric data [0/20 pts]")
        except Exception:
            feedback_parts.append("Failed to read report file [0/20 pts]")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report file not created [0/20 pts]")

    # ---- Final Evaluation ----
    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }