#!/usr/bin/env python3
"""
Verifier for create_workflow_rule task.
Uses multi-criteria evaluation checking the database state exported as JSON,
combined with VLM trajectory verification to ensure robust anti-gaming.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_workflow_rule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}
        
    metadata = task_info.get('metadata', {})
    expected_summary = metadata.get('expected_summary', 'Auto-Update Next Step on Closed Won')
    
    # 1. Read exported result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/workflow_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 2. Gate Check: Was a new workflow actually created?
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    wf_found = result.get('wf_found', False)
    
    if not wf_found or current_count <= initial_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed: No new workflow created (Initial: {initial_count}, Current: {current_count})"
        }
        
    score += 20
    feedback_parts.append("New workflow created (+20)")
    
    # 3. Verify Workflow Meta (Name & Trigger & Status)
    summary = result.get('summary', '')
    if expected_summary.lower() in summary.lower():
        score += 10
        feedback_parts.append("Summary matched (+10)")
    else:
        feedback_parts.append(f"Summary mismatch (Expected: {expected_summary})")
        
    # execution_condition=3 (Every time saved) or 6 (in newer Vtiger variants)
    exec_cond = str(result.get('exec_condition', ''))
    if exec_cond in ['3', '6']:
        score += 10
        feedback_parts.append("Trigger type correct (+10)")
    else:
        feedback_parts.append(f"Trigger type incorrect (Got: {exec_cond})")
        
    status = str(result.get('status', ''))
    if status == '1' or not status:  # 1 or empty typically denotes active in Vtiger DB
        score += 5
        feedback_parts.append("Workflow is active (+5)")
        
    # 4. Verify Workflow Condition JSON
    test_json_str = result.get('test', '')
    if 'sales_stage' in test_json_str.lower() and 'Closed Won' in test_json_str:
        score += 15
        feedback_parts.append("Condition configured correctly (+15)")
    else:
        feedback_parts.append("Condition missing or incorrect")
        
    # 5. Verify Field Update Task
    task_data = result.get('task_data', '')
    task_summary = result.get('task_summary', '')
    
    if task_data and ('UpdateFields' in task_data or 'nextstep' in task_data):
        score += 10
        feedback_parts.append("Update Fields task exists (+10)")
        
        # Verify specific update values inside serialized task data
        if 'nextstep' in task_data.lower() and 'Generate Invoice' in task_data:
            score += 15
            feedback_parts.append("Task updates Next Step correctly (+15)")
        else:
            feedback_parts.append("Task does not set Next Step to Generate Invoice")
    else:
        feedback_parts.append("Update Fields task missing")

    # 6. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = (
            "You are verifying a CRM agent trajectory. The agent was asked to create a 'Workflow' rule "
            "in Vtiger CRM's Settings. Did the agent navigate to CRM Settings -> Automation -> Workflows, "
            "and configure a workflow rule with an Update Fields action? "
            "Reply with YES or NO, followed by a brief reason."
        )
        
        try:
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                vlm_text = vlm_response.get("text", "").strip().upper()
                if "YES" in vlm_text[:15]:
                    vlm_score = 15
                    feedback_parts.append("VLM confirmed trajectory (+15)")
                else:
                    feedback_parts.append("VLM did not confirm trajectory")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM error")
            
    score += vlm_score

    # Threshold: Must get at least 65 points to pass (ensures core DB traits were hit)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }