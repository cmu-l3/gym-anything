#!/usr/bin/env python3
"""
Verifier for analyze_intersection_queues task.

Implements multi-signal verification via:
1. File checks indicating SUMO config was modified to request `<queue-output>`.
2. Artifact timestamp tracking verifying an actual active simulation run versus spoofing.
3. Stringent programmatic content verification comparing the agent's reported queue parameters 
   against a dynamic ground truth run computed automatically inside export_result.sh.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_intersection_queues(traj, env_info, task_info):
    """
    Verify that the agent correctly configured queue output, ran the simulation,
    and reliably extracted the proper maximum queue metrics.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    config_modified = result.get('config_modified', False)
    queues_xml_exists = result.get('queues_xml_exists', False)
    queues_xml_mtime = result.get('queues_xml_mtime', 0)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_content = result.get('report_content', '')

    gt_len = result.get('gt_max_length', -1.0)
    gt_lane = result.get('gt_max_lane', '')
    gt_time = result.get('gt_max_time', -1.0)

    # Criterion 1: Configuration Modified (20 points)
    if config_modified:
        score += 20
        feedback_parts.append("Config modified properly")
    else:
        feedback_parts.append("Config not modified properly")

    # Criterion 2: Simulation Executed via Timestamp validation (20 points)
    if queues_xml_exists and queues_xml_mtime >= task_start:
        score += 20
        feedback_parts.append("Simulation successfully executed")
    elif queues_xml_exists:
        feedback_parts.append("Simulation output exists but timestamp predates task (spoofing detected)")
    else:
        feedback_parts.append("Simulation not executed (queues.xml missing)")

    # Data Parsing
    agent_len, agent_lane, agent_time = None, None, None
    if report_exists and report_mtime >= task_start:
        m_len = re.search(r"max_queue_length:\s*([0-9.]+)", report_content, re.IGNORECASE)
        m_lane = re.search(r"max_queue_lane:\s*([A-Za-z0-9_.-]+)", report_content, re.IGNORECASE)
        m_time = re.search(r"max_queue_timestep:\s*([0-9.]+)", report_content, re.IGNORECASE)

        if m_len:
            try: agent_len = float(m_len.group(1))
            except Exception: pass
        if m_lane:
            agent_lane = m_lane.group(1).strip()
        if m_time:
            try: agent_time = float(m_time.group(1))
            except Exception: pass
            
        # Criterion 3: Correct Queue Length Tolerance (20 points)
        if agent_len is not None and abs(agent_len - gt_len) <= 0.01:
            score += 20
            feedback_parts.append(f"Correct queue length: {agent_len}")
        else:
            feedback_parts.append(f"Incorrect queue length (Expected: {gt_len}, Got: {agent_len})")

        # Criterion 4: Correct Lane ID match (20 points)
        if agent_lane is not None and agent_lane == gt_lane:
            score += 20
            feedback_parts.append(f"Correct lane ID: {agent_lane}")
        else:
            feedback_parts.append(f"Incorrect lane ID (Expected: '{gt_lane}', Got: '{agent_lane}')")

        # Criterion 5: Correct Timestep Extracted (20 points)
        if agent_time is not None and abs(agent_time - gt_time) <= 0.01:
            score += 20
            feedback_parts.append(f"Correct timestep: {agent_time}")
        else:
            feedback_parts.append(f"Incorrect timestep (Expected: {gt_time}, Got: {agent_time})")
    else:
        if not report_exists:
            feedback_parts.append("queue_report.txt not found")
        else:
            feedback_parts.append("queue_report.txt pre-dates the task session")

    key_criteria_met = config_modified and (queues_xml_exists and queues_xml_mtime >= task_start)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }