#!/usr/bin/env python3
"""
Verifier for fleeting_contact_aos_automation task.

This task requires the agent to write an aggressive polling script that waits
for a simulated 15-second Acquisition of Signal (AOS) window, sends a command,
and records the precise timestamps.

Scoring breakdown (100 pts total, pass threshold = 70):
  10pts  JSON file exists on Desktop and parses correctly.
  20pts  Simulation Triggered (agent properly sent the ready signal).
  30pts  System Command Verified (CMD_ACPT_CNT telemetry strictly increased) [HARD GATE].
  20pts  AOS Timing Accuracy (reported aos_timestamp is within 3s of actual).
  20pts  Command Execution Window (reported command_timestamp is within the AOS window).
 ---
 100pts total
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fleeting_contact_aos(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/task_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/pass_capture.json')

    score = 0
    feedback = []

    # 1. Read export metadata
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Failed to read export metadata: {e}'}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 2. Extract Ground Truth Data
    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    ready_signal = export_meta.get('ready_signal_sent', False)
    
    try:
        initial_cmd_acpt = float(export_meta.get('initial_cmd_acpt', 0))
        current_cmd_acpt = float(export_meta.get('current_cmd_acpt', 0))
    except ValueError:
        initial_cmd_acpt, current_cmd_acpt = 0, 0

    try:
        sim_aos_start = float(export_meta.get('aos_start_time', 0))
        sim_aos_end = float(export_meta.get('aos_end_time', 0))
    except ValueError:
        sim_aos_start, sim_aos_end = 0, 0

    # 3. Check Simulation Triggered (20 pts)
    if ready_signal and sim_aos_start > 0:
        score += 20
        feedback.append('Simulation triggered correctly via ready signal (+20)')
    else:
        feedback.append('Simulation was NOT triggered (ready signal missing or failed)')

    # 4. Check System Command Verified [HARD GATE] (30 pts)
    cmd_verified = False
    if current_cmd_acpt > initial_cmd_acpt:
        cmd_verified = True
        score += 30
        feedback.append(f'System command verified in telemetry (count increased {initial_cmd_acpt} -> {current_cmd_acpt}) (+30)')
    else:
        feedback.append('Command was NOT verified (CMD_ACPT_CNT did not increase)')

    # 5. Extract Agent JSON Output (10 pts)
    if not file_exists:
        feedback.append('Output JSON file not found on Desktop')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}
    
    if not file_is_new:
        feedback.append('Output JSON file predates task start (no content credit)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}

    agent_data = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            agent_data = json.load(f)
        score += 10
        feedback.append('Output JSON exists and parsed successfully (+10)')
    except Exception as e:
        feedback.append(f'Failed to parse output JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

    # 6. Assess Timing Accuracies
    try:
        agent_aos_ts = float(agent_data.get('aos_timestamp', 0))
        agent_cmd_ts = float(agent_data.get('command_timestamp', 0))
    except (ValueError, TypeError):
        agent_aos_ts, agent_cmd_ts = 0, 0

    # Timing checks only valid if simulation actually ran
    if sim_aos_start > 0:
        # AOS Timing Accuracy (20 pts)
        aos_diff = abs(agent_aos_ts - sim_aos_start)
        if 0 < aos_diff <= 3.0:
            score += 20
            feedback.append(f'AOS timing accurate (diff: {aos_diff:.2f}s) (+20)')
        else:
            feedback.append(f'AOS timing inaccurate or missing (diff: {aos_diff:.2f}s)')

        # Command Execution Window (20 pts)
        # Agent must have sent command ON or AFTER aos_start, and BEFORE aos_end
        # Include a 1s buffer for network/OS lag
        if (sim_aos_start - 1.0) <= agent_cmd_ts <= (sim_aos_end + 1.0):
            score += 20
            feedback.append('Command executed correctly within the 15-second AOS window (+20)')
        else:
            feedback.append('Command timestamp falls outside the simulated AOS window')
    else:
        feedback.append('Skipping timing checks because simulation was not triggered')

    # Pass threshold: 70 points WITH the command strictly verified in the system
    passed = (score >= 70) and cmd_verified

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }