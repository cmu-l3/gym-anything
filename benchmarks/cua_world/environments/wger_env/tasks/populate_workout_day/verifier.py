#!/usr/bin/env python3
"""
Verifier for the populate_workout_day task.
Checks database extracts for required exercises and configurations, 
and leverages VLM trajectory checking to ensure workflow progression.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an agent successfully configured a workout day in the wger fitness manager.

Examine these trajectory frames. Determine:
1. Did the agent navigate to the "Upper Body Day" and open the exercise search/add interface?
2. Did the agent search for and select exercises (e.g., Bench Press, Row, Press)?
3. Did the agent configure the sets and reps in the UI?

Respond in JSON format:
{
    "navigated_to_day": true/false,
    "searched_exercises": true/false,
    "configured_sets_reps": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_populate_workout_day(traj, env_info, task_info):
    # 1. Access environment copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # 2. Extract JSON result from environment safely
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
            
    db_result = result.get('db_result', {})
    
    if "error" in db_result:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Database error: {db_result['error']}"
        }
        
    exercises = db_result.get('exercises', [])
    exercise_count = db_result.get('exercise_count', 0)
    
    score = 0
    feedback = []
    
    # Base anti-gaming check
    if exercise_count > 0:
        score += 5
        feedback.append(f"Day has {exercise_count} exercises added.")
    else:
        feedback.append("No exercises were added to the day.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
        
    # Initialize trackers
    found_bench, bench_config = False, False
    found_row, row_config = False, False
    found_press, press_config = False, False
    
    # 3. Analyze programmatic database results
    for ex in exercises:
        names = " ".join(ex.get('exercise_names', [])).lower()
        config = ex.get('config', [])
        
        # Helper to handle wger's "4 sets of 8" vs 4 independent "8 rep" entries
        def check_config(target_sets, target_reps):
            if not config: return False
            
            # Pattern A: Single Setting definition (sets=4, reps=8)
            try:
                c = config[0]
                if int(c.get('sets', 0)) == target_sets and int(c.get('reps', 0)) == target_reps:
                    return True
            except:
                pass
                
            # Pattern B: Multiple Setting definitions (len=4, all reps=8)
            try:
                if len(config) == target_sets and all(int(cx.get('reps', 0)) == target_reps for cx in config):
                    return True
            except:
                pass
                
            return False
            
        # Classify and test each exercise
        if "bench" in names and "press" in names:
            found_bench = True
            if check_config(4, 8):
                bench_config = True
        elif "row" in names or "bent over" in names:
            found_row = True
            if check_config(3, 10):
                row_config = True
        elif "press" in names or "military" in names or "shoulder" in names or "overhead" in names:
            if "bench" not in names:  # exclude bench press matches
                found_press = True
                if check_config(3, 12):
                    press_config = True
                    
    distinct_exercises = sum([found_bench, found_row, found_press])
    
    # 4. Award criteria points
    if found_bench:
        score += 15
        feedback.append("Bench press added.")
        if bench_config:
            score += 10
            feedback.append("Bench press configured (4x8).")
        else:
            feedback.append("Bench press config missing/incorrect.")
            
    if found_row:
        score += 15
        feedback.append("Row exercise added.")
        if row_config:
            score += 10
            feedback.append("Row configured (3x10).")
        else:
            feedback.append("Row config missing/incorrect.")
            
    if found_press:
        score += 15
        feedback.append("Press exercise added.")
        if press_config:
            score += 10
            feedback.append("Press configured (3x12).")
        else:
            feedback.append("Press config missing/incorrect.")
            
    if distinct_exercises >= 3:
        score += 10
        feedback.append("All 3 distinct exercise types present.")
        
    # 5. Supplementary VLM Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            try:
                vlm_res = query_vlm(
                    prompt=VERIFICATION_PROMPT,
                    images=images
                )
                parsed = vlm_res.get("parsed", {})
                if parsed.get("searched_exercises"):
                    vlm_score += 5
                if parsed.get("configured_sets_reps"):
                    vlm_score += 5
                    
                score += vlm_score
                feedback.append(f"VLM verified workflow (+{vlm_score} pts).")
            except Exception as e:
                logger.error(f"VLM verification error: {e}")
                
    # 6. Final success determination
    # Minimum requirement: 60 points + At least 2 correct distinct exercises added
    passed = score >= 60 and distinct_exercises >= 2
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "details": {
            "exercise_count": exercise_count,
            "found_bench": found_bench,
            "bench_config": bench_config,
            "found_row": found_row,
            "row_config": row_config,
            "found_press": found_press,
            "press_config": press_config,
            "distinct_types": distinct_exercises
        }
    }