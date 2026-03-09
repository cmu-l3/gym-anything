#!/usr/bin/env python3
"""
Verifier for customize_menu_item_visuals task.

Criteria:
1. Item 'Firecracker Shrimp' exists in DB (30 pts)
2. Price is 12.99 (20 pts)
3. Button Color is Red (approx -65536) (20 pts)
4. Text Color is White (approx -1) (20 pts)
5. VLM Verification of UI interaction (10 pts)
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Import gym_anything utility if available, otherwise mock
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): 
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_menu_item_visuals(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Firecracker Shrimp')
    expected_price = metadata.get('expected_price', 12.99)
    # Java Color.RED.getRGB() is -65536 (0xFFFF0000)
    # Java Color.WHITE.getRGB() is -1 (0xFFFFFFFF)
    expected_btn_color = str(metadata.get('expected_btn_color_int', '-65536'))
    expected_text_color = str(metadata.get('expected_text_color_int', '-1'))

    score = 0
    feedback_parts = []
    
    # 1. Read Result JSON
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

    app_running = result.get('app_was_running', False)
    db_output = result.get('db_query_output', "")
    
    if not app_running:
        feedback_parts.append("App was not running at end of task (-5)")
    else:
        score += 5 # Bonus for clean state
        feedback_parts.append("App was running")

    # 2. Parse DB Output
    # ij output typically looks like:
    # NAME            |PRICE               |BTN_COLOR  |TEXT_COLOR |VISIBLE
    # ---------------------------------------------------------------------
    # Firecracker Shr*|12.99               |-65536     |-1         |true 
    
    item_found = False
    price_correct = False
    btn_color_correct = False
    text_color_correct = False
    
    if expected_name in db_output:
        item_found = True
        score += 30
        feedback_parts.append(f"Item '{expected_name}' created")
        
        # Check attributes in the same output block
        # We look for the line containing the name
        for line in db_output.splitlines():
            if expected_name in line:
                # Check Price
                if str(expected_price) in line:
                    price_correct = True
                    score += 20
                    feedback_parts.append("Price correct")
                else:
                    feedback_parts.append("Price incorrect")
                
                # Check Button Color
                if expected_btn_color in line:
                    btn_color_correct = True
                    score += 20
                    feedback_parts.append("Button color RED")
                elif "null" in line.lower() and "BTN_COLOR" not in line: 
                    feedback_parts.append("Button color not set")
                elif "BTN_COLOR" not in line:
                    # If it's some other number
                    feedback_parts.append("Button color set (wrong color)")
                    score += 5 # Partial credit for changing it
                
                # Check Text Color
                if expected_text_color in line:
                    text_color_correct = True
                    score += 20
                    feedback_parts.append("Text color WHITE")
                elif "null" in line.lower() and "TEXT_COLOR" not in line:
                     feedback_parts.append("Text color not set")
                elif "TEXT_COLOR" not in line:
                    feedback_parts.append("Text color set (wrong color)")
                    score += 5 # Partial credit
                
                break
    else:
        feedback_parts.append(f"Item '{expected_name}' NOT found in database")

    # 3. VLM Verification (Trajectory)
    # We want to see if they opened the color chooser
    frames = sample_trajectory_frames(traj, n=8)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of a user using Floreant POS.
        Did the user:
        1. Access the 'Menu Items' or 'Explorers' screen?
        2. Open a 'Color' chooser dialog (usually shows a color palette/wheel or Swatches)?
        3. Select Red or White colors?
        
        Return JSON:
        {
            "accessed_menu_explorer": true/false,
            "opened_color_chooser": true/false,
            "confidence": "low/medium/high"
        }
        """
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("opened_color_chooser"):
                score += 5
                feedback_parts.append("VLM: Color chooser usage detected")
            elif parsed.get("accessed_menu_explorer"):
                 # Small points for navigation if they failed the color part
                 pass 
    
    # Final Score Calculation
    passed = item_found and price_correct and btn_color_correct and text_color_correct and (score >= 95)
    
    # Allow small tolerance
    if score >= 90 and item_found and price_correct:
        passed = True

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }