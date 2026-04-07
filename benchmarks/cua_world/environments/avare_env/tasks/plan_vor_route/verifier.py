#!/usr/bin/env python3
import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plan_vor_route(traj, env_info, task_info):
    """
    Verify the flight plan creation task.
    
    Criteria:
    1. A flight plan file named "VOR_PRACTICE" exists.
    2. The plan was created during the task.
    3. The plan contains exactly 3 waypoints.
    4. Waypoints are KRHV -> SJC (VOR) -> KSQL.
    5. CRITICAL: The second waypoint must be the VOR (ID: SJC), NOT the airport (ID: KSJC).
    6. VLM verification of the workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Freshness
    if not result_data.get('plan_exists'):
        return {"passed": False, "score": 0, "feedback": "Plan 'VOR_PRACTICE' not saved."}
    
    score += 10
    feedback_parts.append("Plan saved")

    if result_data.get('created_during_task'):
        score += 10
        feedback_parts.append("Plan created during task")
    else:
        feedback_parts.append("Plan file is old (anti-gaming fail)")
        # We continue to verify content, but this is a major deduction

    # 3. Analyze Plan Content
    # We need to pull the actual plan file content
    plan_content_valid = False
    waypoints_correct = False
    vor_distinction_correct = False
    
    exported_plan_path = result_data.get('exported_plan_path')
    if exported_plan_path:
        temp_plan = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(exported_plan_path, temp_plan.name)
            with open(temp_plan.name, 'r') as f:
                # Avare plan format is typically a JSON array of objects
                # Example: [{"ID":"KRHV", "Type":"Airport", ...}, {"ID":"SJC", "Type":"VOR", ...}]
                try:
                    plan_json = json.load(f)
                    # Handle typical Avare structure (it might be wrapped or a raw list)
                    waypoints = plan_json if isinstance(plan_json, list) else plan_json.get("waypoints", [])
                    
                    if len(waypoints) == 3:
                        score += 10
                        feedback_parts.append("Correct waypoint count (3)")
                        
                        # Waypoint 1: KRHV
                        wp1_id = waypoints[0].get("ID", "").upper()
                        if wp1_id == "KRHV":
                            score += 10
                            feedback_parts.append("Dep: KRHV")
                        
                        # Waypoint 2: SJC (The Critical Check)
                        wp2_id = waypoints[1].get("ID", "").upper()
                        wp2_type = waypoints[1].get("Type", "")
                        
                        if wp2_id == "SJC":
                            score += 40  # Big points for getting the VOR correct
                            feedback_parts.append("Int: SJC (VOR) - Correct")
                            vor_distinction_correct = True
                        elif wp2_id == "KSJC":
                            score += 0
                            feedback_parts.append("Int: KSJC (Airport) - INCORRECT (Expected VOR 'SJC')")
                        else:
                            feedback_parts.append(f"Int: Unexpected ID '{wp2_id}'")
                            
                        # Waypoint 3: KSQL
                        wp3_id = waypoints[2].get("ID", "").upper()
                        if wp3_id == "KSQL":
                            score += 10
                            feedback_parts.append("Dest: KSQL")
                            
                    else:
                        feedback_parts.append(f"Incorrect waypoint count: {len(waypoints)}")
                        
                except json.JSONDecodeError:
                    feedback_parts.append("Failed to parse plan file JSON")
        except Exception as e:
            feedback_parts.append(f"Error reading plan content: {e}")
        finally:
            if os.path.exists(temp_plan.name):
                os.unlink(temp_plan.name)

    # 4. VLM Verification (Trajectory Analysis)
    # Useful to confirm they didn't just write a file manually or to verify visual feedback
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of the Avare aviation app. "
            "Did the user create a flight plan? "
            "Look for a list of waypoints KRHV, SJC, KSQL. "
            "Does the map show a route line connecting 3 points? "
            "Is the plan saved with the name 'VOR_PRACTICE'?"
        )
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_res.get('success'):
            # Simple heuristic for VLM score based on keyword presence in reasoning
            reasoning = vlm_res.get('parsed', {}).get('reasoning', '').lower()
            if "yes" in reasoning or "success" in reasoning or "vor_practice" in reasoning:
                score += 20
                feedback_parts.append("VLM confirms workflow")
            else:
                feedback_parts.append("VLM did not confirm workflow")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Final Pass Logic
    # Pass if score >= 80 AND the critical VOR distinction was correct
    passed = (score >= 80) and vor_distinction_correct
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }