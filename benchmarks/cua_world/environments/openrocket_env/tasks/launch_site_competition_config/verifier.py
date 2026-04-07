#!/usr/bin/env python3
"""
Verifier for launch_site_competition_config task.

Validates that the target rocket file was saved, the correct environment
parameters were applied to the simulation, the simulation was successfully run,
and the required briefing file was generated.

Scoring breakdown (100 points total):
- 12 pts: Launch altitude correct
- 12 pts: Launch rod length correct
- 10 pts: Launch rod angle correct
- 8 pts: Latitude correct
- 8 pts: Longitude correct
- 10 pts: Wind average speed correct
- 8 pts: Wind turbulence intensity correct
- 17 pts: Simulation status is 'uptodate'
- 15 pts: Pre-launch briefing file exists and has meaningful content

Pass Threshold: 60 points
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
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def verify_launch_site_competition_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/competition_ready.ork')
    briefing_txt_path = metadata.get('briefing_txt_path', '/home/ga/Documents/exports/pre_launch_briefing.txt')

    score = 0
    feedback_parts = []
    
    # Check export results metadata
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # Anti-gaming: Ensure output file was created and modified
    if not result_data.get('ork_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Target file '{target_ork_path}' was not found. Agent did not save the rocket correctly."
        }
        
    if result_data.get('ork_md5') == result_data.get('starting_md5'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file is identical to the starting file. No modifications were made."
        }

    # Fetch and evaluate .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
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
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to read rocket file."}

    # Extract simulations and evaluate the best matching one
    sims = ork_root.find('simulations')
    if sims is None or len(list(sims.findall('simulation'))) == 0:
        return {"passed": False, "score": 0, "feedback": "No simulations found in the saved rocket file."}

    best_params_score = -1
    best_sim_feedback = []
    any_uptodate = False

    for sim in sims.findall('simulation'):
        sim_score = 0
        sim_feedback = []
        
        status = sim.get('status', 'outdated')
        if status == 'uptodate':
            any_uptodate = True
            
        conds = sim.find('conditions')
        if conds is not None:
            # Helper to safely extract float
            def _get_float(tag, default=0.0):
                try: return float(conds.findtext(tag, str(default)))
                except (ValueError, TypeError): return default

            alt = _get_float('launchaltitude')
            rod_len = _get_float('launchrodlength')
            rod_ang = _get_float('launchrodangle')
            lat = _get_float('launchlatitude')
            lon = _get_float('launchlongitude')
            wind = _get_float('windaverage')
            turb = _get_float('windturbulence')

            # Evaluate Altitude (Target: 1401, Tol: 100) -> 12 pts
            if 1301 <= alt <= 1501:
                sim_score += 12
                sim_feedback.append("Altitude correct")
            
            # Evaluate Rod Length (Target: 1.8, Tol: 0.15) -> 12 pts
            if 1.65 <= rod_len <= 1.95:
                sim_score += 12
                sim_feedback.append("Rod length correct")
                
            # Evaluate Rod Angle (Target: 0.0873 rad / 5 deg, Tol: 0.02) -> 10 pts
            if 0.067 <= rod_ang <= 0.107:
                sim_score += 10
                sim_feedback.append("Rod angle correct")
                
            # Evaluate Latitude (Target: 32.99, Tol: 1.0) -> 8 pts
            if 31.99 <= lat <= 33.99:
                sim_score += 8
                sim_feedback.append("Latitude correct")
                
            # Evaluate Longitude (Target: -106.97, Tol: 1.0) -> 8 pts
            if -107.97 <= lon <= -105.97:
                sim_score += 8
                sim_feedback.append("Longitude correct")
                
            # Evaluate Wind Speed (Target: 8.0, Tol: 2.0) -> 10 pts
            if 6.0 <= wind <= 10.0:
                sim_score += 10
                sim_feedback.append("Wind speed correct")
                
            # Evaluate Wind Turbulence (Target: 0.15, Tol: 0.05) -> 8 pts
            if 0.10 <= turb <= 0.20:
                sim_score += 8
                sim_feedback.append("Wind turbulence correct")

        if sim_score > best_params_score:
            best_params_score = sim_score
            best_sim_feedback = sim_feedback

    # Apply best configuration score
    score += best_params_score
    if best_params_score > 0:
        feedback_parts.append(f"Simulation parameters: {', '.join(best_sim_feedback)}")
    else:
        feedback_parts.append("Failed to configure simulation parameters correctly.")

    # Simulation Status (17 pts)
    if any_uptodate:
        score += 17
        feedback_parts.append("Simulation successfully run [17/17 pts]")
    else:
        feedback_parts.append("Simulation was not re-run (status is outdated) [0/17 pts]")

    # Evaluate Briefing Document (15 pts)
    if result_data.get('briefing_exists', False):
        tmp_brief = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(briefing_txt_path, tmp_brief.name)
            with open(tmp_brief.name, 'r') as f:
                content = f.read().lower()
                
            if len(content) > 100:
                has_alt_apogee = 'alt' in content or 'apogee' in content
                has_vel = 'vel' in content or 'speed' in content
                
                if has_alt_apogee and has_vel:
                    score += 15
                    feedback_parts.append("Briefing document exists and contains expected metrics [15/15 pts]")
                else:
                    score += 7
                    feedback_parts.append("Briefing exists but missing some expected flight metric keywords [7/15 pts]")
            else:
                feedback_parts.append("Briefing document exists but is too short/empty [0/15 pts]")
        except Exception as e:
            feedback_parts.append(f"Failed to verify briefing text content: {e}")
        finally:
            if os.path.exists(tmp_brief.name):
                os.unlink(tmp_brief.name)
    else:
        feedback_parts.append("Briefing document not found [0/15 pts]")

    threshold = metadata.get('pass_threshold', 60)
    passed = score >= threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }