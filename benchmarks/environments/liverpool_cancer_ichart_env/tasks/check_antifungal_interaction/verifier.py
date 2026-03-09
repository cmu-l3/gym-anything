#!/usr/bin/env python3
"""
Verifier for check_antifungal_interaction task.

Verification Strategy:
1. Anti-gaming: Check app launch and task duration.
2. VLM Trajectory: Verify multi-step navigation (Dabrafenib -> Category -> Ketoconazole).
3. VLM Final State: Verify the final screen shows the interaction result and color.
4. UI Text (Fallback): Check if specific keywords are visible in the UI dump.
"""

import json
import tempfile
import os
import logging
import sys

# Import VLM utilities from the framework
# (Adjust import path based on actual environment structure if needed)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/Mock for local testing without framework
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_antifungal_interaction(traj, env_info, task_info):
    """
    Verify that the agent checked the interaction between Dabrafenib and Ketoconazole.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    cancer_drug = metadata.get('cancer_drug', 'Dabrafenib')
    comedication = metadata.get('comedication', 'Ketoconazole')
    expected_colors = metadata.get('expected_colors', ['red', 'orange'])

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Task Result JSON & Text Dump
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_text = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    task_result = {}
    visible_text_content = ""

    try:
        # Get JSON
        copy_from_env("/sdcard/tasks/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
            
        # Get Text Dump (optional, might not exist)
        try:
            copy_from_env("/sdcard/tasks/visible_text.txt", temp_text.name)
            with open(temp_text.name, 'r') as f:
                visible_text_content = f.read().lower()
        except Exception:
            logger.warning("Could not retrieve visible_text.txt")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_text.name): os.unlink(temp_text.name)

    # ================================================================
    # 2. Basic State Verification (30 Points)
    # ================================================================
    
    # App Launched (15 pts)
    if task_result.get("app_launched", False):
        score += 15
        feedback_parts.append("App was launched.")
    else:
        feedback_parts.append("App was NEVER launched.")
        return {"passed": False, "score": 0, "feedback": "Fail: App not launched."}

    # App Focused at end (10 pts)
    if task_result.get("app_focused", False):
        score += 10
        feedback_parts.append("App is in foreground.")
    else:
        feedback_parts.append("App not in foreground at end.")

    # Duration check (5 pts) - Anti-gaming for impossible speed
    duration = task_result.get("task_duration_seconds", 0)
    if duration > 5:
        score += 5
    else:
        feedback_parts.append("Task completed suspiciously fast (<5s).")

    # ================================================================
    # 3. VLM Trajectory Verification (40 Points)
    # ================================================================
    # We want to see the workflow: Search -> Select Dabrafenib -> Select Category -> Select Ketoconazole
    
    frames = sample_trajectory_frames(traj, n=6)
    
    trajectory_prompt = f"""
    You are verifying an agent using a medical app 'Liverpool Cancer iChart'.
    The goal is to navigate: Drug List -> Select '{cancer_drug}' -> Select category 'Antifungal' -> Select '{comedication}'.
    
    Look at the sequence of screenshots.
    1. Do you see a list of cancer drugs or a search for '{cancer_drug}'?
    2. Do you see the details page for '{cancer_drug}'?
    3. Do you see a category list including 'Antifungals' or 'Antifungal agents'?
    4. Do you see the interaction result page?
    
    JSON Output:
    {{
        "seen_drug_search": boolean,
        "seen_dabrafenib_page": boolean,
        "seen_antifungal_category": boolean,
        "workflow_score_0_to_10": integer
    }}
    """
    
    vlm_traj_res = query_vlm(images=frames, prompt=trajectory_prompt)
    
    traj_score = 0
    if vlm_traj_res and vlm_traj_res.get("success"):
        parsed = vlm_traj_res.get("parsed", {})
        if parsed.get("seen_drug_search"): traj_score += 10
        if parsed.get("seen_dabrafenib_page"): traj_score += 10
        if parsed.get("seen_antifungal_category"): traj_score += 10
        
        # Add remaining points based on qualitative score
        qual_score = parsed.get("workflow_score_0_to_10", 0)
        traj_score += qual_score  # Max 10 pts here
        
        feedback_parts.append(f"Trajectory analysis: {traj_score}/40 points.")
    else:
        feedback_parts.append("VLM Trajectory analysis failed.")
        # Fallback: give partial credit if UI text dump contains key terms
        if cancer_drug.lower() in visible_text_content:
            traj_score += 10
            feedback_parts.append("(Fallback) 'Dabrafenib' found in UI text.")
    
    score += min(traj_score, 40)

    # ================================================================
    # 4. Final Result Verification (30 Points)
    # ================================================================
    # Check the final screen for the specific interaction result
    
    final_img = get_final_screenshot(traj)
    
    final_prompt = f"""
    Analyze this app screenshot.
    1. Is the drug '{cancer_drug}' visible?
    2. Is the co-medication '{comedication}' visible?
    3. Is there a traffic-light color indicator visible? (Red, Orange, Yellow, Green, Grey)
    4. What color is the indicator?
    
    JSON Output:
    {{
        "dabrafenib_visible": boolean,
        "ketoconazole_visible": boolean,
        "color_indicator_visible": boolean,
        "detected_color": "string"
    }}
    """
    
    vlm_final_res = query_vlm(image=final_img, prompt=final_prompt)
    
    final_score = 0
    passed_final = False
    
    if vlm_final_res and vlm_final_res.get("success"):
        parsed = vlm_final_res.get("parsed", {})
        
        # Check drugs visible (10 pts)
        if parsed.get("dabrafenib_visible") or parsed.get("ketoconazole_visible"):
            final_score += 10
        
        # Check color (20 pts)
        detected_color = parsed.get("detected_color", "").lower()
        color_match = any(c in detected_color for c in expected_colors)
        
        if parsed.get("color_indicator_visible") and color_match:
            final_score += 20
            passed_final = True
            feedback_parts.append(f"Correct interaction color ({detected_color}) detected.")
        elif parsed.get("color_indicator_visible"):
            final_score += 5
            feedback_parts.append(f"Wrong interaction color detected: {detected_color}.")
        else:
            feedback_parts.append("No interaction color indicator found.")
            
    else:
        # Fallback to text dump
        if cancer_drug.lower() in visible_text_content and comedication.lower() in visible_text_content:
            final_score += 10
            feedback_parts.append("(Fallback) Both drugs found in UI text.")
            
    score += min(final_score, 30)

    # ================================================================
    # Final Decision
    # ================================================================
    
    # Pass threshold: 60 points AND final verification passed (or strong trajectory)
    # We require seeing the drugs/category to prevent just launching the app.
    pass_threshold = 60
    passed = (score >= pass_threshold) and (passed_final or traj_score >= 20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }