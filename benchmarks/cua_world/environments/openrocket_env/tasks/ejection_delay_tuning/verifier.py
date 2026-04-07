#!/usr/bin/env python3
"""
Verifier for ejection_delay_tuning task.

Scoring breakdown (100 points total):
  20 pts - E16 Delay Tuned (3.0-8.0s) & deployevent is 'ejectioncharge'
  20 pts - F67 Delay Tuned (4.0-9.0s) & deployevent is 'ejectioncharge'
  20 pts - G40 Delay Tuned (5.0-9.0s) & deployevent is 'ejectioncharge'
  25 pts - Safe Deployments Verified: All 3 sims uptodate with < 15m/s deployment velocity
  15 pts - Tuning Report exists and mentions motors/delays

Pass threshold: 65 points
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


def verify_ejection_delay_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/delay_report.txt')
    delay_ranges = metadata.get('delay_ranges', {
        'E16': {'min': 3.0, 'max': 8.0},
        'F67': {'min': 4.0, 'max': 9.0},
        'G40': {'min': 5.0, 'max': 9.0}
    })
    max_deploy_vel = metadata.get('max_deployment_velocity_ms', 15.0)

    score = 0
    feedback_parts = []

    # Get the basic result output
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/ejection_delay_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res_json = json.load(f)
    except Exception as e:
        res_json = {}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not res_json.get('ork_exists'):
        return {"passed": False, "score": 0, "feedback": "ORK file not found"}

    ork_vm_path = res_json.get('ork_path')

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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"}

    # ---- Extract Parachute State (Anti-Gaming Check) ----
    is_ejection_charge = False
    for para in ork_root.iter('parachute'):
        de = para.findtext('deployevent', '').strip()
        if de == 'ejectioncharge':
            is_ejection_charge = True
            break
            
    if not is_ejection_charge:
        feedback_parts.append("CRITICAL: Parachute deploy event changed from 'Motor ejection charge'! (Anti-gaming violation)")
        # Cap score extremely low, as solving the problem natively was bypassed
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---- Extract Motor Settings ----
    motor_delays = {}
    for mm in ork_root.iter('motormount'):
        for m in mm.findall('motor'):
            cid = m.get('configid', '')
            desig = m.findtext('designation', '').strip()
            try:
                delay = float(m.findtext('delay', '-1'))
            except (ValueError, TypeError):
                delay = -1.0
            motor_delays[cid] = {'desig': desig, 'delay': delay}

    # Verify Delay Values
    motors_found = 0
    motors_tuned = 0
    for motor_name, drange in delay_ranges.items():
        found = False
        for cid, md in motor_delays.items():
            if motor_name in md['desig']:
                found = True
                motors_found += 1
                delay_val = md['delay']
                if drange['min'] <= delay_val <= drange['max']:
                    score += 20
                    motors_tuned += 1
                    feedback_parts.append(f"{motor_name} delay tuned ({delay_val}s) [20/20]")
                else:
                    feedback_parts.append(f"{motor_name} delay unsafe ({delay_val}s) [0/20]")
                break
        if not found:
            feedback_parts.append(f"{motor_name} config missing [0/20]")

    # ---- Verify Simulations ----
    sims = ork_root.find('simulations')
    safe_sims = 0
    total_expected = 3
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        dv = float(fd.get('deploymentvelocity', '999'))
                        if dv < max_deploy_vel:
                            safe_sims += 1
                    except (ValueError, TypeError):
                        pass

    if safe_sims >= total_expected:
        score += 25
        feedback_parts.append(f"All 3 sims safe deployment <{max_deploy_vel}m/s [25/25]")
    elif safe_sims > 0:
        pts = int(25 * (safe_sims / total_expected))
        score += pts
        feedback_parts.append(f"{safe_sims}/{total_expected} sims safe deployment [{pts}/25]")
    else:
        feedback_parts.append(f"No safe up-to-date sims [0/25]")

    # ---- Check Report ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r') as f:
            content = f.read().lower()
            if len(content) > 10 and any(m.lower() in content for m in ['e16', 'f67', 'g40']):
                score += 15
                feedback_parts.append("Tuning report found and valid [15/15]")
            elif len(content) > 0:
                score += 5
                feedback_parts.append("Tuning report found but lacks motor details [5/15]")
            else:
                feedback_parts.append("Tuning report empty [0/15]")
    except Exception:
        feedback_parts.append("Tuning report not found [0/15]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    passed = score >= metadata.get('pass_threshold', 65)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }