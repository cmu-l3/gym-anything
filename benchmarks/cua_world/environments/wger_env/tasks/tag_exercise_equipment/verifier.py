#!/usr/bin/env python3
"""
Verifier for tag_exercise_equipment task.

Verification Strategy:
1. Programmatic database verification via copy_from_env (Bench added, Barbell kept).
2. Exact count checking to prevent spamming all checkboxes.
3. VLM trajectory verification to ensure agent legitimately navigated the UI.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_exercise_equipment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load the exported verification JSON file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    db_state = result.get('db_state', {})
    found = db_state.get('found', False)
    equipment = db_state.get('equipment', [])
    count = db_state.get('count', 0)

    # 1. Verification of state
    if not found:
        return {"passed": False, "score": 0, "feedback": "Target exercise not found in database. It may have been wrongfully deleted."}

    bench_linked = 'Bench' in equipment
    barbell_linked = 'Barbell' in equipment
    strict_count = (count == 2)

    if bench_linked:
        score += 40
        feedback_parts.append("✅ Bench equipment successfully added")
    else:
        feedback_parts.append("❌ Bench equipment missing")

    if barbell_linked:
        score += 20
        feedback_parts.append("✅ Barbell equipment preserved")
    else:
        feedback_parts.append("❌ Barbell equipment was wrongfully removed")

    if strict_count:
        score += 20
        feedback_parts.append("✅ Strict count met (Exactly 2 items)")
    else:
        feedback_parts.append(f"❌ Strict count failed (Expected exactly 2, found {count})")

    # 2. VLM Trajectory Verification
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are evaluating an AI agent's performance in a fitness management web application.
TASK: Edit the exercise 'Barbell Hip Thrust (Sports Science)' to add the 'Bench' equipment dependency.

Review these trajectory screenshots of the agent's workflow. Determine the following:
1. Did the agent navigate to the exercise editing screen for 'Barbell Hip Thrust'?
2. Did the agent interact with the UI's equipment selection (e.g. checkboxes or dropdowns) to add 'Bench'?

Respond in JSON ONLY:
{
  "navigated_to_edit": true/false,
  "interacted_with_equipment": true/false
}"""
                vlm_res = query_vlm(prompt=prompt, images=images)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('navigated_to_edit') and parsed.get('interacted_with_equipment'):
                    score += 20
                    feedback_parts.append("✅ VLM verified proper UI workflow")
                else:
                    feedback_parts.append("❌ VLM could not verify legitimate UI interaction (Anti-gaming check)")
        except Exception as e:
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)}")
    else:
        feedback_parts.append("⚠️ VLM not available for UI verification")

    # Calculate final status
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }