#!/usr/bin/env python3
"""
Verifier for school_lunch_menu_planning task.

Checks:
1. Firefox history for USDA FoodData Central and FNS visits.
2. Existence and freshness of ~/Documents/weekly_menu_plan.json.
3. Correct structure and plausible nutritional values in the JSON.
4. Existence of specific bookmarks.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_school_lunch_menu_planning(traj, env_info, task_info):
    """
    Verifies the school lunch menu planning task.
    """
    # 1. Retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Initialize Scoring
    score = 0
    feedback = []
    
    # --- Criterion 1: Research Activity (History) [15 pts] ---
    visits_fdc = result.get('visits_fdc', 0)
    visits_fns = result.get('visits_fns', 0)
    
    if visits_fdc > 0 and visits_fns > 0:
        score += 15
        feedback.append("Research: Visited both FDC and FNS websites (+15)")
    elif visits_fdc > 0 or visits_fns > 0:
        score += 8
        feedback.append("Research: Visited one required USDA website (+8)")
    else:
        feedback.append("Research: No evidence of USDA website visits (+0)")

    # --- Criterion 2: Bookmarks [20 pts] ---
    folder_exists = result.get('bookmark_folder_exists', 0)
    bm_count = result.get('bookmark_count', 0)
    usda_bm_count = result.get('usda_bookmark_count', 0)
    
    if folder_exists:
        score += 10
        feedback.append("Bookmarks: Folder 'Menu Planning Resources' created (+10)")
        
        if bm_count >= 5:
            score += 5
            feedback.append(f"Bookmarks: Correct count ({bm_count} >= 5) (+5)")
        else:
            feedback.append(f"Bookmarks: Insufficient count ({bm_count} < 5) (+0)")
            
        if usda_bm_count >= 2:
            score += 5
            feedback.append(f"Bookmarks: Contains USDA sources ({usda_bm_count} >= 2) (+5)")
        else:
            feedback.append("Bookmarks: Missing USDA specific sources (+0)")
    else:
        feedback.append("Bookmarks: Folder not found (+0)")

    # --- Criterion 3: JSON File Existence & Freshness [10 pts] ---
    json_exists = result.get('json_file_exists', 0)
    json_fresh = result.get('json_file_fresh', 0)
    menu_data = result.get('menu_json_content', {})
    
    if json_exists and json_fresh:
        score += 10
        feedback.append("File: JSON file created during task (+10)")
    elif json_exists:
        score += 5
        feedback.append("File: JSON file exists but timestamp is old (anti-gaming check) (+5)")
    else:
        feedback.append("File: JSON file not found (+0)")
        # Critical failure for subsequent checks
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # --- Criterion 4: JSON Structure & Content [55 pts] ---
    if not isinstance(menu_data, dict):
        feedback.append("Content: Invalid JSON structure (not a dictionary) (+0)")
    else:
        days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
        components = ['main_dish', 'side', 'vegetable', 'fruit', 'milk']
        
        days_present = 0
        valid_days = 0
        plausible_days = 0
        
        for day in days:
            if day in menu_data:
                days_present += 1
                day_data = menu_data[day]
                
                # Check all components present
                comps_present = all(c in day_data for c in components)
                has_total = 'total_calories' in day_data
                
                if comps_present and has_total:
                    valid_days += 1
                    
                    # Check nutritional plausibility
                    # 1. Total calories roughly matches sum of parts (+/- 50)
                    calc_total = sum(day_data[c].get('calories', 0) for c in components if isinstance(day_data[c], dict))
                    stated_total = day_data.get('total_calories', 0)
                    
                    # 2. Total is in reasonable lunch range (400-1000)
                    # 3. Protein is numeric and > 0
                    is_plausible = True
                    if not (400 <= stated_total <= 1000): is_plausible = False
                    if abs(calc_total - stated_total) > 50: is_plausible = False
                    
                    # Check individual components roughly
                    for c in components:
                        c_data = day_data[c]
                        if not isinstance(c_data, dict): is_plausible = False; break
                        cal = c_data.get('calories', 0)
                        prot = c_data.get('protein_g', -1)
                        if not (0 < cal < 1200): is_plausible = False # Single item shouldn't be >1200 or 0
                        if prot < 0: is_plausible = False
                    
                    if is_plausible:
                        plausible_days += 1

        # Score for Days Present (Max 10)
        if days_present == 5: score += 10; feedback.append("Content: All 5 days present (+10)")
        elif days_present > 0: score += (days_present * 2); feedback.append(f"Content: {days_present}/5 days present (+{days_present*2})")
        
        # Score for Structure (Max 15)
        if valid_days == 5: score += 15; feedback.append("Content: All days have correct components (+15)")
        elif valid_days > 0: score += (valid_days * 3); feedback.append(f"Content: {valid_days}/5 days valid structure (+{valid_days*3})")
        
        # Score for Plausibility (Max 30)
        if plausible_days == 5: score += 30; feedback.append("Content: Nutritional data plausible for all days (+30)")
        elif plausible_days > 0: score += (plausible_days * 6); feedback.append(f"Content: {plausible_days}/5 days plausible (+{plausible_days*6})")
        else: feedback.append("Content: Nutritional data implausible or totals incorrect (+0)")

    # 3. Final Check
    passed = (score >= 60) and (json_exists and json_fresh)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }