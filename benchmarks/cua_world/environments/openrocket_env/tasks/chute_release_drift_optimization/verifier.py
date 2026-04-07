#!/usr/bin/env python3
"""
Verifier for chute_release_drift_optimization task.

Scoring breakdown (100 points total):
  20 pts - Altitude Deployment Set: Parachute deployevent is ALTITUDE with valid deployaltitude.
  10 pts - Environmental Wind Set: Uptodate simulation has windaverage >= 10.0 m/s.
  15 pts - Apogee Maintained: maxaltitude >= 300m (prevents swapping to a tiny motor).
  25 pts - Safe Hit Velocity: groundhitvelocity <= 6.0 m/s in uptodate simulation.
  20 pts - Drift Constraint Met: maxdistance <= 150m in uptodate simulation.
  10 pts - Optimization Report: Report file exists and contains metrics.

Pass threshold: 70 points
"""

import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import json
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
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_chute_release_drift_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/optimized_chute_release.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/chute_release_report.txt')
    target_wind = metadata.get('target_wind_ms', 10.0)
    min_apogee = metadata.get('min_apogee_m', 300.0)
    max_ghv = metadata.get('max_ground_hit_velocity_ms', 6.0)
    max_drift = metadata.get('max_drift_m', 150.0)
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Copy & Parse Result JSON
    # ---------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result_data.get('ork_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Target file {ork_vm_path} not found. Task not completed."
        }

    # ---------------------------------------------------------
    # Copy & Parse ORK File
    # ---------------------------------------------------------
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

    # ---------------------------------------------------------
    # Evaluate Parachutes
    # ---------------------------------------------------------
    altitude_deployment_set = False
    parachutes_found = False

    for para in ork_root.iter('parachute'):
        parachutes_found = True
        de = para.findtext('deployevent', '')
        
        try:
            da = float(para.findtext('deployaltitude', '0'))
        except (ValueError, TypeError):
            da = 0.0

        if de == 'ALTITUDE' and da > 0:
            altitude_deployment_set = True

    if altitude_deployment_set:
        score += 20
        feedback_parts.append("Altitude deployment correctly configured [20/20 pts]")
    elif parachutes_found:
        feedback_parts.append("Parachutes found, but deploy event is not ALTITUDE or deploy altitude is 0 [0/20 pts]")
    else:
        feedback_parts.append("No parachutes found in the design [0/20 pts]")

    # ---------------------------------------------------------
    # Evaluate Simulations
    # ---------------------------------------------------------
    sims = ork_root.find('simulations')
    best_sim = None

    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                cond = sim.find('conditions')
                wind = float(cond.findtext('windaverage', '0')) if cond is not None else 0.0
                
                fd = sim.find('flightdata')
                if fd is not None:
                    max_alt = float(fd.get('maxaltitude', '0'))
                    ghv = float(fd.get('groundhitvelocity', '999'))
                    drift = float(fd.get('maxdistance', '999'))
                    
                    # We want to pick the best simulation that matches the wind criteria
                    sim_record = {'wind': wind, 'max_alt': max_alt, 'ghv': ghv, 'drift': drift}
                    
                    if best_sim is None:
                        best_sim = sim_record
                    else:
                        # Prioritize simulations that met the wind constraint
                        if wind >= (target_wind - 0.1) and best_sim['wind'] < (target_wind - 0.1):
                            best_sim = sim_record
                        elif wind >= (target_wind - 0.1) and best_sim['wind'] >= (target_wind - 0.1):
                            # Both meet wind, pick one with lower GHV
                            if ghv < best_sim['ghv']:
                                best_sim = sim_record

    if best_sim:
        # 1. Wind Constraint
        if best_sim['wind'] >= (target_wind - 0.1):
            score += 10
            feedback_parts.append(f"Simulation wind set to {best_sim['wind']:.1f} m/s [10/10 pts]")
        else:
            feedback_parts.append(f"Simulation wind is {best_sim['wind']:.1f} m/s, expected {target_wind} m/s [0/10 pts]")

        # 2. Apogee Constraint (Anti-gaming)
        if best_sim['max_alt'] >= min_apogee:
            score += 15
            feedback_parts.append(f"Apogee maintained at {best_sim['max_alt']:.1f}m >= {min_apogee}m [15/15 pts]")
        else:
            feedback_parts.append(f"Apogee {best_sim['max_alt']:.1f}m dropped below {min_apogee}m! [0/15 pts]")

        # 3. Ground Hit Velocity (Safe Descent)
        if best_sim['ghv'] <= max_ghv:
            score += 25
            feedback_parts.append(f"Safe ground hit velocity at {best_sim['ghv']:.1f} m/s <= {max_ghv} m/s [25/25 pts]")
        else:
            feedback_parts.append(f"Unsafe ground hit velocity {best_sim['ghv']:.1f} m/s > {max_ghv} m/s [0/25 pts]")

        # 4. Drift Constraint
        if best_sim['drift'] <= max_drift:
            score += 20
            feedback_parts.append(f"Drift successfully limited to {best_sim['drift']:.1f}m <= {max_drift}m [20/20 pts]")
        else:
            feedback_parts.append(f"Excessive drift {best_sim['drift']:.1f}m > {max_drift}m [0/20 pts]")
    else:
        feedback_parts.append("No 'uptodate' simulations with flight data found. Run a simulation! [0/70 pts]")

    # ---------------------------------------------------------
    # Evaluate Report
    # ---------------------------------------------------------
    report_exists = result_data.get('report_exists', False)
    report_size = result_data.get('report_size', 0)

    if report_exists and report_size > 50:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', errors='ignore') as f:
                content = f.read().lower()
                
            keywords = ['drift', 'velocity', 'altitude', 'm/s', 'diameter']
            found_keywords = sum(1 for k in keywords if k in content)
            
            if found_keywords >= 2:
                score += 10
                feedback_parts.append("Optimization report is valid [10/10 pts]")
            else:
                score += 5
                feedback_parts.append("Report exists but lacks detailed metrics [5/10 pts]")
        except Exception:
            score += 5
            feedback_parts.append("Report exists but could not be parsed [5/10 pts]")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    elif report_exists:
        feedback_parts.append("Report file is too small or empty [0/10 pts]")
    else:
        feedback_parts.append("No optimization report found [0/10 pts]")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }