#!/usr/bin/env python3
"""
Verifier for create_menu_group task.

Criteria:
1. Database record exists for 'Breakfast Specials' (primary)
2. App was running (prerequisite)
3. Visual verification of Back Office UI (secondary)
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Import VLM utils if available
try:
    sys.path.insert(0, str(Path(__file__).parent.parent))
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/mock for standalone testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not imported"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n=1): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_menu_group(traj, env_info, task_info):
    """
    Verifies that the menu group was created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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

    score = 0
    feedback_parts = []
    
    # 2. Score based on DB record (Primary Signal)
    db_record_found = result.get("db_record_found", False)
    db_record_name = result.get("db_record_name", "")
    
    if db_record_found:
        score += 60
        feedback_parts.append("Database record found for 'Breakfast Specials'")
        if db_record_name.strip() == "Breakfast Specials":
             score += 10 # Exact match bonus
    else:
        feedback_parts.append("No database record found for 'Breakfast Specials'")

    # 3. Score based on App State
    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("Application was running")

    # 4. VLM Verification (Secondary Signal)
    # Check if agent was in the Menu Group editor
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    if frames or final_img:
        images_to_check = frames + ([final_img] if final_img else [])
        
        prompt = """
        Review these screenshots from a Point of Sale system task.
        Goal: Create a new Menu Group named "Breakfast Specials".
        
        Look for:
        1. The "Menu Group" editor or list.
        2. Text "Breakfast Specials" being typed or displayed.
        3. A "Save" or "OK" button being clicked in a form.
        4. The "Back Office" interface (usually grey/administrative look, not the colorful button grid).
        
        JSON response:
        {
            "back_office_seen": boolean,
            "menu_group_form_seen": boolean,
            "breakfast_specials_text_seen": boolean,
            "confidence": "low|medium|high"
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=images_to_check)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("back_office_seen"):
                score += 10
                feedback_parts.append("VLM: Back Office accessed")
            if parsed.get("menu_group_form_seen"):
                score += 5
                feedback_parts.append("VLM: Menu Group form seen")
            if parsed.get("breakfast_specials_text_seen"):
                score += 5
                feedback_parts.append("VLM: 'Breakfast Specials' text visible")

    # Final logic
    passed = (score >= 70) and db_record_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }