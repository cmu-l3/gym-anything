#!/usr/bin/env python3
"""
Verifier for configure_omnichannel_livechat task.

Verifies:
1. Omnichannel/LiveChat system is enabled
2. agent.user is registered as a LiveChat agent
3. 'Technical Support' department exists and is enabled
4. agent.user is assigned to the department
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_omnichannel_livechat(traj, env_info, task_info):
    """
    Verify Omnichannel LiveChat configuration.
    Uses result JSON exported from container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract results
    livechat_enabled = result.get('livechat_enabled', False)
    agent_registered = result.get('agent_registered', False)
    dept_exists = result.get('department_exists', False)
    dept_enabled = result.get('department_enabled', False)
    agent_assigned = result.get('agent_assigned_to_dept', False)

    # Criterion 1: Omnichannel enabled (25 pts)
    if livechat_enabled:
        score += 25
        feedback_parts.append("Omnichannel is enabled")
    else:
        feedback_parts.append("Omnichannel is NOT enabled")

    # Criterion 2: Agent registered (25 pts)
    if agent_registered:
        score += 25
        feedback_parts.append("Agent 'agent.user' is registered")
    else:
        feedback_parts.append("Agent 'agent.user' is NOT registered")

    # Criterion 3: Department exists & enabled (25 pts)
    if dept_exists:
        if dept_enabled:
            score += 25
            feedback_parts.append("Department 'Technical Support' exists and is enabled")
        else:
            score += 15
            feedback_parts.append("Department exists but is DISABLED")
    else:
        feedback_parts.append("Department 'Technical Support' not found")

    # Criterion 4: Agent assigned (25 pts)
    if agent_assigned:
        score += 25
        feedback_parts.append("Agent assigned to department")
    elif dept_exists:
        feedback_parts.append("Agent NOT assigned to department")

    # Anti-gaming check: Task duration
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    duration = task_end - task_start
    if duration < 5:
        score = 0
        feedback_parts.append("Task completed too quickly (likely pre-configured or gaming)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }