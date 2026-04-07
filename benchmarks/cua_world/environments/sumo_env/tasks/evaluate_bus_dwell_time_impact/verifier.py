#!/usr/bin/env python3
"""
Verifier for Evaluate Bus Dwell Time Impact task.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_container_file(copy_func, container_path):
    """Helper to copy a file from the container and return the local temp path."""
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.close()
    try:
        copy_func(container_path, tmp.name)
        if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name
    except Exception as e:
        logger.warning(f"Failed to copy {container_path}: {e}")
    
    if os.path.exists(tmp.name):
        os.unlink(tmp.name)
    return None

def verify_evaluate_bus_dwell_time_impact(traj, env_info, task_info):
    """
    Verify that the bus modifications were properly made, simulation executed, and metrics extracted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []

    # Read the main result JSON
    res_json_path = get_container_file(copy_from_env, "/tmp/task_result.json")
    if not res_json_path:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result JSON."}

    with open(res_json_path, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Invalid JSON in task_result.json"}
    os.unlink(res_json_path)

    # 1. Verify Modified Bus Route File (25 pts)
    bus_file_path = get_container_file(copy_from_env, "/tmp/pasubio_busses_slow.rou.xml")
    if bus_file_path:
        score += 5
        try:
            tree = ET.parse(bus_file_path)
            score += 5
            
            stops = tree.findall('.//stop')
            if stops:
                all_duration_60 = True
                no_until = True
                for stop in stops:
                    if stop.get('duration') != '60':
                        all_duration_60 = False
                    if 'until' in stop.attrib:
                        no_until = False
                
                if all_duration_60:
                    score += 10
                    feedback_parts.append("Bus file: All stops have duration='60'")
                else:
                    feedback_parts.append("Bus file: Some stops missing duration='60'")
                
                if no_until:
                    score += 5
                    feedback_parts.append("Bus file: No 'until' attributes found")
                else:
                    feedback_parts.append("Bus file: 'until' attributes still exist")
            else:
                feedback_parts.append("Bus file: No <stop> elements found in XML")
        except ET.ParseError:
            feedback_parts.append("Bus file exists but is invalid XML")
        
        os.unlink(bus_file_path)
    else:
        feedback_parts.append("pasubio_busses_slow.rou.xml not found")

    # 2. Verify Config File (15 pts)
    cfg_file_path = get_container_file(copy_from_env, "/tmp/run_slow_buses.sumocfg")
    if cfg_file_path:
        score += 5
        try:
            tree = ET.parse(cfg_file_path)
            score += 5
            
            adds = tree.findall('.//additional-files')
            cfg_valid = False
            for add in adds:
                val = add.get('value', '')
                if 'pasubio_busses_slow.rou.xml' in val:
                    cfg_valid = True
                    break
            
            if cfg_valid:
                score += 5
                feedback_parts.append("Config file correctly references new bus file")
            else:
                feedback_parts.append("Config file missing reference to pasubio_busses_slow.rou.xml")
        except ET.ParseError:
            feedback_parts.append("Config file exists but is invalid XML")
            
        os.unlink(cfg_file_path)
    else:
        feedback_parts.append("run_slow_buses.sumocfg not found")

    # 3. Verify Simulation Execution & Ground Truth (30 pts)
    trip_file_path = get_container_file(copy_from_env, "/tmp/tripinfos_slow.xml")
    gt_average_duration = None
    
    if trip_file_path:
        score += 10
        try:
            tree = ET.parse(trip_file_path)
            bus_durations = []
            
            for trip in tree.findall('.//tripinfo'):
                vid = trip.get('id', '')
                if 'bus' in vid.lower():
                    try:
                        bus_durations.append(float(trip.get('duration', 0)))
                    except ValueError:
                        pass
            
            if bus_durations:
                gt_average_duration = sum(bus_durations) / len(bus_durations)
                score += 20
                feedback_parts.append(f"Simulation output valid. Found {len(bus_durations)} bus trips")
            else:
                feedback_parts.append("Simulation output valid but no bus trips found")
        except ET.ParseError:
            feedback_parts.append("Tripinfos output is invalid XML")
            
        os.unlink(trip_file_path)
    else:
        feedback_parts.append("tripinfos_slow.xml not found")

    # 4 & 5. Verify Report and Accuracy (30 pts = 10 for report + 20 for accuracy)
    report_file_path = get_container_file(copy_from_env, "/tmp/bus_impact_report.txt")
    if report_file_path:
        score += 5
        with open(report_file_path, 'r') as f:
            content = f.read()
            
        # Look for "average_bus_duration_seconds: <val>"
        match = re.search(r'average_bus_duration_seconds:\s*([0-9.]+)', content, re.IGNORECASE)
        if match:
            score += 5
            agent_avg_duration = float(match.group(1))
            feedback_parts.append(f"Report found with value: {agent_avg_duration}")
            
            # Compare with ground truth if available
            if gt_average_duration is not None:
                diff = abs(agent_avg_duration - gt_average_duration)
                if diff <= 1.0:
                    score += 20
                    feedback_parts.append("Calculated average duration is highly accurate")
                elif diff <= 5.0:
                    score += 10
                    feedback_parts.append("Calculated average duration is close (partial credit)")
                else:
                    feedback_parts.append(f"Calculated average ({agent_avg_duration}) deviates from ground truth ({gt_average_duration:.2f})")
            else:
                feedback_parts.append("Cannot verify accuracy: Ground truth missing due to bad simulation output")
        else:
            feedback_parts.append("Report exists but missing 'average_bus_duration_seconds: <value>' format")
            
        os.unlink(report_file_path)
    else:
        feedback_parts.append("bus_impact_report.txt not found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }