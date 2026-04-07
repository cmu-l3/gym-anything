#!/usr/bin/env python3
"""Verifier for evaluate_hov_lane_policy task."""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_evaluate_hov_lane_policy(traj, env_info, task_info):
    """
    Verify the HOV lane policy evaluation pipeline.
    
    Checks:
    1. Route file exists and has correct 160/40 demand split (25 points)
    2. TraCI script logic uses setAllowed appropriately (25 points)
    3. Simulation completed successfully, yielding tripinfo.xml (20 points)
    4. Data analysis produced correct values within tolerance (30 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_num_standard = metadata.get('num_standard', 160)
    expected_num_hov = metadata.get('num_hov', 40)

    score = 0
    feedback_parts = []
    
    # Copy and read the overall task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    route_stat = result.get('route_file', {})
    script_stat = result.get('script_file', {})
    tripinfo_stat = result.get('tripinfo_file', {})
    analysis_stat = result.get('analysis_file', {})

    # Helper function to read file contents from environment
    def get_file(remote_path):
        tmp = tempfile.NamedTemporaryFile(delete=False)
        tmp.close()
        try:
            copy_from_env(remote_path, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
                with open(tmp.name, 'r', encoding='utf-8') as f:
                    return f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
        return None

    # Criterion 1: Route File and Demand Split (25 points)
    route_xml = get_file("/home/ga/SUMO_Output/hov_demand.rou.xml") if route_stat.get('exists') else None
    if route_stat.get('exists') and route_stat.get('created_during_task'):
        score += 10
        feedback_parts.append("Route file created")
        if route_xml:
            try:
                root = ET.fromstring(route_xml)
                standard_cnt = 0
                hov_cnt = 0
                for veh in root.findall('vehicle') + root.findall('trip'):
                    vtype = veh.get('type')
                    if vtype == 'type_standard':
                        standard_cnt += 1
                    elif vtype == 'type_hov':
                        hov_cnt += 1
                
                if standard_cnt == expected_num_standard and hov_cnt == expected_num_hov:
                    score += 15
                    feedback_parts.append(f"Demand split correct ({standard_cnt} std, {hov_cnt} hov)")
                else:
                    feedback_parts.append(f"Demand split incorrect (found {standard_cnt} std, {hov_cnt} hov)")
            except ET.ParseError:
                feedback_parts.append("Route file is not valid XML")
    else:
        feedback_parts.append("Route file missing or not created during task")

    # Criterion 2: TraCI Script Logic (25 points)
    script_content = get_file("/home/ga/SUMO_Output/run_hov_sim.py") if script_stat.get('exists') else None
    if script_stat.get('exists') and script_stat.get('created_during_task'):
        if script_content:
            has_import = "import traci" in script_content
            has_set_allowed = "setAllowed" in script_content
            if has_import and has_set_allowed:
                score += 25
                feedback_parts.append("TraCI script logic verified")
            else:
                score += 10
                feedback_parts.append("TraCI script missing 'setAllowed'")
        else:
            feedback_parts.append("TraCI script could not be read")
    else:
        feedback_parts.append("TraCI script missing or not created during task")

    # Criterion 3: Simulation Execution (20 points)
    tripinfo_xml = get_file("/home/ga/SUMO_Output/tripinfo.xml") if tripinfo_stat.get('exists') else None
    ground_truth_standard = None
    ground_truth_hov = None
    if tripinfo_stat.get('exists') and tripinfo_stat.get('created_during_task'):
        if tripinfo_xml:
            try:
                root = ET.fromstring(tripinfo_xml)
                std_durations = []
                hov_durations = []
                for ti in root.findall('tripinfo'):
                    vtype = ti.get('vType')
                    dur = float(ti.get('duration', 0))
                    if vtype == 'type_standard':
                        std_durations.append(dur)
                    elif vtype == 'type_hov':
                        hov_durations.append(dur)
                
                if std_durations or hov_durations:
                    score += 20
                    feedback_parts.append("Simulation completed (tripinfo generated)")
                    if std_durations:
                        ground_truth_standard = sum(std_durations) / len(std_durations)
                    if hov_durations:
                        ground_truth_hov = sum(hov_durations) / len(hov_durations)
                else:
                    feedback_parts.append("tripinfo.xml contains no trips")
            except Exception as e:
                feedback_parts.append(f"tripinfo.xml parse error: {e}")
    else:
        feedback_parts.append("tripinfo.xml missing")

    # Criterion 4: Analysis Accuracy (30 points)
    analysis_content = get_file("/home/ga/SUMO_Output/hov_analysis.txt") if analysis_stat.get('exists') else None
    if analysis_stat.get('exists') and analysis_stat.get('created_during_task'):
        if analysis_content and ground_truth_standard is not None and ground_truth_hov is not None:
            agent_std = None
            agent_hov = None
            for line in analysis_content.splitlines():
                if "avg_duration_standard" in line:
                    match = re.search(r"avg_duration_standard=([\d\.]+)", line)
                    if match:
                        agent_std = float(match.group(1))
                elif "avg_duration_hov" in line:
                    match = re.search(r"avg_duration_hov=([\d\.]+)", line)
                    if match:
                        agent_hov = float(match.group(1))
            
            acc_score = 0
            # Adding margin of 1.0 seconds for floating point routing/precision variations across valid logic sets
            if agent_std is not None and abs(agent_std - ground_truth_standard) < 1.0:
                acc_score += 15
            if agent_hov is not None and abs(agent_hov - ground_truth_hov) < 1.0:
                acc_score += 15
            
            score += acc_score
            if acc_score == 30:
                feedback_parts.append("Analysis accuracy perfect")
            elif acc_score == 15:
                feedback_parts.append("Analysis accuracy partial")
            else:
                feedback_parts.append(f"Analysis incorrect (Expected std:~{ground_truth_standard:.2f}, hov:~{ground_truth_hov:.2f})")
        else:
            feedback_parts.append("Analysis missing values or ground truth unavailable")
    else:
        feedback_parts.append("Analysis file missing")

    # Final pass logic
    key_criteria_met = (tripinfo_stat.get('exists') and analysis_stat.get('exists') and score >= 75)
    passed = bool(key_criteria_met)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }