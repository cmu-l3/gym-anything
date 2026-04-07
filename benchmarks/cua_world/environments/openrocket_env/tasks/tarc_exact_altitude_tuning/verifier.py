#!/usr/bin/env python3
"""
Verifier for tarc_exact_altitude_tuning task.

Scoring Breakdown (100 points total):
  15 pts - Motor upgraded to C6.
  15 pts - Ballast mass component added specifically inside the nose cone (>0g).
  35 pts - Apogee successfully tuned to 200.0m +/- 2.0m (verified via uptodate simulation).
  15 pts - Tuning report generated with meaningful content.
  20 pts - VLM Verification: Agent trajectory shows workflow (Motor Config + Mass Tuning + Simulation).

Pass Threshold: 70 points AND the Apogee Tuned criteria must be successfully met.
"""

import os
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
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse XML: {e}"
    except Exception as e:
        return None, f"Could not open ORK: {e}"

def verify_tarc_exact_altitude_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/tuned_altitude_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/ballast_tuning_report.txt')
    target_alt = metadata.get('target_altitude_m', 200.0)
    tolerance = metadata.get('tolerance_m', 2.0)
    target_motor = metadata.get('target_motor', 'C6')

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. Fetch JSON result via copy_from_env
    # ================================================================
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        res_data = {}
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not res_data.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Target file {ork_vm_path} not found. Task abandoned."
        }

    # Anti-gaming: Ensure file was created during the task
    task_start = res_data.get('task_start_time', 0)
    ork_mtime = int(res_data.get('ork_mtime', 0))
    if ork_mtime > 0 and ork_mtime < task_start:
        return {"passed": False, "score": 0, "feedback": "ORK file predates task start time. Invalid submission."}

    # ================================================================
    # 2. Fetch ORK file and Parse XML
    # ================================================================
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Failed to parse ORK: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Failed to retrieve ORK: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if not ork_root:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # Criterion 1: Motor Upgraded to C6 (15 pts)
    # ================================================================
    has_c6 = False
    for code in ork_root.findall('.//enginecode') + ork_root.findall('.//designation'):
        if code.text and target_motor.upper() in code.text.upper():
            has_c6 = True
            break

    if has_c6:
        score += 15
        feedback_parts.append("C6 motor configured [15/15 pts]")
    else:
        feedback_parts.append("C6 motor not found in configuration [0/15 pts]")

    # ================================================================
    # Criterion 2: Ballast added to nose cone (15 pts)
    # ================================================================
    ballast_found = False
    nosecone = ork_root.find('.//nosecone')
    if nosecone is not None:
        for mass_comp in nosecone.findall('.//masscomponent'):
            mass_val = mass_comp.findtext('mass', '0')
            try:
                if float(mass_val) > 0:
                    ballast_found = True
                    break
            except ValueError:
                pass

    if ballast_found:
        score += 15
        feedback_parts.append("Mass component (>0g) found inside nose cone [15/15 pts]")
    else:
        feedback_parts.append("No mass component > 0g found inside nose cone [0/15 pts]")

    # ================================================================
    # Criterion 3: Apogee Tuned (35 pts)
    # ================================================================
    sims = ork_root.find('simulations')
    best_alt = None
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        # Select the closest altitude if multiple simulations exist
                        if best_alt is None or abs(alt - target_alt) < abs(best_alt - target_alt):
                            best_alt = alt
                    except ValueError:
                        pass

    if best_alt is not None:
        diff = abs(best_alt - target_alt)
        if diff <= tolerance:
            score += 35
            feedback_parts.append(f"Apogee tuned to {best_alt:.1f}m (Target {target_alt}±{tolerance}m) [35/35 pts]")
        elif diff <= tolerance * 5:
            score += 15
            feedback_parts.append(f"Apogee {best_alt:.1f}m is close but outside tolerance [15/35 pts]")
        else:
            feedback_parts.append(f"Apogee {best_alt:.1f}m is too far from target [0/35 pts]")
    else:
        feedback_parts.append("No uptodate simulations found. Run a simulation to verify altitude. [0/35 pts]")

    # ================================================================
    # Criterion 4: Report Written (15 pts)
    # ================================================================
    if res_data.get('report_exists', False) and res_data.get('report_size', 0) > 10:
        score += 15
        feedback_parts.append("Tuning report exists [15/15 pts]")
    else:
        feedback_parts.append("Tuning report missing or empty [0/15 pts]")

    # ================================================================
    # Criterion 5: VLM Trajectory Verification (20 pts)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
        except ImportError:
            images = []
            logger.warning("gym_anything.vlm not available for trajectory sampling.")

        if images:
            prompt = """You are analyzing a series of screenshots from a user performing a parametric tuning task in OpenRocket.
The user's goal was to add a 'Mass component' to the nose cone, change the motor to an 'Estes C6', and iteratively run simulations to target exactly 200m altitude.

Review the screenshots and determine if the user performed these actions.
Respond ONLY with a JSON object format:
{
  "interacted_with_motor": true/false,
  "interacted_with_mass": true/false,
  "ran_simulations": true/false
}"""
            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result and vlm_result.get('success') and 'parsed' in vlm_result:
                parsed = vlm_result['parsed']
                pts = 0
                if parsed.get('interacted_with_motor'): pts += 6
                if parsed.get('interacted_with_mass'): pts += 7
                if parsed.get('ran_simulations'): pts += 7
                vlm_score = pts
                feedback_parts.append(f"VLM trajectory check passed [{pts}/20 pts]")
            else:
                feedback_parts.append("VLM trajectory check failed or was unparseable [0/20 pts]")
        else:
            feedback_parts.append("No trajectory images available for VLM [0/20 pts]")
    else:
        # Gracefully auto-grant VLM points if framework does not supply `query_vlm` but XML criteria is perfectly met.
        if best_alt is not None and abs(best_alt - target_alt) <= tolerance:
            vlm_score = 20
            feedback_parts.append("VLM unavailable, auto-granting points due to perfect file validation [20/20 pts]")
        else:
            feedback_parts.append("VLM unavailable [0/20 pts]")

    score += vlm_score

    # ================================================================
    # Final Pass/Fail Calculation
    # ================================================================
    apogee_perfect = (best_alt is not None) and (abs(best_alt - target_alt) <= tolerance)
    passed = (score >= 70) and apogee_perfect

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }