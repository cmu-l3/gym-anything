#!/usr/bin/env python3
"""
Verifier for network_stress_test_analysis task.

Checks:
1. Files were created during the task (anti-gaming).
2. The agent successfully generated both XML files.
3. The stress XML represents an actual scaled simulation (inserted > baseline).
4. The agent correctly extracted the peak metrics according to the instructions.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_sumo_summary(xml_path):
    """Parses a SUMO summary XML file for target metrics."""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        max_halting = 0
        min_speed = float('inf')
        max_inserted = 0
        
        for step in root.findall('step'):
            halting = int(step.get('halting', 0))
            running = int(step.get('running', 0))
            speed = float(step.get('meanSpeed', 0))
            inserted = int(step.get('inserted', 0))
            
            if halting > max_halting:
                max_halting = halting
                
            if running > 0 and speed < min_speed:
                min_speed = speed
                
            if inserted > max_inserted:
                max_inserted = inserted
                
        if min_speed == float('inf'):
            min_speed = 0.0
            
        return {
            "max_halting": max_halting,
            "min_speed": min_speed,
            "total_inserted": max_inserted
        }
    except Exception as e:
        logger.error(f"Failed to parse SUMO summary {xml_path}: {e}")
        return None

def verify_network_stress_test(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result metadata
    result_json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_tmp.name)
        with open(result_json_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        os.unlink(result_json_tmp.name)
        
    if not result.get("files_created_during_task", False):
        feedback_parts.append("Warning: Files were not created during the task timeframe.")
        
    if not result.get("baseline_exists") or not result.get("stress_exists") or not result.get("report_exists"):
        feedback_parts.append("Missing required output files.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Files missing."}

    score += 15
    feedback_parts.append("All output files exist")

    # 2. Extract and parse Baseline XML
    baseline_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/tmp/baseline_summary.xml", baseline_tmp.name)
        baseline_data = parse_sumo_summary(baseline_tmp.name)
    finally:
        os.unlink(baseline_tmp.name)
        
    # 3. Extract and parse Stress XML
    stress_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/tmp/stress_summary.xml", stress_tmp.name)
        stress_data = parse_sumo_summary(stress_tmp.name)
    finally:
        os.unlink(stress_tmp.name)
        
    if not baseline_data or not stress_data:
        feedback_parts.append("Failed to parse the generated XML summary files.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    score += 15
    
    # 4. Verify that scaling was actually applied in the stress scenario
    # A 1.2x scale should result in roughly ~15-20% more total inserted vehicles
    if stress_data['total_inserted'] > baseline_data['total_inserted'] * 1.05:
        score += 20
        feedback_parts.append("Scaling verified in stress simulation")
    else:
        feedback_parts.append("Stress simulation does not appear to have --scale 1.2 applied")
        
    # 5. Extract and parse Agent's Text Report
    report_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    agent_report = {}
    try:
        copy_from_env("/tmp/stress_test_report.txt", report_tmp.name)
        with open(report_tmp.name, 'r') as f:
            for line in f:
                if ':' in line:
                    key, val = line.split(':', 1)
                    key = key.strip()
                    try:
                        agent_report[key] = float(val.strip())
                    except ValueError:
                        pass
    finally:
        os.unlink(report_tmp.name)

    # 6. Compare actual parsed data with agent's report
    metrics_correct = 0
    
    # Baseline Halting
    if 'baseline_max_halting' in agent_report and abs(agent_report['baseline_max_halting'] - baseline_data['max_halting']) < 0.1:
        metrics_correct += 1
        score += 12.5
    else:
        feedback_parts.append(f"baseline_max_halting incorrect (Expected: {baseline_data['max_halting']})")
        
    # Stress Halting
    if 'stress_max_halting' in agent_report and abs(agent_report['stress_max_halting'] - stress_data['max_halting']) < 0.1:
        metrics_correct += 1
        score += 12.5
    else:
        feedback_parts.append(f"stress_max_halting incorrect (Expected: {stress_data['max_halting']})")

    # Baseline Speed (Allow small float tolerance)
    if 'baseline_min_speed' in agent_report and abs(agent_report['baseline_min_speed'] - baseline_data['min_speed']) < 0.05:
        metrics_correct += 1
        score += 12.5
    else:
        feedback_parts.append(f"baseline_min_speed incorrect (Expected: {baseline_data['min_speed']:.3f})")

    # Stress Speed
    if 'stress_min_speed' in agent_report and abs(agent_report['stress_min_speed'] - stress_data['min_speed']) < 0.05:
        metrics_correct += 1
        score += 12.5
    else:
        feedback_parts.append(f"stress_min_speed incorrect (Expected: {stress_data['min_speed']:.3f})")

    if metrics_correct == 4:
        feedback_parts.append("All metrics correctly extracted")
        
    key_criteria_met = (metrics_correct >= 3 and result.get("files_created_during_task", False))
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }