#!/usr/bin/env python3
"""
Verifier for program_powerlifting_peaking_block.
Evaluates nested data creation and form overriding for set/rep structures.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_powerlifting_block(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_configs = metadata.get('expected_configs', [])
    
    # Extract the exported JSON state
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    routine_found = result.get('routine_found', False)
    days_count = result.get('days_count', 0)
    agent_configs = result.get('configs', [])
    
    # 1. Check if routine was created (10 pts)
    if routine_found:
        score += 10
        feedback_parts.append("✅ Routine 'Smolov Jr. Bench' created")
    else:
        feedback_parts.append("❌ Routine not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Check for exact day counts (10 pts)
    if days_count == 4:
        score += 10
        feedback_parts.append(f"✅ Exactly 4 days created")
    elif days_count > 0:
        score += 5
        feedback_parts.append(f"⚠️ {days_count} days created (expected 4)")
    else:
        feedback_parts.append("❌ No days created in routine")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check specific Sets/Reps configuration mapping (12 pts each, up to 48 pts)
    matched_configs_count = 0
    valid_exercise_selected = False
    
    for expected in expected_configs:
        e_sets = int(expected["sets"])
        e_reps = str(expected["reps"]).strip()
        
        match_found = False
        for ac in agent_configs:
            a_sets = int(ac.get("sets", 0))
            a_reps = str(ac.get("reps", "")).strip()
            
            if a_sets == e_sets and a_reps == e_reps:
                match_found = True
                
                # Verify exercise appropriateness ("bench" or "press" in the name)
                ex_name = ac.get("exercise", "").lower()
                if "bench" in ex_name or "press" in ex_name:
                    valid_exercise_selected = True
                break
                
        if match_found:
            score += 12
            matched_configs_count += 1
            feedback_parts.append(f"✅ Volume scheme {e_sets}x{e_reps} configured")
        else:
            feedback_parts.append(f"❌ Missing volume scheme {e_sets}x{e_reps}")

    # 4. Check exercise assignments (12 pts)
    if valid_exercise_selected and matched_configs_count > 0:
        score += 12
        feedback_parts.append("✅ Appropriate Bench Press exercise selected")
    elif matched_configs_count > 0:
        feedback_parts.append("❌ Incorrect exercise assigned to the volume scheme")

    # 5. Anti-gaming / UI Interaction via VLM (20 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """Look at these screenshots of a computer agent using the wger fitness tracker.
            Did the agent use the web UI to interact with workout routines, add training days, and input numbers for sets/reps?
            Reply strictly in JSON format: {"used_ui": true/false}"""
            
            try:
                vlm_resp = query_vlm(prompt=prompt, images=frames)
                if vlm_resp.get("success") and vlm_resp.get("parsed", {}).get("used_ui"):
                    score += 20
                    feedback_parts.append("✅ VLM verified natural UI interaction")
                else:
                    feedback_parts.append("❌ VLM could not verify UI interaction")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("⚠️ VLM evaluation error")

    # Evaluator Threshold 
    passed = score >= 70 and routine_found and (matched_configs_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }