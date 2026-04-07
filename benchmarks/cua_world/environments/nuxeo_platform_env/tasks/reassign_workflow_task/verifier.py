#!/usr/bin/env python3
"""
Verifier for reassign_workflow_task.
Checks if user 'jdoe' has been assigned to the workflow task.
"""

import json
import os
import logging
import tempfile
import sys

# Import VLM utils provided by the framework if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_workflow_task(traj, env_info, task_info):
    """
    Verify that the workflow task was reassigned to jdoe.
    
    Scoring Criteria:
    1. Workflow is still active (10 pts)
    2. jdoe is an actor on the task (35 pts)
    3. jsmith is NOT the sole assignee (15 pts) - implies change occurred
    4. Task is associated with correct document (10 pts)
    5. VLM: Trajectory shows task interface navigation (15 pts)
    6. VLM: Trajectory shows reassignment/delegation dialog (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    api_result = result_data.get('api_result', {})
    if 'error' in api_result:
        return {"passed": False, "score": 0, "feedback": f"API check failed: {api_result['error']}"}

    score = 0
    feedback = []
    
    # ----------------------------------------------------------------
    # Programmatic Verification (70 pts)
    # ----------------------------------------------------------------
    
    # Criterion 1: Workflow Active (10 pts)
    if api_result.get('workflow_active', False):
        score += 10
        feedback.append("Workflow is still active.")
    else:
        feedback.append("Workflow is NOT active (likely cancelled or completed incorrectly).")
        # If workflow is gone, we can't verify assignments
        return {"passed": False, "score": 0, "feedback": "Workflow ended prematurely. Task must be reassigned, not completed or cancelled."}

    # Criterion 2: jdoe found (35 pts)
    jdoe_found = api_result.get('jdoe_found', False)
    if jdoe_found:
        score += 35
        feedback.append("User 'jdoe' is assigned to the task.")
    else:
        feedback.append("User 'jdoe' was NOT found in the task actors list.")

    # Criterion 3: jsmith not sole assignee (15 pts)
    final_actors_list = api_result.get('final_actors', [])
    # Flatten list
    all_current_actors = [actor for sublist in final_actors_list for actor in sublist]
    
    # Check if jsmith is the ONLY one
    is_jsmith_sole = (len(all_current_actors) == 1 and 'jsmith' in all_current_actors)
    
    if not is_jsmith_sole:
        score += 15
        feedback.append("Task assignment was modified (jsmith is not sole actor).")
    else:
        feedback.append("Task assignment unchanged (jsmith is still sole actor).")

    # Criterion 4: Correct Document (10 pts)
    # Implicitly checked by the API query in export_result.sh which queries /id/$DOC_ID/@task
    if api_result.get('doc_id') and api_result.get('workflow_active'):
        score += 10
        feedback.append("Task is associated with correct document.")

    # ----------------------------------------------------------------
    # VLM Verification (30 pts)
    # ----------------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE:
        # Sample frames to find the delegation dialog
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Analyze these screenshots of a user interacting with Nuxeo Platform (a document management system).
        The user goal is to REASSIGN or DELEGATE a workflow task.
        
        Look for:
        1. A list of tasks or a document workflow view.
        2. A "Delegate", "Reassign", or "Add Reviewers" dialog box or popup.
        3. User selection input (searching for "jdoe" or "Jane Doe").
        
        Return JSON:
        {
            "task_view_visible": boolean,
            "reassign_dialog_visible": boolean,
            "user_selection_visible": boolean,
            "confidence": "high|medium|low"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            # Criterion 5: Navigation (15 pts)
            if parsed.get('task_view_visible'):
                vlm_score += 15
                feedback.append("VLM confirmed navigation to task/workflow view.")
            
            # Criterion 6: Action (15 pts)
            if parsed.get('reassign_dialog_visible') or parsed.get('user_selection_visible'):
                vlm_score += 15
                feedback.append("VLM confirmed reassignment dialog usage.")
        else:
            feedback.append("VLM verification skipped (failed to process).")
            # Fallback points if programmatic checks are perfect
            if score >= 60:
                vlm_score = 10 
    else:
        feedback.append("VLM unavailable.")
        # If VLM unavailable but programmatic passed, grant partial credit
        if score >= 60:
            vlm_score = 30
            
    score += vlm_score

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = (score >= 60) and jdoe_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }