#!/usr/bin/env python3
"""
Verifier for compare_cancer_drug_interactions task.

Verifies that the agent:
1. Navigated to Tamoxifen and checked Paroxetine interaction (Red).
2. Navigated to Letrozole and checked Paroxetine interaction (Green).
3. Performed these actions sequentially (indicating comparison).

Uses VLM trajectory analysis.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List

# Assuming gym_anything.vlm provides these utilities
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing if library not present
    def sample_trajectory_frames(traj, n=5):
        return [s['screenshot'] for s in traj[-n:]] if traj else []
    
    def query_vlm(prompt, images):
        return {"success": False, "error": "VLM library not found"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
The agent was asked to COMPARE the interaction of 'Paroxetine' with two cancer drugs: 'Tamoxifen' and 'Letrozole'.

Review the sequence of screenshots provided (chronological order) and determine:

1. TAMOXIFEN_CHECK: Did the agent select 'Tamoxifen' and view its co-medications?
2. TAMOXIFEN_RESULT: Did the agent see the 'Paroxetine' interaction for Tamoxifen? Was the traffic light color RED (or Orange/Severe)?
3. LETROZOLE_CHECK: Did the agent select 'Letrozole' and view its co-medications?
4. LETROZOLE_RESULT: Did the agent see the 'Paroxetine' interaction for Letrozole? Was the traffic light color GREEN (or safe)?
5. COMPARISON_WORKFLOW: Did the agent navigate BACK from one drug and into the other (showing a comparative workflow)?

Respond in JSON format:
{
    "tamoxifen_viewed": true/false,
    "tamoxifen_paroxetine_color_seen": "red" | "green" | "none" | "other",
    "letrozole_viewed": true/false,
    "letrozole_paroxetine_color_seen": "green" | "red" | "none" | "other",
    "workflow_comparison_observed": true/false,
    "confidence": "high" | "medium" | "low",
    "reasoning": "your reasoning here"
}
"""

def verify_compare_interactions(traj, env_info, task_info):
    """
    Verify the comparison task using VLM on trajectory frames.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve basic task execution data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check anti-gaming timestamps
    task_start = result_data.get('task_start', 0)
    task_end = result_data.get('task_end', 0)
    duration = task_end - task_start
    
    if duration < 5:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Task completed too quickly ({duration}s). Impossible to perform manual comparison."
        }

    # 2. VLM Trajectory Analysis
    # We sample frames to capture the workflow. 
    # Since this is a multi-step navigation, we need enough frames to see both branches.
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available for verification"}

    vlm_response = query_vlm(
        prompt=TRAJECTORY_PROMPT,
        images=frames
    )

    if not vlm_response.get("success"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"VLM verification failed: {vlm_response.get('error')}"
        }

    analysis = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {analysis}")

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Tamoxifen Interaction Checked (35 pts)
    tamox_viewed = analysis.get("tamoxifen_viewed", False)
    tamox_color = analysis.get("tamoxifen_paroxetine_color_seen", "none").lower()
    
    if tamox_viewed:
        score += 15
        if "red" in tamox_color or "orange" in tamox_color or "severe" in tamox_color:
            score += 20
            feedback_parts.append("Tamoxifen+Paroxetine (Red) verified.")
        else:
            feedback_parts.append(f"Tamoxifen viewed but color unclear ({tamox_color}).")
    else:
        feedback_parts.append("Tamoxifen not viewed.")

    # Criterion 2: Letrozole Interaction Checked (35 pts)
    letro_viewed = analysis.get("letrozole_viewed", False)
    letro_color = analysis.get("letrozole_paroxetine_color_seen", "none").lower()
    
    if letro_viewed:
        score += 15
        if "green" in letro_color or "safe" in letro_color:
            score += 20
            feedback_parts.append("Letrozole+Paroxetine (Green) verified.")
        else:
            feedback_parts.append(f"Letrozole viewed but color unclear ({letro_color}).")
    else:
        feedback_parts.append("Letrozole not viewed.")

    # Criterion 3: Workflow/Navigation (20 pts)
    # The agent must have navigated between screens to compare
    comparison_observed = analysis.get("workflow_comparison_observed", False)
    if comparison_observed:
        score += 20
        feedback_parts.append("Comparative workflow observed.")
    elif tamox_viewed and letro_viewed:
        # Implicit comparison if both were viewed, even if VLM didn't explicitly flag "workflow"
        score += 15 
        feedback_parts.append("Both drugs viewed.")

    # Criterion 4: App was running at end (10 pts)
    if result_data.get("app_was_running", False):
        score += 10
    
    # Pass logic
    # Must have viewed BOTH drugs to pass the "Comparison" task
    passed = (score >= 60) and tamox_viewed and letro_viewed

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }