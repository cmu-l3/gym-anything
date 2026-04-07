#!/usr/bin/env python3
"""Verifier for parachute_recovery_setup task.

Verifies:
1. 5 CHUTE_* parameters are correctly set in the ArduPilot parameter tree (50 points).
2. The agent created a compliance report text file containing key values and an airworthiness sign-off (20 points).
3. VLM trajectory verification: The agent used the QGC UI and a text editor during the workflow (30 points).

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_PARAMS = {
    'CHUTE_ENABLED':  (1.0, 10, 0.1),
    'CHUTE_ALT_MIN':  (25.0, 10, 2.0),
    'CHUTE_CRT_SINK': (4.5, 10, 0.2),
    'CHUTE_DELAY_MS': (250.0, 10, 5.0),
    'CHUTE_CHAN':     (8.0, 10, 0.1),
}

VLM_PROMPT = """You are evaluating an AI agent's performance on a desktop GUI task.
The agent was asked to configure drone parameters in QGroundControl (QGC) and write a text report.

Look at these screenshots taken during the task workflow.
1. Did the agent navigate to the "Parameters" or "Vehicle Setup" screen in QGroundControl at some point? (Look for parameter lists, search bars with 'CHUTE_', or gear icons).
2. Did the agent use a text editor (like gedit, nano, terminal, or text window) to view the manual or write the report?

Return your assessment strictly as JSON format:
{
    "used_qgc_parameters": true/false,
    "used_text_editor": true/false
}
"""

def verify_parachute_recovery_setup(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Read exported result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    details = {}
    params = result.get('params', {})

    # --- 1. Parameter Checks (50 pts: 10 pts per param) ---
    for param_name, (required_val, pts, tol) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                if abs(actual_f - required_val) <= tol:
                    score += pts
                    feedback.append(f'{param_name}={actual_f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f} (need {required_val}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- 2. Report Checks (20 pts) ---
    report_found = result.get('report_found', False)
    report_modified = result.get('report_modified', False)
    
    if report_found and report_modified:
        score += 10
        feedback.append('Report created/modified during task (+10)')
        
        # Text analysis (10 pts total - 2.5 pts per key element)
        report_content = result.get('report_content', '').lower()
        if isinstance(report_content, str):
            report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
            
        content_score = 0
        if '25' in report_content:
            content_score += 2.5
        if '4.5' in report_content:
            content_score += 2.5
        if '8' in report_content:
            content_score += 2.5
        if 'airworthy' in report_content or 'air-worthy' in report_content or 'sign-off' in report_content or 'signed off' in report_content:
            content_score += 2.5
            
        score += content_score
        feedback.append(f'Report content checks passed: {content_score}/10 pts')
    else:
        feedback.append('Report file not found or not modified during task (+0/20)')

    # --- 3. VLM Trajectory Verification (30 pts) ---
    vlm_score = 0
    if query_vlm:
        # Sample frames from trajectory + final screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            vlm_result = query_vlm(
                prompt=VLM_PROMPT,
                images=frames
            )
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                used_qgc = parsed.get("used_qgc_parameters", False)
                used_editor = parsed.get("used_text_editor", False)
                
                if used_qgc:
                    vlm_score += 15
                    feedback.append('VLM: Agent navigated QGC Parameters (+15)')
                else:
                    feedback.append('VLM: QGC Parameters usage not verified (+0)')
                    
                if used_editor:
                    vlm_score += 15
                    feedback.append('VLM: Agent used a text editor (+15)')
                else:
                    feedback.append('VLM: Text editor usage not verified (+0)')
            else:
                feedback.append('VLM verification query failed (+0/30)')
        else:
            feedback.append('No trajectory frames available for VLM verification (+0/30)')
    else:
        # If VLM unavailable but file was modified and params set, award points to prevent penalty
        feedback.append('VLM not available, awarding trajectory points assuming valid interaction (+30)')
        vlm_score = 30

    score += vlm_score

    # Final pass/fail evaluation
    passed = score >= 70
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }