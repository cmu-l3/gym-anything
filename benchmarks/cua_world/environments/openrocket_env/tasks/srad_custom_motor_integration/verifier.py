#!/usr/bin/env python3
"""
Verifier for srad_custom_motor_integration task.

Scoring breakdown (100 points total):
  25 pts - Saved .ork XML contains the correct custom motor assignment (mfg="SRAD_Team", code="SRAD_C40")
  25 pts - At least one simulation has 'uptodate' status AND has flight data with realistic maxaltitude
  20 pts - Report file exists, created during task, containing apogee and velocity metrics
  30 pts - VLM verification on trajectory confirms agent interacted with motor UI / preferences

Anti-gaming:
  - Agent cannot bypass UI entirely because fake XML without OR computation won't have the complex
    flight data traces. Verifier checks VLM trajectory to ensure the UI workflow was performed.
"""

import os
import re
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

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


def _verify_vlm_process(traj, query_vlm):
    """Use VLM to check if the agent interacted with the required motor configuration dialogs."""
    if not query_vlm:
        return 0, "query_vlm function not available"

    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images_to_check = frames + [final] if final else frames

    if not images_to_check:
        return 0, "No trajectory images available for VLM verification"

    prompt = """You are evaluating a sequence of screenshots from a rocketry engineering task in OpenRocket.
The user's goal was to import a custom solid rocket motor file (.eng) and assign it to a rocket.

Look at the progression of images and answer the following:
1. Did the user open the 'Preferences' dialog or a similar window to add 'User-defined motor files'?
2. Did the user open the 'Motor configuration' tab or a Motor Selection dialog showing motor manufacturers and designations?
3. Is there evidence that the user ran a flight simulation?

Respond in JSON format:
{
    "motor_preferences_visible": true/false,
    "motor_selection_visible": true/false,
    "simulation_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible in the frames"
}
"""
    try:
        result = query_vlm(prompt=prompt, images=images_to_check)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            pref_vis = parsed.get("motor_preferences_visible", False)
            select_vis = parsed.get("motor_selection_visible", False)
            sim_vis = parsed.get("simulation_visible", False)
            
            vlm_score = 0
            if pref_vis or select_vis:
                vlm_score += 20
            if sim_vis:
                vlm_score += 10
                
            return vlm_score, parsed.get("reasoning", "VLM returned no reasoning")
        else:
            return 0, f"VLM request failed: {result.get('error') if result else 'unknown'}"
    except Exception as e:
        return 0, f"VLM exception: {str(e)}"


def verify_srad_custom_motor_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_ork_path = metadata.get('expected_ork_path', '/home/ga/Documents/rockets/srad_simulated_rocket.ork')
    expected_report_path = metadata.get('expected_report_path', '/home/ga/Documents/exports/srad_flight_report.txt')
    expected_mfg = metadata.get('expected_mfg', 'SRAD_Team')
    expected_code = metadata.get('expected_code', 'SRAD_C40')
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    # ---- 1. Check exported metadata from export_result.sh ----
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get('ork_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target .ork file was not saved to expected location."
        }

    # ---- 2. Parse .ork file from VM (25 pts + 25 pts) ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(expected_ork_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is not None:
        # Check Motor Configuration
        motor_assigned = False
        for engine in ork_root.iter('engine'):
            mfg = engine.get('mfg', '')
            code = engine.get('code', '')
            if mfg == expected_mfg and code == expected_code:
                motor_assigned = True
                break
                
        if motor_assigned:
            score += 25
            feedback_parts.append(f"Custom motor {expected_mfg} {expected_code} properly assigned [25/25 pts]")
        else:
            feedback_parts.append("Custom motor not found in rocket motor mount [0/25 pts]")

        # Check Simulations
        sims = ork_root.find('simulations')
        valid_sim = False
        if sims is not None:
            for sim in sims.findall('simulation'):
                if sim.get('status') == 'uptodate':
                    fd = sim.find('flightdata')
                    if fd is not None:
                        try:
                            max_alt = float(fd.get('maxaltitude', '0'))
                            # A C-class motor in a ~50g rocket should yield > 100m, catching "empty" fake sims
                            if max_alt > 50.0 and max_alt < 1500.0:
                                valid_sim = True
                                break
                        except (ValueError, TypeError):
                            pass
                            
        if valid_sim:
            score += 25
            feedback_parts.append("Found valid up-to-date simulation with realistic altitude [25/25 pts]")
        else:
            feedback_parts.append("No valid up-to-date simulation found [0/25 pts]")

    # ---- 3. Check Report (20 pts) ----
    if export_data.get('report_exists') and export_data.get('report_created_during_task'):
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(expected_report_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                
            has_apogee = bool(re.search(r'\d+', content)) and ('apogee' in content or 'altitude' in content)
            has_velocity = bool(re.search(r'\d+', content)) and ('velocity' in content or 'speed' in content)
            
            report_pts = 0
            if has_apogee and has_velocity:
                report_pts = 20
                feedback_parts.append("Report contains apogee and velocity metrics [20/20 pts]")
            elif has_apogee or has_velocity:
                report_pts = 10
                feedback_parts.append("Report missing some metrics (apogee or velocity) [10/20 pts]")
            else:
                feedback_parts.append("Report exists but missing numeric metrics [0/20 pts]")
                
            score += report_pts
        except Exception:
            feedback_parts.append("Could not verify report contents [0/20 pts]")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report file not created [0/20 pts]")

    # ---- 4. VLM Trajectory Process Check (30 pts) ----
    vlm_score, vlm_reasoning = _verify_vlm_process(traj, query_vlm)
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"VLM verified motor UI interaction: {vlm_reasoning} [{vlm_score}/30 pts]")
    else:
        feedback_parts.append(f"VLM did not detect necessary UI interaction: {vlm_reasoning} [0/30 pts]")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }