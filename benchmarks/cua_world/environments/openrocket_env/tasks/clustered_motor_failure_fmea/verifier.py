#!/usr/bin/env python3
"""
Verifier for clustered_motor_failure_fmea task.

Scoring breakdown (100 points total):
  35 pts - Failure Config Created (A motor configuration exists with exactly 6 motors)
  15 pts - Nominal Preserved (The original 7-motor configuration is still present)
  30 pts - Failure Simulation Run (An `uptodate` simulation exists using the 6-motor failure configuration)
  20 pts - FMEA Report (`fmea_report.txt` exists and contains relevant trajectory/altitude analysis)

Pass threshold: 65 points
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

def verify_clustered_motor_failure_fmea(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/clustered_fmea.ork')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/fmea_report.txt')
    nominal_count = metadata.get('nominal_motor_count', 7)
    failure_count = metadata.get('failure_motor_count', 6)
    pass_threshold = metadata.get('pass_threshold', 65)

    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    result = {}
    try:
        copy_from_env("/tmp/fmea_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target ORK file clustered_fmea.ork was not created."
        }

    # ---- Copy .ork file from VM ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(target_ork_path, tmp_ork.name)
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

    # ---- Check 1 & 2: Motor Configurations (50 points) ----
    config_motor_counts = {}
    config_ids = set()
    
    # Initialize all config IDs
    configs_elem = ork_root.find('motorconfigurations')
    if configs_elem is not None:
        for mc in configs_elem.findall('motorconfiguration'):
            cid = mc.get('id')
            if cid:
                config_ids.add(cid)
                config_motor_counts[cid] = 0
                
    # Count motors per config
    for motor in ork_root.iter('motor'):
        cid = motor.get('configid')
        if cid:
            config_motor_counts[cid] = config_motor_counts.get(cid, 0) + 1

    has_nominal = False
    has_failure = False
    failure_config_id = None
    
    for cid, count in config_motor_counts.items():
        if count == nominal_count:
            has_nominal = True
        elif count == failure_count:
            has_failure = True
            failure_config_id = cid

    if has_failure:
        score += 35
        feedback_parts.append(f"Failure config with {failure_count} motors found [35/35 pts]")
    else:
        feedback_parts.append(f"No failure config with exactly {failure_count} motors found [0/35 pts]")

    if has_nominal:
        score += 15
        feedback_parts.append(f"Nominal config with {nominal_count} motors preserved [15/15 pts]")
    else:
        feedback_parts.append(f"Nominal config with {nominal_count} motors not preserved [0/15 pts]")

    # ---- Check 3: Failure Simulation Run (30 points) ----
    failure_sim_uptodate = False
    if has_failure and failure_config_id:
        sims = ork_root.find('simulations')
        if sims is not None:
            for sim in sims.findall('simulation'):
                if sim.get('status') == 'uptodate':
                    conds = sim.find('conditions')
                    if conds is not None:
                        cid = conds.findtext('configid', '').strip()
                        if cid == failure_config_id:
                            failure_sim_uptodate = True
                            break

    if failure_sim_uptodate:
        score += 30
        feedback_parts.append("Uptodate simulation found for failure config [30/30 pts]")
    elif has_failure:
        feedback_parts.append("No uptodate simulation found for failure config [0/30 pts]")
    else:
        feedback_parts.append("Cannot verify simulation without failure config [0/30 pts]")

    # ---- Check 4: FMEA Report (20 points) ----
    report_pts = 0
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                
                # Basic presence
                report_pts += 5
                
                # Check for altitude/apogee comparison
                if 'apogee' in content or 'altitude' in content or 'm' in content or 'ft' in content:
                    report_pts += 5
                    
                # Check for trajectory/physics analysis
                physics_words = ['asymmetric', 'trajectory', 'arc', 'deviation', 'spin', 'tumble', 'off-axis', 'thrust']
                if any(w in content for w in physics_words):
                    report_pts += 5
                    
                # Check for safety conclusion
                safety_words = ['safe', 'unsafe', 'hazard', 'conclusion', 'fmea', 'recommend', 'result']
                if any(w in content for w in safety_words):
                    report_pts += 5
                    
            feedback_parts.append(f"FMEA report evaluated [{report_pts}/20 pts]")
        else:
            feedback_parts.append("FMEA report is missing or empty [0/20 pts]")
    except Exception as e:
        feedback_parts.append(f"Could not read FMEA report: {e} [0/20 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)
            
    score += report_pts

    passed = score >= pass_threshold and has_failure and failure_sim_uptodate

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }