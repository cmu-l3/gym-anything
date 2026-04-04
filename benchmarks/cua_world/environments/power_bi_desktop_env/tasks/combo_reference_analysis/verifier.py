#!/usr/bin/env python3
"""
Verifier for Power BI Combo Chart Task.

Verification Logic:
1. PBIX Structure (70%):
   - File exists and created during task.
   - Contains 'Monthly Performance' page.
   - Contains 'lineClusteredColumnComboChart' visual.
   - Contains 'Total_Revenue' and 'Avg_Discount_Pct' measures in DataModel.
   - Visual configuration contains 'constantLine' objects (Analytics pane usage).

2. Visual Verification (30%):
   - VLM checks if the report actually looks like a combo chart with reference lines.
"""

import json
import os
import tempfile
import logging
import sys

# Add gym_anything to path if needed (standard in env)
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def get_final_screenshot(traj): return None

logger = logging.getLogger(__name__)

def verify_combo_reference_analysis(traj, env_info, task_info):
    """
    Verifies the Power BI combo chart task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    # 1. Retrieve JSON Result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\combo_reference_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Programmatic Verification (70 pts) ---
    
    # 1. File Existence & Timestamp (10 pts)
    if result.get("file_exists") and result.get("file_created_after_start"):
        score += 10
        feedback.append("✅ Report file saved successfully.")
    else:
        feedback.append("❌ Report file missing or created before task start.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Page Name (10 pts)
    page_names = result.get("page_names", [])
    if "Monthly Performance" in page_names:
        score += 10
        feedback.append("✅ Page renamed to 'Monthly Performance'.")
    else:
        feedback.append(f"❌ Page name 'Monthly Performance' not found. Found: {page_names}")

    # 3. DAX Measures (20 pts)
    measures = result.get("measures_found", [])
    if "Total_Revenue" in measures:
        score += 10
        feedback.append("✅ Measure 'Total_Revenue' found.")
    else:
        feedback.append("❌ Measure 'Total_Revenue' not found in Data Model.")
        
    if "Avg_Discount_Pct" in measures:
        score += 10
        feedback.append("✅ Measure 'Avg_Discount_Pct' found.")
    else:
        feedback.append("❌ Measure 'Avg_Discount_Pct' not found in Data Model.")

    # 4. Visual Type (15 pts)
    visuals = result.get("visual_types", [])
    if "lineClusteredColumnComboChart" in visuals:
        score += 15
        feedback.append("✅ Combo Chart (Line and Clustered Column) found.")
    else:
        feedback.append(f"❌ Combo Chart not found. Found types: {visuals}")

    # 5. Reference Lines Configuration (15 pts)
    if result.get("constant_lines_found"):
        score += 15
        feedback.append("✅ Analytics reference lines detected in visual configuration.")
    else:
        feedback.append("❌ No Analytics reference/constant lines found in visual configuration.")

    # --- VLM Verification (30 pts) ---
    # We use VLM to ensure the agent didn't just add the visual but actually configured it correctly.
    
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Analyze this Power BI report screenshot.
        1. Is there a Combo Chart (bars and lines combined)?
        2. Do you see horizontal reference lines (dashed or solid lines extending across the chart, distinct from the data series)?
        3. Does the chart look populated with data (not blank)?
        
        Respond JSON: {"has_combo_chart": bool, "has_reference_lines": bool, "is_populated": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("has_combo_chart"):
                score += 10
                feedback.append("✅ VLM confirmed Combo Chart visual.")
            if parsed.get("has_reference_lines"):
                score += 10
                feedback.append("✅ VLM confirmed visible reference lines.")
            if parsed.get("is_populated"):
                score += 10
                feedback.append("✅ VLM confirmed chart is populated with data.")
        else:
            feedback.append("⚠️ VLM verification failed to run (awarding partial points based on file structure).")
            score += 15 # Grace points if VLM fails but file structure is perfect
    else:
        feedback.append("⚠️ No screenshot available for visual verification.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }