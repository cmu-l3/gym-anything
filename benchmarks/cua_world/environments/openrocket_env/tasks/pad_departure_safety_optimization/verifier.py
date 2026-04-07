#!/usr/bin/env python3
"""
Verifier for pad_departure_safety_optimization task.

Scoring breakdown (100 points total):
  20 pts - Launch rod length configured to exactly 2.0 meters
  25 pts - Launch rod clearance velocity >= 18.0 m/s
  25 pts - Max altitude <= 1200 m
  15 pts - At least one up-to-date simulation exists
  15 pts - Safety memo exists with reasonable file size

Pass threshold: 70 points
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

def verify_pad_departure_safety(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_vm = metadata.get('target_ork', '/home/ga/Documents/rockets/safe_janus.ork')
    req_rod_length = metadata.get('req_rod_length_m', 2.0)
    min_rod_velocity = metadata.get('min_rod_velocity_ms', 18.0)
    max_altitude = metadata.get('max_altitude_m', 1200.0)
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    # Check export results
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    try:
        copy_from_env("/tmp/pad_safety_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        result_data = {}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    ork_exists = result_data.get('ork_exists', False)
    memo_exists = result_data.get('memo_exists', False)
    memo_size = result_data.get('memo_size', 0)

    if not ork_exists:
        return {"passed": False, "score": 0, "feedback": "Modified .ork file (safe_janus.ork) was not created or saved."}

    # Retrieve and parse .ork file
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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"}

    # Evaluate Simulations
    sims = ork_root.find('simulations')
    best_sim_score = 0
    best_sim_feedback = []
    has_uptodate_sim = False
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') != 'uptodate':
                continue
                
            has_uptodate_sim = True
            current_sim_score = 15  # Up-to-date sim exists
            current_sim_feedback = ["Up-to-date simulation found [15/15 pts]"]
            
            # Check launch rod length
            rod_len_el = sim.find('./conditions/launchrodlength')
            rod_len = float(rod_len_el.text) if rod_len_el is not None else 1.0  # OpenRocket default is generally absent and fallback ~1.0m
            
            # Allow minor floating point diffs (e.g. 1.999 to 2.001)
            if abs(rod_len - req_rod_length) < 0.01:
                current_sim_score += 20
                current_sim_feedback.append(f"Launch rod length is {rod_len}m [20/20 pts]")
            else:
                current_sim_feedback.append(f"Launch rod length is {rod_len}m (expected {req_rod_length}m) [0/20 pts]")
                
            # Check flight data
            fd = sim.find('flightdata')
            if fd is not None:
                try:
                    rod_vel = float(fd.get('launchrodvelocity', '0'))
                    max_alt = float(fd.get('maxaltitude', '0'))
                except (ValueError, TypeError):
                    rod_vel, max_alt = 0.0, 0.0
                
                # Check velocity
                if rod_vel >= min_rod_velocity:
                    current_sim_score += 25
                    current_sim_feedback.append(f"Departure velocity {rod_vel:.1f} m/s >= {min_rod_velocity} m/s [25/25 pts]")
                else:
                    current_sim_feedback.append(f"Departure velocity {rod_vel:.1f} m/s < {min_rod_velocity} m/s [0/25 pts]")
                    
                # Check altitude
                if 0 < max_alt <= max_altitude:
                    current_sim_score += 25
                    current_sim_feedback.append(f"Apogee {max_alt:.1f} m <= {max_altitude} m [25/25 pts]")
                else:
                    current_sim_feedback.append(f"Apogee {max_alt:.1f} m > {max_altitude} m (or invalid) [0/25 pts]")
            else:
                current_sim_feedback.append("No flight data found in up-to-date simulation [0/50 pts]")
                
            # Keep the highest scoring simulation evaluation
            if current_sim_score > best_sim_score:
                best_sim_score = current_sim_score
                best_sim_feedback = current_sim_feedback
                
    if not has_uptodate_sim:
        best_sim_feedback.append("No up-to-date simulations found [0/85 pts]")
        
    score += best_sim_score
    feedback_parts.extend(best_sim_feedback)

    # Check memo
    if memo_exists and memo_size > 20:
        score += 15
        feedback_parts.append(f"Safety memo exists with data ({memo_size} bytes) [15/15 pts]")
    elif memo_exists:
        score += 5
        feedback_parts.append(f"Safety memo exists but is very small/empty [5/15 pts]")
    else:
        feedback_parts.append("Safety memo does not exist [0/15 pts]")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }