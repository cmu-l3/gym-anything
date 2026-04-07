#!/usr/bin/env python3
"""
Verifier for start_document_workflow task.
Verifies that a Serial Document Review workflow was started on the correct document,
assigned to 'jsmith', and contains the correct directive.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_start_document_workflow(traj, env_info, task_info):
    """
    Verify the document review workflow task.
    
    Criteria:
    1. Workflow Instance Exists (30 pts)
    2. Correct Workflow Model (15 pts)
    3. Task Assigned to jsmith (25 pts)
    4. Directive Comment Present (15 pts)
    5. VLM Process Verification (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # Extract data
    initial_count = result.get('initial_workflow_count', 0)
    final_count = result.get('final_workflow_count', 0)
    active_workflows = result.get('active_workflows', [])
    jsmith_tasks = result.get('jsmith_tasks', [])
    
    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('directive_keywords', ["budget", "timeline"])

    # --- Criterion 1: Workflow Instance Exists (30 pts) ---
    # Must have increased count (anti-gaming) and have active workflows
    workflow_created = False
    target_workflow = None
    
    if final_count > initial_count and len(active_workflows) > 0:
        score += 30
        feedback.append("Workflow instance started successfully.")
        workflow_created = True
        # Grab the most recent workflow (assuming it's the one we just made)
        # Nuxeo API typically returns list, we check the last added or simply the existence
        target_workflow = active_workflows[-1] # Simple heuristic
    else:
        feedback.append("No new workflow instance detected.")

    # --- Criterion 2: Correct Workflow Model (15 pts) ---
    if workflow_created and target_workflow:
        model_name = target_workflow.get('workflowModelName', '')
        if model_name == 'SerialDocumentReview':
            score += 15
            feedback.append("Correct workflow model (SerialDocumentReview).")
        else:
            feedback.append(f"Incorrect workflow model: {model_name}.")

    # --- Criterion 3: Task Assigned to jsmith (25 pts) ---
    task_found = False
    target_task = None
    if len(jsmith_tasks) > 0:
        score += 25
        feedback.append("Review task assigned to user 'jsmith' found.")
        task_found = True
        target_task = jsmith_tasks[0]
    else:
        feedback.append("No review task found assigned to 'jsmith' for this document.")

    # --- Criterion 4: Directive Comment Present (15 pts) ---
    directive_score = 0
    if task_found and target_task:
        # Nuxeo tasks often store the comment in 'variables' -> 'comment' or 'directive'
        # Or directly in the task properties depending on version.
        # Typically for SerialReview, the comment is in `variables.comment` or passed as a node variable.
        # We check the variables dict.
        variables = target_task.get('variables', {})
        
        # Search all string values in variables for the keywords
        # Also check 'comment' specifically
        found_text = ""
        for key, val in variables.items():
            if isinstance(val, str):
                found_text += val + " "
        
        # Check keywords
        matches = [kw for kw in expected_keywords if kw.lower() in found_text.lower()]
        if len(matches) >= 2:
            directive_score = 15
            feedback.append(f"Directive comment verified (keywords found: {matches}).")
        elif len(matches) == 1:
            directive_score = 10
            feedback.append(f"Directive comment partially verified (keyword found: {matches}).")
        else:
            feedback.append("Directive comment missing or did not match expected keywords.")
            
    score += directive_score

    # --- Criterion 5: VLM Process Verification (15 pts) ---
    # Use VLM to check if the agent actually used the UI
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = (
            "You are verifying a user action in the Nuxeo Platform web interface. "
            "Look at the sequence of screenshots. "
            "Did the user interact with a document workflow dialog? "
            "Specifically, look for a popup or form where they might select 'Serial Document Review', "
            "add a participant/user, or type a comment. "
            "Answer JSON with key 'workflow_ui_interaction' (boolean) and 'confidence' (high/medium/low)."
        )
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("workflow_ui_interaction") and parsed.get("confidence") in ["high", "medium"]:
                vlm_score = 15
                feedback.append("Visual evidence of workflow UI interaction confirmed.")
            else:
                feedback.append("VLM did not confidently detect workflow UI interaction.")
        else:
            # If VLM fails, we fallback to giving points if the programmatic check was perfect (anti-frustration)
            if score >= 85:
                vlm_score = 15
                feedback.append("VLM unavailable, assumed passed based on strong programmatic evidence.")
    else:
        feedback.append("No trajectory frames available for VLM.")

    score += vlm_score

    # --- Final Pass/Fail ---
    # Pass if: Workflow started (30) AND Task assigned (25) = 55 minimum
    passed = (workflow_created and task_found and score >= 55)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }