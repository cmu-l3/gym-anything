#!/usr/bin/env python3
"""
Verifier for model_traffic_incident task.

Verifies:
1. Incident XML contains a <stop> duration >= 900
2. Base simulation produced valid tripinfo XML.
3. Rerouted simulation produced valid tripinfo XML with routing devices.
4. Report file exists and correctly calculates the average duration from both XMLs.
5. Trajectory frames show active interaction with the terminal.
"""

import os
import json
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_average_duration_from_xml(xml_path):
    """Parse a tripinfo file and calculate the average trip duration."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        durations = []
        has_routing_device = False

        for tinfo in root.iter('tripinfo'):
            durations.append(float(tinfo.attrib.get('duration', 0)))
            devices = tinfo.attrib.get('devices', '')
            if 'routing' in devices:
                has_routing_device = True

        if durations:
            avg_dur = sum(durations) / len(durations)
            return avg_dur, has_routing_device
    except Exception as e:
        logger.warning(f"Failed to parse XML {xml_path}: {e}")
    
    return None, False


def check_incident_xml(xml_path):
    """Check if the incident XML file has a stop duration >= 900."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for stop in root.iter('stop'):
            dur = float(stop.attrib.get('duration', 0))
            if dur >= 900:
                return True
    except Exception as e:
        logger.warning(f"Failed to parse incident XML {xml_path}: {e}")
    
    return False


def verify_traffic_incident(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # --- 1. Load exported result JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result.get('task_start', 0)

    # --- 2. Check Incident Route File (20 pts) ---
    incident_info = result.get('incident_file', {})
    if incident_info.get('exists') and incident_info.get('mtime', 0) > task_start:
        # Copy and parse to check contents
        temp_incident = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(metadata.get('incident_file'), temp_incident.name)
            if check_incident_xml(temp_incident.name):
                score += 20
                feedback_parts.append("Incident XML created with 15min stop")
            else:
                feedback_parts.append("Incident XML lacks valid stop of >= 900s")
        finally:
            if os.path.exists(temp_incident.name):
                os.unlink(temp_incident.name)
    else:
        feedback_parts.append("Incident XML not created/modified during task")

    # --- 3. Check Base Tripinfo File (20 pts) ---
    base_info = result.get('base_tripinfo', {})
    base_avg_dur = None
    if base_info.get('exists') and base_info.get('mtime', 0) > task_start:
        temp_base = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(metadata.get('base_tripinfo'), temp_base.name)
            base_avg_dur, _ = calculate_average_duration_from_xml(temp_base.name)
            if base_avg_dur is not None:
                score += 20
                feedback_parts.append(f"Base simulation parsed successfully (Avg {base_avg_dur:.2f}s)")
            else:
                feedback_parts.append("Base simulation tripinfo exists but contains no valid data")
        finally:
            if os.path.exists(temp_base.name):
                os.unlink(temp_base.name)
    else:
        feedback_parts.append("Base tripinfo XML missing or old")

    # --- 4. Check Reroute Tripinfo File (20 pts) ---
    reroute_info = result.get('reroute_tripinfo', {})
    reroute_avg_dur = None
    if reroute_info.get('exists') and reroute_info.get('mtime', 0) > task_start:
        temp_reroute = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(metadata.get('reroute_tripinfo'), temp_reroute.name)
            reroute_avg_dur, used_routing = calculate_average_duration_from_xml(temp_reroute.name)
            if reroute_avg_dur is not None:
                if used_routing:
                    score += 20
                    feedback_parts.append(f"Rerouted simulation parsed with routing enabled (Avg {reroute_avg_dur:.2f}s)")
                else:
                    score += 10
                    feedback_parts.append(f"Rerouted simulation parsed (Avg {reroute_avg_dur:.2f}s) but routing device not found")
            else:
                feedback_parts.append("Rerouted simulation tripinfo exists but contains no valid data")
        finally:
            if os.path.exists(temp_reroute.name):
                os.unlink(temp_reroute.name)
    else:
        feedback_parts.append("Rerouted tripinfo XML missing or old")

    # --- 5. Verify Report Accuracy (25 pts) ---
    report_info = result.get('report_file', {})
    report_content = result.get('report_content', '')
    
    if report_info.get('exists') and report_info.get('mtime', 0) > task_start:
        base_match = re.search(r'Base Average Duration:\s*([\d.]+)', report_content, re.IGNORECASE)
        reroute_match = re.search(r'Rerouted Average Duration:\s*([\d.]+)', report_content, re.IGNORECASE)
        
        if base_match and reroute_match and base_avg_dur is not None and reroute_avg_dur is not None:
            reported_base = float(base_match.group(1))
            reported_reroute = float(reroute_match.group(1))
            
            # Allow for floating point differences within +/- 1 second
            base_correct = abs(reported_base - base_avg_dur) <= 1.0
            reroute_correct = abs(reported_reroute - reroute_avg_dur) <= 1.0
            
            if base_correct and reroute_correct:
                score += 25
                feedback_parts.append("Report successfully parsed and averages match ground truth")
            else:
                score += 10
                feedback_parts.append("Report generated but values don't match calculated ground truth")
        else:
            feedback_parts.append("Report exists but format is incorrect or simulations failed")
    else:
        feedback_parts.append("Impact report missing")

    # --- 6. VLM Verification for Terminal usage (15 pts) ---
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """The agent's task is to write configuration files and run command-line SUMO simulations.
Look at these trajectory frames.
Is there evidence of terminal interaction (e.g. typing commands, using a text editor, running SUMO headless)?

Respond with a JSON object:
{
    "terminal_activity": true/false,
    "observations": "brief description of terminal usage"
}"""
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        if parsed.get('terminal_activity', False):
            score += 15
            feedback_parts.append("VLM confirmed terminal interaction")
        else:
            feedback_parts.append("VLM did not observe terminal interaction")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        # Give partial credit if we can't run VLM to avoid penalizing agent for framework errors
        score += 10
        feedback_parts.append("VLM check skipped/failed")

    # Determine passing state
    key_criteria_met = (
        (incident_info.get('exists', False)) and 
        (base_info.get('exists', False)) and 
        (reroute_info.get('exists', False)) and
        (report_info.get('exists', False))
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }