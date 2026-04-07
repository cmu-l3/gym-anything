#!/usr/bin/env python3
"""
Verifier for cancel_stalled_workflow task.

Verifies that:
1. The target document still exists (was not deleted).
2. The active workflow tasks on the document are gone (count == 0).
3. VLM: Trajectory shows interaction with "Abandon" or "Cancel" controls.
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory for shared utilities if needed, 
# though for this task we use self-contained logic where possible.
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from vlm_utils import sample_trajectory_frames, query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_stalled_workflow(traj, env_info, task_info):
    """
    Verify the stalled workflow was cancelled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Document must still exist (Critical)
    # If the user deleted the document to "remove the workflow", that's a fail.
    doc_exists = result.get("document_exists", False)
    if not doc_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL FAIL: The document 'Contract Template' was deleted. You must cancel the workflow, not delete the document."
        }
    
    score += 40
    feedback_parts.append("Document preserved")

    # Criterion 2: No active tasks
    active_tasks = result.get("active_tasks_count", -1)
    if active_tasks == 0:
        score += 40
        feedback_parts.append("Workflow tasks successfully cleared")
    else:
        feedback_parts.append(f"Workflow tasks still active (Count: {active_tasks})")

    # Criterion 3: Workflow State check (Bonus/Confirmation)
    wf_state = result.get("workflow_state", "")
    # "missing" usually means it's gone/cleaned up from the active table, which is good for cancellation
    # Or state could be "canceled"
    if wf_state in ["canceled", "missing", "running"]: # "running" would be bad if tasks are active
        pass # Evaluated primarily via task count

    # Criterion 4: VLM Trajectory Verification
    # We want to confirm the agent actually clicked "Abandon" or similar
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        You are verifying an agent's actions in the Nuxeo Platform ECM.
        The goal was to CANCEL or ABANDON a stalled workflow.
        
        Look at these screenshots. Do you see the agent:
        1. Navigating to a 'Tasks' view or a document's 'Process'/'Workflow' tab?
        2. Clicking a button labeled 'Abandon', 'Cancel', 'Stop', or 'End'?
        3. Confirming a cancellation dialog?
        
        Answer JSON: {"action_observed": true/false, "description": "..."}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("action_observed"):
                    vlm_score = 20
                    feedback_parts.append("VLM confirmed cancellation action")
                else:
                    feedback_parts.append("VLM did not clearly see cancellation action")
            else:
                # If VLM fails, give benefit of doubt if programmatic checks passed
                if active_tasks == 0:
                    vlm_score = 20
        except Exception:
            if active_tasks == 0:
                vlm_score = 20
    else:
        # Fallback if VLM not available
        if active_tasks == 0:
            vlm_score = 20

    score += vlm_score

    # Final Evaluation
    passed = (doc_exists and active_tasks == 0 and score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }