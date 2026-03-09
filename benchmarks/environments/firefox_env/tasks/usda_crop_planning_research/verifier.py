#!/usr/bin/env python3
"""
Verifier for usda_crop_planning_research task.

Verifies:
1. Browser History: Visits to USDA NASS and ERS domains.
2. Bookmarks: Specific folder created with USDA links.
3. Output File: JSON advisory exists, is valid, and contains plausible data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_usda_crop_planning_research(traj, env_info, task_info):
    """
    Verify USDA Crop Planning Research task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Verification Data
    task_result_path = "/tmp/task_result.json"
    advisory_file_path = "/home/ga/Documents/crop_planning_advisory.json"
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_advisory = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Copy task result (history/bookmarks stats)
        copy_from_env(task_result_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_stats = json.load(f)
            
        # Copy advisory file (agent output)
        advisory_data = None
        if task_stats.get("file_exists", False):
            try:
                copy_from_env(advisory_file_path, temp_advisory.name)
                with open(temp_advisory.name, 'r') as f:
                    advisory_data = json.load(f)
            except Exception as e:
                logger.warning(f"Failed to read advisory file: {e}")
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_advisory.name): os.unlink(temp_advisory.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Browser History (25 pts) ---
    usda_visits = task_stats.get("usda_visits", 0)
    nass_visits = task_stats.get("nass_visits", 0)
    ers_visits = task_stats.get("ers_visits", 0)
    
    if usda_visits >= 3:
        if nass_visits >= 1 and ers_visits >= 1:
            score += 25
            feedback_parts.append("History: Visited NASS and ERS (+25)")
        else:
            score += 15
            feedback_parts.append("History: Visited USDA pages but missed distinct NASS/ERS sources (+15)")
    elif usda_visits >= 1:
        score += 5
        feedback_parts.append("History: Minimal USDA visits (+5)")
    else:
        feedback_parts.append("History: No USDA visits found")

    # --- Criterion 2: Bookmarks (15 pts) ---
    folder_exists = task_stats.get("bookmark_folder_exists", False)
    usda_bms = task_stats.get("usda_bookmarks_count", 0)
    
    if folder_exists:
        if usda_bms >= 5:
            score += 15
            feedback_parts.append(f"Bookmarks: Folder created with {usda_bms} USDA links (+15)")
        elif usda_bms >= 1:
            score += 10
            feedback_parts.append(f"Bookmarks: Folder created but only {usda_bms} USDA links (need 5) (+10)")
        else:
            score += 5
            feedback_parts.append("Bookmarks: Folder created but empty/no USDA links (+5)")
    else:
        feedback_parts.append("Bookmarks: 'Crop Planning Research' folder not found")

    # --- Criterion 3: JSON File Validity (10 pts) ---
    if task_stats.get("file_exists") and task_stats.get("file_created_during_task"):
        if advisory_data:
            score += 10
            feedback_parts.append("Output: Valid JSON file created (+10)")
        else:
            score += 5
            feedback_parts.append("Output: File exists but invalid JSON (+5)")
    else:
        feedback_parts.append("Output: File not created or pre-existed")

    # --- Criterion 4: Data Plausibility (50 pts) ---
    # Only check if we have valid JSON data
    if advisory_data:
        ranges = task_info.get("metadata", {}).get("plausible_ranges", {})
        
        # Check Corn Data (20 pts)
        corn = advisory_data.get("corn", {})
        c_prod = float(corn.get("iowa_production_bushels_millions", 0))
        c_yield = float(corn.get("national_yield_bushels_per_acre", 0))
        c_price = float(corn.get("price_per_bushel_dollars", 0))
        
        c_ranges = ranges.get("corn", {})
        if c_ranges.get("iowa_production_min", 1500) <= c_prod <= c_ranges.get("iowa_production_max", 3000):
            score += 7
        if c_ranges.get("national_yield_min", 150) <= c_yield <= c_ranges.get("national_yield_max", 200):
            score += 7
        if c_ranges.get("price_min", 3.0) <= c_price <= c_ranges.get("price_max", 8.5):
            score += 6
            
        # Check Soybean Data (20 pts)
        soy = advisory_data.get("soybeans", {})
        s_prod = float(soy.get("iowa_production_bushels_millions", 0))
        s_yield = float(soy.get("national_yield_bushels_per_acre", 0))
        s_price = float(soy.get("price_per_bushel_dollars", 0))
        
        s_ranges = ranges.get("soybeans", {})
        if s_ranges.get("iowa_production_min", 350) <= s_prod <= s_ranges.get("iowa_production_max", 750):
            score += 7
        if s_ranges.get("national_yield_min", 40) <= s_yield <= s_ranges.get("national_yield_max", 60):
            score += 7
        if s_ranges.get("price_min", 8.0) <= s_price <= s_ranges.get("price_max", 18.0):
            score += 6
            
        # Check Recommendation (10 pts)
        rec = advisory_data.get("recommendation", "")
        if isinstance(rec, str) and len(rec) > 50 and "corn" in rec.lower() and "soy" in rec.lower():
            score += 10
            feedback_parts.append("Output: Detailed recommendation found (+10)")
        elif isinstance(rec, str) and len(rec) > 10:
            score += 5
            feedback_parts.append("Output: Brief recommendation found (+5)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }