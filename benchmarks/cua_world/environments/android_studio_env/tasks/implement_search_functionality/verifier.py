#!/usr/bin/env python3
"""
Verifier for implement_search_functionality task.

Criteria:
1. Build Success (20 pts)
2. Menu XML created with SearchView (20 pts)
3. EmployeeAdapter updated with filtering logic (30 pts)
4. MainActivity updated with OnQueryTextListener (30 pts)
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_search_functionality(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env missing"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Build Success
    if result.get("build_success", False):
        score += 20
        feedback.append("Build Success: Passed (20/20)")
    else:
        feedback.append("Build Success: Failed (0/20) - Code must compile")

    # 2. Menu XML Verification
    menu_content = result.get("menu_content", "")
    if result.get("menu_file_exists", False) and menu_content:
        # Check for item ID and ActionView
        has_id = "action_search" in menu_content
        has_search_view = "androidx.appcompat.widget.SearchView" in menu_content or "android.widget.SearchView" in menu_content
        
        if has_id and has_search_view:
            score += 20
            feedback.append("Menu XML: Valid SearchView found (20/20)")
        elif has_search_view:
            score += 15
            feedback.append("Menu XML: SearchView found but incorrect ID (15/20)")
        else:
            score += 5
            feedback.append("Menu XML: File exists but missing SearchView configuration (5/20)")
    else:
        feedback.append("Menu XML: File not found (0/20)")

    # 3. Adapter Verification
    # Logic: Should maintain a copy of list, and have a filter/search function
    adapter_content = result.get("adapter_content", "")
    if adapter_content:
        # Check for filtering keywords
        has_filter_logic = any(x in adapter_content.lower() for x in ["filter", "contains", "lowercase"])
        has_notify = "notifyDataSetChanged" in adapter_content or "submitList" in adapter_content
        
        # Check if they created a second list (e.g., filteredList vs originalList)
        # This is a heuristic: checking for variable declarations involving lists
        list_vars = len(re.findall(r'List<Employee>', adapter_content))
        
        if has_filter_logic and has_notify:
            score += 30
            feedback.append("Adapter: Filtering logic detected (30/30)")
        elif has_filter_logic:
            score += 20
            feedback.append("Adapter: Filter logic found but missing notifyDataSetChanged (20/30)")
        else:
            feedback.append("Adapter: No filtering logic detected (0/30)")
    else:
        feedback.append("Adapter: File not read (0/30)")

    # 4. Activity Verification
    # Logic: onCreateOptionsMenu + setOnQueryTextListener
    activity_content = result.get("activity_content", "")
    if activity_content:
        has_menu_inflation = "onCreateOptionsMenu" in activity_content
        has_listener = "setOnQueryTextListener" in activity_content
        has_query_change = "onQueryTextChange" in activity_content
        
        if has_menu_inflation and has_listener and has_query_change:
            score += 30
            feedback.append("Activity: Search listener wired up correctly (30/30)")
        elif has_menu_inflation:
            score += 10
            feedback.append("Activity: Menu inflation found but missing listener (10/30)")
        else:
            feedback.append("Activity: Missing menu logic (0/30)")
    else:
        feedback.append("Activity: File not read (0/30)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }