#!/usr/bin/env python3
"""
Verifier for add_exercise_aliases task.

This evaluates both the final Database state and the trajectory via VLM.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying an agent's trajectory in a fitness web application (wger).
The agent was asked to search for exercises and add acronyms (like RDL, OHP, BSS) as "aliases".

Look at these trajectory frames. Determine if the agent used the web UI to interact with exercises and add aliases.
Evidence includes:
- Searching in the exercise overview list
- Viewing an exercise details page
- Clicking "Add alias" or typing an alias into a form

Respond with JSON in this format:
{
    "used_ui": true/false,
    "reasoning": "brief explanation of the frames seen"
}
"""

def verify_add_exercise_aliases(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output
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

    db_state = result.get("db_state", {})
    aliases = db_state.get("aliases", {})
    original_names = db_state.get("original_names", {})
    dummies = db_state.get("dummies", [])

    score = 0
    feedback_parts = []
    
    # 1. Alias Mapping (20 pts each)
    alias_checks = [("RDL", 20), ("OHP", 20), ("BSS", 20)]
    all_mapped = True
    
    for a, pts in alias_checks:
        if aliases.get(a) is True:
            score += pts
            feedback_parts.append(f"✅ Alias {a} correctly mapped")
        else:
            all_mapped = False
            feedback_parts.append(f"❌ Alias {a} missing or mapped incorrectly")

    # 2. Original Names Preserved (10 pts)
    originals_ok = True
    for t_name, preserved in original_names.items():
        if not preserved:
            originals_ok = False
            
    if originals_ok:
        score += 10
        feedback_parts.append("✅ Original exercise names preserved")
    else:
        feedback_parts.append("❌ One or more original exercise names were modified")

    # 3. No Dummy Exercises (10 pts)
    if len(dummies) == 0:
        score += 10
        feedback_parts.append("✅ No duplicate/dummy exercises created")
    else:
        feedback_parts.append(f"❌ Dummy exercises created directly: {', '.join(dummies)}")

    # 4. Trajectory Verification via VLM (20 pts)
    ui_used = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_res = query_vlm(images=frames, prompt=VERIFICATION_PROMPT)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_ui', False):
                        ui_used = True
                        score += 20
                        feedback_parts.append("✅ Trajectory shows agent used the web UI correctly")
                    else:
                        feedback_parts.append(f"❌ Trajectory did not show UI usage. Reasoning: {parsed.get('reasoning')}")
                else:
                    feedback_parts.append("⚠️ VLM request failed, omitting trajectory score")
        except Exception as e:
            logger.error(f"VLM Trajectory check failed: {e}")
            feedback_parts.append("⚠️ VLM verification error")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")

    # Determine passing state
    # Must correctly map all aliases AND not break the system (no dummies or modified originals)
    is_safe = originals_ok and (len(dummies) == 0)
    passed = (score >= 70) and all_mapped and is_safe

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }