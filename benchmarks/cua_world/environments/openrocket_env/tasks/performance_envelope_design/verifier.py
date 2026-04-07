#!/usr/bin/env python3
"""
Verifier for performance_envelope_design task.

Scoring breakdown (100 points total):
  15 pts - Motor changed (not C6 anymore)
  15 pts - Parachute resized to safe diameter (>= 280mm)
  15 pts - At least one simulation has 'uptodate' status
  20 pts - Altitude constraint met: 130m <= Apogee <= 170m
  20 pts - Descent velocity constraint met: GHV <= 5.5 m/s
  15 pts - Optimization report exists with meaningful keywords

Pass threshold: 60 points
  Requires multiple coordinated fixes + simulation + verification.
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


def verify_performance_envelope_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/simple_model_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/performance_envelope_report.txt')
    
    alt_min = metadata.get('target_altitude_min_m', 130.0)
    alt_max = metadata.get('target_altitude_max_m', 170.0)
    ghv_max = metadata.get('max_ground_hit_velocity_ms', 5.5)
    para_min = metadata.get('min_parachute_diameter_m', 0.280)
    injected_motor = metadata.get('injected_motor', 'C6')

    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON Metadata ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    result_data = {}
    try:
        copy_from_env("/tmp/envelope_design_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    ork_mtime = result_data.get('ork_mtime', 0)
    task_start_ts = result_data.get('task_start_ts', 0)
    
    # Anti-gaming: Check if .ork was actually modified after task start
    if ork_mtime > 0 and task_start_ts > 0 and ork_mtime <= task_start_ts:
        feedback_parts.append("WARNING: .ork file modification time is before task start. Agent may not have saved changes.")

    # ---- Copy .ork file from VM ----
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

    # ---- Check 1: Motor Changed (15 points) ----
    motor_changed = False
    active_motors = []
    for mm in ork_root.iter('motormount'):
        for motor in mm.findall('motor'):
            desig = motor.findtext('designation', '').strip().upper()
            if desig:
                active_motors.append(desig)
                if injected_motor not in desig:
                    motor_changed = True
                    
    # Also valid if no motors exist but they are testing via simulation conditions (rare, but possible)
    if motor_changed or not active_motors:
        score += 15
        motors_str = ", ".join(active_motors) if active_motors else "none"
        feedback_parts.append(f"Motor changed from {injected_motor} to {motors_str} [15/15 pts]")
    else:
        feedback_parts.append(f"Motor unchanged (still {injected_motor}) [0/15 pts]")

    # ---- Check 2: Parachute Resized (15 points) ----
    max_para_diam = 0.0
    for para in ork_root.iter('parachute'):
        try:
            d = float(para.findtext('diameter', '0'))
            max_para_diam = max(max_para_diam, d)
        except (ValueError, TypeError):
            pass

    if max_para_diam >= para_min:
        score += 15
        feedback_parts.append(f"Parachute sized safely at {max_para_diam*1000:.0f}mm [15/15 pts]")
    elif max_para_diam > 0.152:
        score += 5
        feedback_parts.append(f"Parachute improved to {max_para_diam*1000:.0f}mm but still undersized [5/15 pts]")
    else:
        feedback_parts.append(f"Parachute still critically undersized ({max_para_diam*1000:.0f}mm) [0/15 pts]")

    # ---- Check 3, 4, 5: Simulation Results (15, 20, 20 points) ----
    sims = ork_root.find('simulations')
    uptodate_sims = 0
    best_alt = 0.0
    best_ghv = 999.0
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_sims += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        v = float(fd.get('groundhitvelocity', '999'))
                        
                        # Keep track of the simulation that best satisfies the constraints
                        # If this one satisfies both, keep it. Otherwise keep closest.
                        if alt_min <= alt <= alt_max and v <= ghv_max:
                            best_alt = alt
                            best_ghv = v
                        elif best_alt == 0.0:  # Initialize with first found
                            best_alt = alt
                            best_ghv = v
                    except (ValueError, TypeError):
                        pass

    if uptodate_sims > 0:
        score += 15
        feedback_parts.append(f"Simulations uptodate: {uptodate_sims} [15/15 pts]")
        
        # Altitude Constraint
        if alt_min <= best_alt <= alt_max:
            score += 20
            feedback_parts.append(f"Apogee {best_alt:.1f}m in range (130-170m) [20/20 pts]")
        else:
            feedback_parts.append(f"Apogee {best_alt:.1f}m OUT of range (130-170m) [0/20 pts]")
            
        # Velocity Constraint
        if best_ghv <= ghv_max:
            score += 20
            feedback_parts.append(f"Descent velocity {best_ghv:.1f}m/s is safe (<= 5.5m/s) [20/20 pts]")
        else:
            feedback_parts.append(f"Descent velocity {best_ghv:.1f}m/s is UNSAFE (> 5.5m/s) [0/20 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/55 pts]")

    # ---- Check 6: Optimization Report (15 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_valid = False
    
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name):
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                if len(content) > 100:
                    has_motor = 'motor' in content or 'impulse' in content
                    has_para = 'parachute' in content or 'chute' in content or 'diameter' in content or 'descent' in content
                    has_alt = 'altitude' in content or 'apogee' in content or '150' in content
                    if has_motor and has_para and has_alt:
                        report_valid = True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    if report_valid:
        score += 15
        feedback_parts.append("Report is detailed and mentions key constraints [15/15 pts]")
    elif result_data.get('report_exists', False):
        score += 5
        feedback_parts.append("Report exists but lacks required detail/keywords [5/15 pts]")
    else:
        feedback_parts.append("Report not found [0/15 pts]")

    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }