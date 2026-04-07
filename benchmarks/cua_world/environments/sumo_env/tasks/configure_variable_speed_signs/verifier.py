#!/usr/bin/env python3
"""
Verifier for configure_variable_speed_signs task.
Validates the XML structural integrity, correct domain values against the dynamic ground truth,
and ensures simulation logic successfully propagated to generating an output artifact.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def safe_copy_from_env(copy_from_env, remote_path, default_ext=".json"):
    """Helper to cleanly extract files from the container."""
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=default_ext)
    temp_file.close()
    try:
        copy_from_env(remote_path, temp_file.name)
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            return temp_file.name
    except Exception:
        pass
    if os.path.exists(temp_file.name):
        os.unlink(temp_file.name)
    return None

def verify_configure_variable_speed_signs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in env."}

    score = 0
    feedback_parts = []
    
    # 1. Pull necessary state files
    result_path = safe_copy_from_env(copy_from_env, "/tmp/task_result.json", ".json")
    gt_path = safe_copy_from_env(copy_from_env, "/tmp/vss_ground_truth.json", ".json")
    vss_path = safe_copy_from_env(copy_from_env, "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_vss.add.xml", ".xml")
    config_path = safe_copy_from_env(copy_from_env, "/home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg", ".xml")

    # Handle missing essential files
    if not result_path or not gt_path:
        return {"passed": False, "score": 0, "feedback": "Failed to read task export data or ground truth"}

    with open(result_path, 'r') as f:
        task_result = json.load(f)
    with open(gt_path, 'r') as f:
        gt = json.load(f)

    # Clean up JSON temporaries
    os.unlink(result_path)
    os.unlink(gt_path)

    # -------------------------------------------------------------
    # CRITERION 1 & 2 & 3 & 4: Variable Speed Sign XML Logic (60 points max)
    # -------------------------------------------------------------
    if not vss_path:
        feedback_parts.append("pasubio_vss.add.xml not found")
    else:
        try:
            tree = ET.parse(vss_path)
            root = tree.getroot()
            
            # Criterion 1: Root tag is 'additional'
            if root.tag == 'additional':
                score += 10
                feedback_parts.append("VSS root <additional> valid (+10)")
            else:
                feedback_parts.append(f"VSS root tag was <{root.tag}> instead of <additional>")

            # Criterion 2: Element structure and ID
            vss_element = root.find('.//variableSpeedSign')
            if vss_element is not None and vss_element.get('id') == 'vss_peak_control':
                score += 10
                feedback_parts.append("VSS element & ID correct (+10)")
                
                # Criterion 3: Lanes match exactly
                actual_lanes = set(vss_element.get('lanes', '').split())
                expected_lanes = set(gt['lanes'].split())
                if actual_lanes == expected_lanes:
                    score += 15
                    feedback_parts.append("VSS lanes match exact (+15)")
                elif len(actual_lanes.intersection(expected_lanes)) > 0:
                    score += 5
                    feedback_parts.append("VSS lanes partially match (+5)")
                else:
                    feedback_parts.append("VSS lanes incorrect")

                # Criterion 4: Step validation
                expected_steps = [
                    (0.0, float(gt['default_speed'])),
                    (300.0, float(gt['reduced_speed'])),
                    (900.0, float(gt['default_speed']))
                ]
                steps = vss_element.findall('step')
                if len(steps) == 3:
                    matched_steps = 0
                    for actual, expected in zip(steps, expected_steps):
                        try:
                            act_time = float(actual.get('time', -1))
                            act_speed = float(actual.get('speed', -1))
                            exp_time, exp_speed = expected
                            if abs(act_time - exp_time) < 1.0 and abs(act_speed - exp_speed) < 0.1:
                                matched_steps += 1
                        except ValueError:
                            pass
                    
                    if matched_steps == 3:
                        score += 25
                        feedback_parts.append("VSS schedule step elements exact (+25)")
                    elif matched_steps > 0:
                        score += 10
                        feedback_parts.append(f"VSS schedule step elements partial match {matched_steps}/3 (+10)")
                    else:
                        feedback_parts.append("VSS schedule steps exist but values incorrect")
                else:
                    feedback_parts.append(f"Found {len(steps)} <step> elements, expected 3")
            else:
                feedback_parts.append("<variableSpeedSign id='vss_peak_control'> not found")
        except ET.ParseError:
            feedback_parts.append("pasubio_vss.add.xml has invalid XML syntax")
        
        os.unlink(vss_path)

    # -------------------------------------------------------------
    # CRITERION 5 & 6: Configuration Logic (15 points max)
    # -------------------------------------------------------------
    if not config_path:
        feedback_parts.append("run.sumocfg not found")
    else:
        try:
            config_tree = ET.parse(config_path)
            config_root = config_tree.getroot()
            addl = config_root.find('.//additional-files')
            if addl is not None:
                val = addl.get('value', '')
                
                # Criterion 5: pasubio_vss.add.xml appended
                if 'pasubio_vss.add.xml' in val:
                    score += 10
                    feedback_parts.append("run.sumocfg appended new VSS file (+10)")
                else:
                    feedback_parts.append("run.sumocfg missing pasubio_vss.add.xml reference")
                
                # Criterion 6: Preserved originals
                required_originals = ['pasubio_vtypes.add.xml', 'pasubio_bus_stops.add.xml', 
                                      'pasubio_busses.rou.xml', 'pasubio_detectors.add.xml', 'pasubio_tls.add.xml']
                if all(r in val for r in required_originals):
                    score += 5
                    feedback_parts.append("Original additionals preserved (+5)")
                else:
                    feedback_parts.append("Original additionals accidentally deleted from run.sumocfg")
            else:
                feedback_parts.append("<additional-files> element missing from run.sumocfg")
        except ET.ParseError:
            feedback_parts.append("run.sumocfg has invalid XML syntax")

        os.unlink(config_path)

    # -------------------------------------------------------------
    # CRITERION 7: Simulation Output Execution & Anti-gaming (10 points max)
    # -------------------------------------------------------------
    task_start = task_result.get('task_start', 0)
    tripinfos_exists = task_result.get('tripinfos_exists', False)
    tripinfos_mtime = task_result.get('tripinfos_mtime', 0)
    
    if tripinfos_exists:
        if tripinfos_mtime >= task_start:
            score += 10
            feedback_parts.append("Simulation completed successfully (tripinfos.xml generated) (+10)")
        else:
            feedback_parts.append("tripinfos.xml found but has old timestamp (simulation wasn't re-run)")
    else:
        feedback_parts.append("Simulation output not found (did agent run sumo?)")

    # -------------------------------------------------------------
    # CRITERION 8: Trajectory Activity (VLM) (10 points max)
    # -------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        prompt = """Review the trajectory of an AI agent performing a task in a Linux environment.
Task: Configure Variable Speed Signs for a SUMO traffic simulation.
Did the agent visibly open a terminal or a text editor (e.g. nano, gedit, vim) at any point to create or modify XML configuration files?
And did the agent execute a command in the terminal to run the SUMO simulation?
Reply in JSON format:
{
  "used_editor_or_terminal": true/false,
  "ran_simulation": true/false
}"""
        vlm_resp = query_vlm(prompt=prompt, images=frames + [final])
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("used_editor_or_terminal"):
            score += 5
            feedback_parts.append("VLM confirmed editor/terminal use (+5)")
        if parsed.get("ran_simulation"):
            score += 5
            feedback_parts.append("VLM confirmed simulation execution (+5)")

    # Key threshold determining overall binary pass/fail
    # Requires structural XML success (score >= 60 to pass)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }