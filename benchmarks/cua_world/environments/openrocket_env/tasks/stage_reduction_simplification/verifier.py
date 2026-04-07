#!/usr/bin/env python3
"""
Verifier for stage_reduction_simplification task.

Scoring breakdown (100 points total):
  10 pts - Valid .ork file outputted at the correct path, not a verbatim copy of a known example
  25 pts - Exactly 2 stages exist in the rocket design
  10 pts - Has a recovery system (parachute or streamer)
   5 pts - Has at least one set of fins
  10 pts - Has at least one motor configured
  25 pts - At least one simulation has 'uptodate' status (proves they verified it)
  15 pts - Meaningful modification report exists (>200 chars, relevant keywords)

Pass threshold: 60 points
  Requires stage reduction (25) + simulation (25) + valid file (10) as an absolute minimum to hit 60.
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


def verify_stage_reduction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_vm = metadata.get('target_ork_vm_path', '/home/ga/Documents/rockets/two_stage_simplified.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/stage_reduction_report.txt')

    score = 0
    feedback_parts = []
    
    # Read the JSON result from the container
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # 1. Check if output file exists and is not a verbatim cheat
    if not export_data.get("ork_exists"):
        return {"passed": False, "score": 0, "feedback": f"Required output file {target_ork_vm} not found."}
    
    if export_data.get("is_known_copy") == True:
        return {"passed": False, "score": 0, "feedback": "Output file is a verbatim copy of a known example. Agent did not do the work."}
    
    if not export_data.get("ork_created_during_task"):
        feedback_parts.append("Warning: .ork file modification time is older than task start.")

    # 2. Extract and Parse the .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(target_ork_vm, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to retrieve/parse rocket file"}

    score += 10
    feedback_parts.append("Valid .ork file found [10/10 pts]")

    # 3. Stage Count Check
    stages = list(ork_root.iter('stage'))
    stage_count = len(stages)
    if stage_count == 2:
        score += 25
        feedback_parts.append("Exactly 2 stages found [25/25 pts]")
    else:
        feedback_parts.append(f"Found {stage_count} stages (expected 2) [0/25 pts]")

    # 4. Recovery System Check
    parachutes = list(ork_root.iter('parachute'))
    streamers = list(ork_root.iter('streamer'))
    if len(parachutes) > 0 or len(streamers) > 0:
        score += 10
        feedback_parts.append("Recovery system present [10/10 pts]")
    else:
        feedback_parts.append("No parachute or streamer found [0/10 pts]")

    # 5. Fins Check
    finsets = (list(ork_root.iter('trapezoidfinset')) + 
               list(ork_root.iter('ellipticalfinset')) + 
               list(ork_root.iter('freeformfinset')))
    if len(finsets) > 0:
        score += 5
        feedback_parts.append("Fins present [5/5 pts]")
    else:
        feedback_parts.append("No fins found [0/5 pts]")

    # 6. Motor Check
    motors = list(ork_root.iter('motor'))
    motor_configs = list(ork_root.iter('motorconfiguration'))
    if len(motors) > 0 or len(motor_configs) > 0:
        score += 10
        feedback_parts.append("Motors assigned [10/10 pts]")
    else:
        feedback_parts.append("No motors assigned [0/10 pts]")

    # 7. Simulation Check
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
    
    if uptodate_count >= 1:
        score += 25
        feedback_parts.append(f"{uptodate_count} uptodate simulation(s) [25/25 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/25 pts]")

    # 8. Report Content Check
    report_pts = 0
    if export_data.get("report_exists"):
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Content checks
            if len(content) > 150:
                has_stage = bool(re.search(r'(stage|remov|delet|simplif)', content, re.IGNORECASE))
                has_perf = bool(re.search(r'(altitud|apogee|velocit|speed)', content, re.IGNORECASE))
                has_stab = bool(re.search(r'(stabl|margin|cg|cp)', content, re.IGNORECASE))
                has_num = bool(re.search(r'\d+', content))
                
                if has_stage and has_perf and has_stab and has_num:
                    report_pts = 15
                    feedback_parts.append("Comprehensive report found [15/15 pts]")
                else:
                    report_pts = 5
                    feedback_parts.append("Report exists but missing key domain information [5/15 pts]")
            else:
                feedback_parts.append("Report too short to be comprehensive [0/15 pts]")
        except Exception:
            feedback_parts.append("Failed to read report file.")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("No report found [0/15 pts]")
        
    score += report_pts

    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }