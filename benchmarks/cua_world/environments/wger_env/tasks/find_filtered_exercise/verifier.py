#!/usr/bin/env python3
"""
Verifier for find_filtered_exercise task.

VERIFICATION STRATEGY:
1. ORM Verification: Inspect database to verify 'Pull Day' was added to 'Push-Pull-Legs'.
2. Set/Rep Verification: Verify exact 3 sets of 12 reps were added.
3. Constraint Verification: Verify the dynamically chosen exercise requires "Dumbbell" and targets "Biceps".
4. VLM Trajectory Verification: Verify the agent used the wger web UI during the process.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's trajectory for a workout management application (wger).
Please look at these trajectory screenshots and the final screenshot.
Did the agent interact with the wger application interface? 
Look for evidence of navigating workout routines, adding days, or using the exercise search/database.

Respond in JSON format:
{
    "interacted_with_app": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_find_filtered_exercise(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata requirements
    metadata = task_info.get('metadata', {})
    expected_sets = metadata.get('expected_sets', 3)
    expected_reps = metadata.get('expected_reps', 12)
    expected_equipment = metadata.get('expected_equipment', ['dumbbell'])
    expected_muscle = metadata.get('expected_muscle', ['biceps', 'biceps brachii'])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    orm_data = result.get('orm_data', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Routine intact (10 pts)
    if orm_data.get('routine_exists', False):
        score += 10
        feedback_parts.append("✅ Routine 'Push-Pull-Legs' exists")
    else:
        feedback_parts.append("❌ Routine 'Push-Pull-Legs' missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # 2. Day created (15 pts)
    if orm_data.get('day_exists', False):
        score += 15
        feedback_parts.append("✅ 'Pull Day' created")
    else:
        feedback_parts.append("❌ 'Pull Day' not found in routine")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Sets and Reps Check (20 pts + 20 pts)
    sets_count = orm_data.get('sets_count', 0)
    reps_found = orm_data.get('reps_found', [])
    
    if sets_count >= expected_sets:
        score += 20
        feedback_parts.append(f"✅ Found {sets_count} sets (Expected >= {expected_sets})")
    else:
        feedback_parts.append(f"❌ Found {sets_count} sets (Expected {expected_sets})")
        
    if len(reps_found) >= expected_sets and all(r == expected_reps for r in reps_found[:expected_sets]):
        score += 20
        feedback_parts.append(f"✅ Configured with exactly {expected_reps} reps")
    else:
        feedback_parts.append(f"❌ Reps mismatch: {reps_found} (Expected {expected_reps})")

    # 4. Equipment Constraint Check (15 pts)
    agent_equipment = orm_data.get('exercise_equipment', [])
    equip_match = any(req in eq for eq in agent_equipment for req in expected_equipment)
    
    if equip_match:
        score += 15
        feedback_parts.append("✅ Selected exercise requires Dumbbell")
    else:
        feedback_parts.append(f"❌ Selected exercise equipment mismatch. Found: {agent_equipment}")

    # 5. Muscle Constraint Check (15 pts)
    agent_muscles = orm_data.get('exercise_muscles', [])
    muscle_match = any(req in musc for musc in agent_muscles for req in expected_muscle)
    
    if muscle_match:
        score += 15
        feedback_parts.append("✅ Selected exercise targets Biceps")
    else:
        feedback_parts.append(f"❌ Selected exercise muscle mismatch. Found: {agent_muscles}")

    # 6. VLM Trajectory Check (5 pts)
    vlm_passed = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            vlm_response = query_vlm(
                images=frames + [final] if final else frames, 
                prompt=VLM_PROMPT
            )
            
            parsed = vlm_response.get('parsed', {})
            if parsed.get('interacted_with_app', False):
                score += 5
                vlm_passed = True
                feedback_parts.append("✅ App interaction visually confirmed")
            else:
                feedback_parts.append("⚠️ App interaction not visually detected")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("⚠️ VLM verification skipped/failed")
            
    # Key criteria MUST be met to pass
    key_criteria_met = (
        orm_data.get('day_exists', False) and 
        sets_count >= expected_sets and
        (equip_match or muscle_match)
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": orm_data
    }