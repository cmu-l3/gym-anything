#!/usr/bin/env python3
"""
Verifier for strategic_taskforce_time_configuration task.

Criteria & Scoring (100 points total):
  1. Client "Executive Strategy Board" created & active (15 pts)
  2. Project "AI Enterprise Integration" created & linked to correct client (25 pts)
     (Partial 10 pts if created but linked to wrong/no client)
  3. Task "Vendor Assessment" created & linked (10 pts)
  4. Task "Security Risk Analysis" created & linked (10 pts)
  5. Task "Pilot Implementation" created & linked (10 pts)
  6. Resource EMP006 (Jessica Liu) allocated (10 pts)
  7. Resource EMP012 (Jennifer Martinez) allocated (10 pts)
  8. Resource EMP015 (Kevin Robinson) allocated (10 pts)

Anti-Gaming Check:
  VLM verifies via trajectory frames that the agent navigated the Sentrifugo Time UI.
  If trajectory shows zero Sentrifugo interaction, the task is failed.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these trajectory screenshots from an agent attempting a task in a web browser.
The task involves configuring the "Time" module in the Sentrifugo HRMS (specifically creating a Client, Project, Tasks, and allocating Resources).

Did the agent interact with the Sentrifugo web interface and navigate through the Time, Clients, or Projects modules at any point during this workflow? 
(We are checking if the agent actually used the UI rather than bypassing it).

Respond strictly in JSON format:
{
    "used_ui": true/false,
    "reasoning": "brief explanation of what UI elements are visible"
}"""


def verify_strategic_taskforce_time_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tasks = metadata.get('expected_tasks', ["Vendor Assessment", "Security Risk Analysis", "Pilot Implementation"])
    expected_resources = metadata.get('expected_resources', ["EMP006", "EMP012", "EMP015"])
    pass_threshold = metadata.get('pass_threshold', 70)

    # 1. Read exported DB state
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    client_id = result.get('client_id', '')
    project_id = result.get('project_id', '')
    project_client_id = result.get('project_client_id', '')
    actual_tasks = result.get('tasks', [])
    actual_resources = result.get('resources', [])

    score = 0
    feedback_parts = []

    # Criterion 1: Client
    if client_id:
        score += 15
        feedback_parts.append("Client 'Executive Strategy Board' created (15/15)")
    else:
        feedback_parts.append("Client 'Executive Strategy Board' missing (0/15)")

    # Criterion 2: Project
    if project_id:
        if client_id and project_client_id == client_id:
            score += 25
            feedback_parts.append("Project 'AI Enterprise Integration' created & linked to client (25/25)")
        else:
            score += 10
            feedback_parts.append("Project created but not linked to correct client (10/25)")
    else:
        feedback_parts.append("Project 'AI Enterprise Integration' missing (0/25)")

    # Criterion 3-5: Tasks
    for t in expected_tasks:
        if any(t.lower() == actual.lower() for actual in actual_tasks):
            score += 10
            feedback_parts.append(f"Task '{t}' created & linked (10/10)")
        else:
            feedback_parts.append(f"Task '{t}' missing (0/10)")

    # Criterion 6-8: Resources
    for r in expected_resources:
        if any(r.upper() == actual.upper() for actual in actual_resources):
            score += 10
            feedback_parts.append(f"Resource '{r}' allocated (10/10)")
        else:
            feedback_parts.append(f"Resource '{r}' missing (0/10)")

    # Anti-Gaming: VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    used_ui = True
    vlm_reasoning = "VLM not available, assuming UI was used."
    
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_resp = query_vlm(images=images, prompt=build_vlm_prompt())
                parsed = vlm_resp.get("parsed", {})
                if "used_ui" in parsed:
                    used_ui = parsed["used_ui"]
                    vlm_reasoning = parsed.get("reasoning", "")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed, proceeding without it: {e}")

    if not used_ui:
        score = 0
        feedback_parts.insert(0, f"FAIL: VLM detected no Sentrifugo UI interaction ({vlm_reasoning})")

    passed = (score >= pass_threshold) and used_ui

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }