#!/usr/bin/env python3
"""
Verifier for telemarketer_log_call_and_task task.

Evaluates:
1. Lead creation and attributes
2. Event (Call) creation, attributes, and linkage to Lead
3. Task (To Do) creation, attributes, and linkage to Lead
4. Anti-gaming timestamps
5. VLM workflow verification via trajectory
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance inside Vtiger CRM.
The agent was asked to create a Lead, add a completed Call Event, and schedule a future Task.

Please review these screenshots from the agent's workflow and determine:
1. Did the agent navigate through the Vtiger CRM interface?
2. Is there visual evidence of the agent interacting with forms to create the Lead, Event, or Task?

Reply with JSON in this format:
{
    "crm_interaction_visible": true/false,
    "forms_filled": true/false,
    "reasoning": "Brief explanation"
}
"""

def verify_telemarketer_log_call_and_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Extract expected metadata
    metadata = task_info.get('metadata', {})
    expected_lead_source = metadata.get('expected_lead_source', 'Cold Call')
    expected_lead_status = metadata.get('expected_lead_status', 'Contact in Future')
    expected_industry = metadata.get('expected_industry', 'Transportation')
    expected_event_status = metadata.get('expected_event_status', 'Held')
    expected_event_date = metadata.get('expected_event_date', '2026-03-08')
    expected_task_status = metadata.get('expected_task_status', 'Not Started')
    expected_task_priority = metadata.get('expected_task_priority', 'High')
    expected_task_date = metadata.get('expected_task_date', '2026-03-15')

    # Read exported JSON results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/telemarketer_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start_time = results.get('task_start_time', 0)

    # 1. Lead Verification (Max 25 pts)
    lead = results.get('lead', {})
    lead_found = lead.get('found', False)
    if lead_found:
        if lead.get('created_time', 0) >= task_start_time:
            score += 15
            feedback_parts.append("Lead created during task")
            
            # Lead Attributes
            attr_score = 0
            if lead.get('source') == expected_lead_source: attr_score += 3
            if lead.get('status') == expected_lead_status: attr_score += 4
            if lead.get('industry') == expected_industry: attr_score += 3
            score += attr_score
            if attr_score == 10:
                feedback_parts.append("Lead attributes perfectly match")
        else:
            feedback_parts.append("Lead found but existed before task (Anti-Gaming failed)")
    else:
        feedback_parts.append("Lead not found")

    # 2. Event/Call Verification (Max 25 pts)
    event = results.get('event', {})
    event_found = event.get('found', False)
    if event_found and event.get('linked_to_lead', False):
        if event.get('created_time', 0) >= task_start_time:
            score += 15
            feedback_parts.append("Call event created and linked")
            
            # Event Attributes
            attr_score = 0
            if event.get('status') == expected_event_status: attr_score += 5
            if event.get('date_start') == expected_event_date: attr_score += 5
            score += attr_score
            if attr_score == 10:
                feedback_parts.append("Event attributes correctly configured")
        else:
            feedback_parts.append("Event found but created prior to task")
    else:
        feedback_parts.append("Call event missing or not linked to Lead")

    # 3. Task/To-Do Verification (Max 25 pts)
    task = results.get('task', {})
    task_found = task.get('found', False)
    if task_found and task.get('linked_to_lead', False):
        if task.get('created_time', 0) >= task_start_time:
            score += 15
            feedback_parts.append("Follow-up task created and linked")
            
            # Task Attributes
            attr_score = 0
            if task.get('status') == expected_task_status: attr_score += 4
            if task.get('priority') == expected_task_priority: attr_score += 3
            if task.get('due_date') == expected_task_date: attr_score += 3
            score += attr_score
            if attr_score == 10:
                feedback_parts.append("Task attributes correctly configured")
        else:
            feedback_parts.append("Task found but created prior to task")
    else:
        feedback_parts.append("Follow-up task missing or not linked to Lead")

    # 4. VLM Verification of workflow (Max 25 pts)
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if frames and final_img:
            vlm_res = query_vlm(
                images=frames + [final_img],
                prompt=VLM_PROMPT
            )
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('crm_interaction_visible'):
                    vlm_points += 10
                    feedback_parts.append("VLM confirmed CRM interaction")
                if parsed.get('forms_filled'):
                    vlm_points += 15
                    feedback_parts.append("VLM confirmed form usage")
                score += vlm_points
            else:
                feedback_parts.append("VLM evaluation failed to parse")
    else:
        feedback_parts.append("VLM functionality unavailable")

    # Final Evaluation
    passed = score >= 70 and lead_found and (event_found or task_found)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }