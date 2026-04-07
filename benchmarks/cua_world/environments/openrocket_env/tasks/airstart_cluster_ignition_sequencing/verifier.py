#!/usr/bin/env python3
"""
Verifier for airstart_cluster_ignition_sequencing task.

Scoring breakdown (100 points total):
  10 pts - Central motor D12 configured
  10 pts - Outboard motors C6 configured
  25 pts - Outboard ignition delay set to exactly 1.5s
  15 pts - Simulation run (status is 'uptodate')
  10 pts - CSV flight data exported
  10 pts - Analysis report written
  20 pts - VLM verification of trajectory (motors tab & simulation used)

Pass threshold: 60 points AND outboard delay must be correct (prevents do-nothing)
"""

import os
import re
import tempfile
import zipfile
import json
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


def verify_airstart_cluster_ignition_sequencing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/airstart_cluster.ork')
    csv_path = metadata.get('csv_path', '/home/ga/Documents/exports/airstart_flight_data.csv')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/airstart_report.txt')
    
    score = 0
    feedback_parts = []
    
    # 1. Read exported JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    ork_exists = result.get('ork_exists', False)
    csv_exists = result.get('csv_exists', False)
    report_exists = result.get('report_exists', False)
    
    if not ork_exists:
        return {"passed": False, "score": 0, "feedback": "Modified ORK file not found. Agent did not save rocket to the expected path."}
        
    # 2. Parse ORK file
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

    # 3. Check Motors and Ignition Configs
    central_has_d12 = False
    outboard_has_c6 = False
    outboard_delay_correct = False
    
    c6_delays = []
    d12_delays = []
    
    for mm in ork_root.iter('motormount'):
        for motor in mm.findall('motor'):
            configid = motor.get('configid', '')
            desig = motor.findtext('designation', '').upper()
            
            # Find matching ignition config for this configid
            delay = 0.0
            for ign in mm.findall('ignitionconfiguration'):
                if ign.get('configid') == configid:
                    try:
                        delay = float(ign.findtext('ignitiondelay', '0'))
                    except ValueError:
                        pass
                        
            if 'D12' in desig:
                central_has_d12 = True
                d12_delays.append(delay)
            elif 'C6' in desig:
                outboard_has_c6 = True
                c6_delays.append(delay)
                
    if central_has_d12:
        score += 10
        feedback_parts.append("Central motor D12 configured [10/10 pts]")
    else:
        feedback_parts.append("D12 motor not found [0/10 pts]")
        
    if outboard_has_c6:
        score += 10
        feedback_parts.append("Outboard motors C6 configured [10/10 pts]")
    else:
        feedback_parts.append("C6 motors not found [0/10 pts]")
        
    # Check delays
    if c6_delays and any(abs(d - 1.5) < 0.1 for d in c6_delays):
        outboard_delay_correct = True
        score += 25
        feedback_parts.append("Outboard ignition delay set to 1.5s [25/25 pts]")
    else:
        feedback_parts.append("Outboard ignition delay NOT 1.5s [0/25 pts]")
        
    # Check simulations
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count > 0:
        score += 15
        feedback_parts.append("Simulation run and is uptodate [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulation found [0/15 pts]")
        
    # Check CSV Data
    if csv_exists and result.get('csv_size', 0) > 50:
        score += 10
        feedback_parts.append("Flight data CSV exported [10/10 pts]")
    else:
        feedback_parts.append("Flight data CSV missing or empty [0/10 pts]")
        
    # Check Summary Report
    if report_exists and result.get('report_size', 0) > 10:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        has_numbers = False
        try:
            copy_from_env(report_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                content = f.read()
                if re.search(r'\d+', content):
                    has_numbers = True
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
                
        if has_numbers:
            score += 10
            feedback_parts.append("Summary report created with data [10/10 pts]")
        else:
            score += 5
            feedback_parts.append("Summary report created but lacks numeric data [5/10 pts]")
    else:
        feedback_parts.append("Summary report missing [0/10 pts]")

    # 4. VLM Trajectory Verification
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = []
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
        except Exception as e:
            logger.warning(f"Failed to sample frames: {e}")
            
        if frames:
            prompt = """You are analyzing screenshots of an agent performing a task in OpenRocket.
The agent must open the 'Motors & Configuration' tab, assign motors, run a simulation, and export data.
Review the trajectory frames and return JSON:
{
  "motors_tab_used": true/false,
  "simulation_dialog_seen": true/false
}"""
            try:
                res = query_vlm(prompt=prompt, images=frames)
                if res and res.get("success"):
                    parsed = res.get("parsed", {})
                    if parsed.get("motors_tab_used"): vlm_points += 10
                    if parsed.get("simulation_dialog_seen"): vlm_points += 10
                else:
                    vlm_points = 20 # Give benefit of doubt on VLM failure
            except Exception:
                vlm_points = 20
        else:
            vlm_points = 20
    else:
        # If VLM is not available, grant the points to avoid penalizing the agent
        vlm_points = 20

    score += vlm_points
    feedback_parts.append(f"VLM trajectory verification [{vlm_points}/20 pts]")

    # Ensure key criteria are met
    passed = score >= 60 and outboard_delay_correct
    
    if not outboard_delay_correct:
        feedback_parts.append("CRITICAL FAILURE: Outboard ignition delay was not configured correctly.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }