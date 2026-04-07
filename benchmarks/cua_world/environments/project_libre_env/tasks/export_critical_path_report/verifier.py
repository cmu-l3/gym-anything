#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_critical_path_report(traj, env_info, task_info):
    """
    Verifies that the agent filtered for critical tasks and exported a PDF.
    
    Scoring Criteria:
    1. PDF File Exists & Valid (30 pts)
    2. File Created During Task (20 pts)
    3. VLM: Filter Applied (Visual Check) (50 pts)
       - Checks if the list of tasks is reduced (filtering happened).
       - Checks if non-critical tasks are hidden.
    """
    
    # 1. Setup & Data Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
        
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System Error: query_vlm missing"}

    # Load result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            result_data = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}

    score = 0
    feedback = []
    
    # 2. File Verification (50 pts total)
    output_exists = result_data.get("output_exists", "false")
    file_created = result_data.get("file_created_during_task", False)
    file_size = result_data.get("file_size_bytes", 0)

    if output_exists == "true":
        score += 30
        feedback.append("PDF output file found.")
    elif output_exists == "true_alt_location":
        score += 15
        feedback.append("PDF found but in wrong directory (likely ~/PDF/ instead of ~/Projects/).")
    else:
        feedback.append("No PDF output file found.")

    if file_created and file_size > 1000: # Min 1KB
        score += 20
        feedback.append("File created successfully during task session.")
    elif file_created:
        feedback.append("File created but seems empty/corrupt.")
    else:
        feedback.append("File verification failed (timestamp or existence).")

    # 3. Visual Verification (50 pts total)
    # We check the final screenshot to see if the view is filtered.
    # In a full project view, the screen is full of bars. 
    # In critical path view, many tasks disappear (ProjectLibre hides non-critical).
    
    final_screenshot = result_data.get("screenshot_path", "")
    
    # If we can't see the screen, we can't verify the filter.
    if not final_screenshot:
         return {"passed": False, "score": score, "feedback": " ".join(feedback) + " No screenshot available for visual verification."}
         
    # VLM Query
    # We ask specifically about the presence of filtered data
    prompt = """
    You are verifying a ProjectLibre task. The goal was to apply a 'Critical' filter.
    
    Look at the screenshot:
    1. Are there blue bars (standard tasks) visible in the Gantt chart? Or primarily red bars (critical tasks)?
    2. Does the task list look filtered (some ID numbers missing or gaps in the list)?
    3. Is the 'Database Implementation' task visible? (It is non-critical, so it should be HIDDEN).
    4. Is the 'Backend API Development' task visible? (It is critical, so it should be VISIBLE).
    
    If the view shows ALL tasks (blue and red bars, full list), the filter was NOT applied.
    If the view shows primarily red bars or a reduced list, the filter WAS applied.
    
    Return JSON:
    {
        "filter_applied": boolean,
        "mostly_red_bars": boolean,
        "reasoning": "string"
    }
    """
    
    # Since the screenshot is in the container, we need to fetch it to host for VLM? 
    # The framework usually handles `query_vlm` with the `traj` object or paths.
    # Assuming `query_vlm` handles the logic or we use `traj` frames.
    # For safety, we use `traj[-1]` (final frame) if available.
    
    try:
        # We try to use the final frame from trajectory first as it's definitely on host
        img_to_check = traj[-1]['image'] if traj and len(traj) > 0 else None
        
        if img_to_check:
            vlm_response = query_vlm(
                prompt=prompt,
                images=[img_to_check] 
            )
            
            # Simple parsing of VLM response (assuming structured object or text)
            # Adapting to typical framework response format
            if isinstance(vlm_response, dict):
                 # Look for parsed JSON in the text field if the VLM returns text
                 content = vlm_response.get('text', '') or vlm_response.get('answer', '')
            else:
                 content = str(vlm_response)

            # Heuristic check on VLM text
            if "true" in content.lower() and ("red" in content.lower() or "filter" in content.lower()):
                score += 50
                feedback.append("Visual verification passed: Critical filter appears active.")
            elif "false" in content.lower():
                feedback.append("Visual verification failed: View does not appear filtered.")
            else:
                # Ambiguous VLM response, award partial
                score += 25
                feedback.append("Visual verification inconclusive, partial credit.")
                
        else:
            feedback.append("No trajectory images available for VLM.")

    except Exception as e:
        feedback.append(f"VLM check failed: {str(e)}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }