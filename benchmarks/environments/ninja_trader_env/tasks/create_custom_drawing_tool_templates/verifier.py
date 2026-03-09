#!/usr/bin/env python3
"""
Verifier for create_custom_drawing_tool_templates task in NinjaTrader.
Verifies the existence, timestamp, and content of XML template files.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_drawing_tool_templates(traj, env_info, task_info):
    """
    Verify creation of 3 drawing tool templates.
    
    Scoring:
    - SupplyZone (Rectangle): 40 pts (Exists + Red + Opacity~20%)
    - DemandZone (Rectangle): 40 pts (Exists + Green + Opacity~20% - implicit in copy usually, but color critical)
    - BigNote (Text): 20 pts (Exists + Blue + Bold + Size 20)
    
    Anti-gaming: Checks timestamps > task_start.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    opacity_target = metadata.get('opacity_target', 20)
    opacity_tolerance = metadata.get('opacity_tolerance', 5)

    # Copy result file from Windows container
    # Path inside container: C:\Users\Docker\Desktop\task_result.json
    # The copy_from_env function handles the path translation usually
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Depending on the backend, Windows paths might need special handling
        # standard gym-anything convention uses forward slashes often even for win
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # --- Verify SupplyZone (40 pts) ---
    sz = result.get('supply_zone', {})
    if sz.get('exists') and sz.get('created_during_task'):
        subscore = 10
        f_msgs = ["SupplyZone created"]
        
        # Color check
        if sz.get('contains_red'):
            subscore += 15
            f_msgs.append("Red color correct")
        else:
            f_msgs.append("Color mismatch (expected Red)")

        # Opacity check
        op_val = sz.get('opacity_val', 100)
        if abs(op_val - opacity_target) <= opacity_tolerance:
            subscore += 15
            f_msgs.append(f"Opacity {op_val}% correct")
        else:
            f_msgs.append(f"Opacity {op_val}% incorrect (target {opacity_target}%)")
            
        score += subscore
        feedback_parts.append(f"SupplyZone: {', '.join(f_msgs)} ({subscore}/40)")
    else:
        feedback_parts.append("SupplyZone: Not created or old file (0/40)")

    # --- Verify DemandZone (40 pts) ---
    dz = result.get('demand_zone', {})
    if dz.get('exists') and dz.get('created_during_task'):
        subscore = 20 # Base for existence
        f_msgs = ["DemandZone created"]
        
        if dz.get('contains_green'):
            subscore += 20
            f_msgs.append("Green color correct")
        else:
            f_msgs.append("Color mismatch (expected Green)")
            
        score += subscore
        feedback_parts.append(f"DemandZone: {', '.join(f_msgs)} ({subscore}/40)")
    else:
        feedback_parts.append("DemandZone: Not created or old file (0/40)")

    # --- Verify BigNote (20 pts) ---
    bn = result.get('big_note', {})
    if bn.get('exists') and bn.get('created_during_task'):
        subscore = 5
        f_msgs = ["BigNote created"]
        
        if bn.get('contains_blue'):
            subscore += 5
            f_msgs.append("Blue")
        if bn.get('contains_bold'):
            subscore += 5
            f_msgs.append("Bold")
        if bn.get('contains_size_20'):
            subscore += 5
            f_msgs.append("Size 20")
            
        score += subscore
        feedback_parts.append(f"BigNote: {', '.join(f_msgs)} ({subscore}/20)")
    else:
        feedback_parts.append("BigNote: Not created or old file (0/20)")

    # Final Pass Check
    # Must create at least the two zones correctly to pass
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }