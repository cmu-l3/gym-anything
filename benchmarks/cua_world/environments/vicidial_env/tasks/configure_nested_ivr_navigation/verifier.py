#!/usr/bin/env python3
"""
Verifier for configure_nested_ivr_navigation task.
Checks creation of In-Groups, Call Menus, and the routing logic between them.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nested_ivr(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    ingroups = result.get("ingroups", {})
    menus = result.get("menus", {})
    options = result.get("options", [])
    
    # Helper to find option
    def get_option(menu_id, opt_key):
        for o in options:
            if o["menu_id"] == menu_id and o["option"] == opt_key:
                return o
        return None

    # 1. Verify In-Groups (10 pts)
    if "TC_SALES" in ingroups and ingroups["TC_SALES"].get("active") == "Y":
        score += 5
        feedback.append("In-Group TC_SALES created and active.")
    else:
        feedback.append("In-Group TC_SALES missing or inactive.")

    if "TC_TECH" in ingroups and ingroups["TC_TECH"].get("active") == "Y":
        score += 5
        feedback.append("In-Group TC_TECH created and active.")
    else:
        feedback.append("In-Group TC_TECH missing or inactive.")

    # 2. Verify Menu Shells (10 pts)
    if "MENU_MAIN" in menus:
        score += 5
        feedback.append("Menu MENU_MAIN created.")
    else:
        feedback.append("Menu MENU_MAIN missing.")

    if "MENU_SUB_SUP" in menus:
        score += 5
        feedback.append("Menu MENU_SUB_SUP created.")
    else:
        feedback.append("Menu MENU_SUB_SUP missing.")

    # 3. Verify Main Menu Routing (40 pts)
    # Option 1 -> TC_SALES
    opt_main_1 = get_option("MENU_MAIN", "1")
    if opt_main_1:
        if opt_main_1["route"] == "IN_GROUP" and opt_main_1["value"] == "TC_SALES":
            score += 20
            feedback.append("MENU_MAIN Opt 1 routes correctly to TC_SALES.")
        else:
            feedback.append(f"MENU_MAIN Opt 1 exists but routes to {opt_main_1['route']}:{opt_main_1['value']}.")
    else:
        feedback.append("MENU_MAIN Opt 1 missing.")

    # Option 2 -> MENU_SUB_SUP
    opt_main_2 = get_option("MENU_MAIN", "2")
    if opt_main_2:
        if opt_main_2["route"] == "CALLMENU" and opt_main_2["value"] == "MENU_SUB_SUP":
            score += 20
            feedback.append("MENU_MAIN Opt 2 routes correctly to MENU_SUB_SUP.")
        else:
            feedback.append(f"MENU_MAIN Opt 2 exists but routes to {opt_main_2['route']}:{opt_main_2['value']}.")
    else:
        feedback.append("MENU_MAIN Opt 2 missing.")

    # 4. Verify Sub Menu Routing (40 pts)
    # Option 1 -> TC_TECH
    opt_sub_1 = get_option("MENU_SUB_SUP", "1")
    if opt_sub_1:
        if opt_sub_1["route"] == "IN_GROUP" and opt_sub_1["value"] == "TC_TECH":
            score += 20
            feedback.append("MENU_SUB_SUP Opt 1 routes correctly to TC_TECH.")
        else:
            feedback.append(f"MENU_SUB_SUP Opt 1 exists but routes to {opt_sub_1['route']}:{opt_sub_1['value']}.")
    else:
        feedback.append("MENU_SUB_SUP Opt 1 missing.")

    # Option 9 -> MENU_MAIN (Back)
    opt_sub_9 = get_option("MENU_SUB_SUP", "9")
    if opt_sub_9:
        if opt_sub_9["route"] == "CALLMENU" and opt_sub_9["value"] == "MENU_MAIN":
            score += 20
            feedback.append("MENU_SUB_SUP Opt 9 routes correctly back to MENU_MAIN.")
        else:
            feedback.append(f"MENU_SUB_SUP Opt 9 exists but routes to {opt_sub_9['route']}:{opt_sub_9['value']}.")
    else:
        feedback.append("MENU_SUB_SUP Opt 9 missing.")

    passed = score >= 80  # Threshold requiring functional navigation
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }