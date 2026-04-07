#!/usr/bin/env python3
"""
Verifier for create_custom_kpi_dashboard task.

Verifies:
1. Dashboard tab "Sales KPIs" exists in database.
2. The tab contains at least 3 widgets.
3. Checks anti-gaming (dashboard count increased during task).
4. Uses VLM with trajectory frames to verify real UI interaction occurred.
"""

import os
import json
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are auditing a computer agent's performance. The agent was tasked with creating a new dashboard tab named "Sales KPIs" and adding widgets to it in Vtiger CRM.

Look at these screenshots from the agent's session.
Determine:
1. Is the agent interacting with a CRM interface (specifically dashboards/analytics)?
2. Is there evidence of interacting with a dashboard tab or an "Add Widget" interface?

Respond ONLY in JSON format:
{
    "is_crm_interface": true/false,
    "interacted_with_dashboard": true/false,
    "reasoning": "brief explanation"
}"""

def verify_create_custom_kpi_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_dashboard_name', 'Sales KPIs')
    min_expected_widgets = metadata.get('min_expected_widgets', 3)

    feedback_parts = []
    score = 0
    
    # 1. Retrieve the exported JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/custom_dashboard_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract state variables
    dashboard_found = result.get('dashboard_found', False)
    dashboard_name = result.get('dashboard_name', '')
    widgets_on_dashboard = int(result.get('widgets_on_dashboard', 0))
    initial_dash_count = int(result.get('initial_dashboard_count', 0))
    current_dash_count = int(result.get('current_dashboard_count', 0))
    
    logger.info(f"Dashboard found: {dashboard_found}, Widgets: {widgets_on_dashboard}")
    
    # 3. Database Verification Logic
    if not dashboard_found or dashboard_name != expected_name:
        feedback_parts.append(f"Dashboard tab '{expected_name}' not found.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }
        
    # Anti-gaming: ensure dashboard was created during the session
    if current_dash_count <= initial_dash_count:
        feedback_parts.append("FAIL: Dashboard count did not increase (Anti-gaming check failed).")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Tab exists and was created (40 points)
    score += 40
    feedback_parts.append("Dashboard tab 'Sales KPIs' successfully created")

    # Widget Verification (20 points per widget up to 3)
    capped_widgets = min(widgets_on_dashboard, min_expected_widgets)
    score += (capped_widgets * 20)
    
    if widgets_on_dashboard >= min_expected_widgets:
        feedback_parts.append(f"Successfully added {widgets_on_dashboard} widgets")
    elif widgets_on_dashboard > 0:
        feedback_parts.append(f"Partial success: Added {widgets_on_dashboard} widgets (expected {min_expected_widgets})")
    else:
        feedback_parts.append("No widgets added to the new dashboard")

    # 4. VLM Verification (Trajectory Anti-Gaming)
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            try:
                vlm_result = query_vlm(images=images, prompt=VERIFICATION_PROMPT)
                parsed = vlm_result.get("parsed", {})
                
                is_crm = parsed.get("is_crm_interface", False)
                interacted = parsed.get("interacted_with_dashboard", False)
                
                if is_crm and interacted:
                    vlm_passed = True
                    feedback_parts.append("VLM verified UI trajectory")
                else:
                    feedback_parts.append("VLM warning: Trajectory does not clearly show dashboard interaction")
                    # If VLM strongly doubts the interaction, penalize score to prevent API-only completion
                    score = min(score, 50) 
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                feedback_parts.append("VLM check encountered an error")
    else:
        feedback_parts.append("VLM function unavailable, relying on DB state")

    # 5. Final Determination
    key_criteria_met = dashboard_found and (widgets_on_dashboard >= 1)
    passed = score >= 80 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "widgets_added": widgets_on_dashboard,
            "vlm_verified": vlm_passed
        }
    }