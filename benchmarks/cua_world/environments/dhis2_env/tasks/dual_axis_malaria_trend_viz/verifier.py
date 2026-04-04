#!/usr/bin/env python3
"""
Verifier for Dual Axis Malaria Trend Visualization Task.

Scoring Criteria (100 pts total):
1. Visualization Saved (25 pts): Visualization with correct name exists in DHIS2.
2. Correct Data Selected (20 pts): Contains both "Malaria RDTs performed" (or similar) AND "Positivity rate".
3. Dual Axis Configured (30 pts): One series is assigned to axis 1 (secondary) or axes config shows dual.
4. Mixed Chart Types (15 pts): Visualization type implies combination or series overrides set to LINE/COLUMN.
5. Image Exported (10 pts): Valid PNG file exists on desktop created during task.

Pass Threshold: 75 pts (Must have dual axis configured).
"""

import json
import os
import logging
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def verify_dual_axis_malaria_trend_viz(traj, env_info, task_info):
    """
    Verifies the task using the exported JSON result.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load Result JSON from Container
    import tempfile
    local_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    try:
        copy_from_env("/tmp/task_result.json", local_temp)
        with open(local_temp, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(local_temp):
            os.unlink(local_temp)

    score = 0
    feedback = []
    
    # --- Check 1: Image Export (10 pts) ---
    if result.get("file_exists") and result.get("file_created_after_start"):
        # Check size (sanity check for empty file)
        if result.get("file_size", 0) > 1000:
            score += 10
            feedback.append("Image exported successfully (+10).")
        else:
            feedback.append("Image exported but file is too small/empty.")
    else:
        feedback.append("Chart image not found on Desktop or not created during task.")

    # --- Check 2: Visualization Existence (25 pts) ---
    viz_list = result.get("viz_api_response", {}).get("visualizations", [])
    
    if not viz_list:
        return {
            "passed": False,
            "score": score,
            "feedback": "No visualization named 'Bo Malaria Testing vs Positivity 2024' found in DHIS2. " + " ".join(feedback)
        }
    
    # Analyze the first match
    viz = viz_list[0]
    score += 25
    feedback.append("Visualization saved in DHIS2 (+25).")

    # --- Check 3: Correct Data Items (20 pts) ---
    # We look in dataDimensionItems or columns/rows for specific keywords
    # Keywords: "RDTs performed" (count) and "positivity rate" (indicator)
    data_items = viz.get("dataDimensionItems", [])
    
    has_volume = False
    has_rate = False
    
    # Helper to check item names
    def check_item(item):
        name = ""
        if "indicator" in item:
            name = item["indicator"].get("displayName", "")
        elif "dataElement" in item:
            name = item["dataElement"].get("displayName", "")
        
        name_lower = name.lower()
        is_vol = "rdt" in name_lower and ("performed" in name_lower or "tests" in name_lower or "done" in name_lower)
        is_rate = "positivity" in name_lower or "rate" in name_lower or "%" in name_lower
        return is_vol, is_rate

    for item in data_items:
        v, r = check_item(item)
        if v: has_volume = True
        if r: has_rate = True

    if has_volume and has_rate:
        score += 20
        feedback.append("Correct data items selected (Test Volume + Positivity Rate) (+20).")
    else:
        feedback.append(f"Data items check partial: Volume={has_volume}, Rate={has_rate}. Need both 'RDTs performed' and 'Positivity rate'.")
        if has_volume or has_rate:
            score += 10

    # --- Check 4: Dual Axis Configuration (30 pts) ---
    # In DHIS2, dual axis is typically indicated by:
    # 1. 'series' array containing items with 'axis': 1
    # 2. 'axes' array having specific configs
    # 3. 'type' might change to 'STACKED_COLUMN' etc., but axis is key.
    
    is_dual_axis = False
    
    # Method A: Check 'series' overrides
    series = viz.get("series", [])
    for s in series:
        if s.get("axis") == 1:
            is_dual_axis = True
            break
            
    # Method B: Check if specific data items are assigned to axes in some versions
    # Method C: Check 'optionalAxes' (older versions) or specific axis flags
    
    if is_dual_axis:
        score += 30
        feedback.append("Dual axis configured correctly (+30).")
    else:
        feedback.append("Dual axis NOT detected. One series must be assigned to the secondary axis (Axis 2).")

    # --- Check 5: Mixed Chart Types (15 pts) ---
    # We want a combo chart (e.g. Column + Line)
    # The visualization 'type' might be 'COLUMN' but with a series override to 'LINE'
    
    is_mixed_type = False
    base_type = viz.get("type", "")
    
    has_line_override = False
    has_column_override = False
    
    for s in series:
        stype = s.get("type", "")
        if stype == "LINE": has_line_override = True
        if stype == "COLUMN" or stype == "BAR": has_column_override = True
        
    # Valid combos: 
    # 1. Base=COLUMN/BAR and has LINE override
    # 2. Base=LINE and has COLUMN/BAR override
    # 3. Explicit combined types (less common in standard API responses, usually implied)
    
    if "COLUMN" in base_type or "BAR" in base_type:
        if has_line_override:
            is_mixed_type = True
    elif "LINE" in base_type:
        if has_column_override:
            is_mixed_type = True
            
    if is_mixed_type:
        score += 15
        feedback.append("Mixed chart types (Column + Line) configured (+15).")
    else:
        feedback.append("Chart does not appear to mix Column and Line types.")
        # Partial credit if dual axis was achieved but type mixing wasn't detected strictly
        if is_dual_axis:
            score += 5 

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }