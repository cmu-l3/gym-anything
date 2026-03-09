#!/usr/bin/env python3
"""
Verifier for churn_key_influencers task.

Scoring (100 points total):
- File saved & valid (10 pts)
- Page name "Churn Drivers" (10 pts)
- Key Influencers visual (keyDrivers) present (25 pts)
- Key Influencers configured for Churn (10 pts)
- Card visuals present (>=2) (10 pts)
- DAX Measure: Total_Customers (15 pts)
- DAX Measure: Churn_Rate (15 pts)
- File created during task (5 pts)

Pass threshold: 65 points (Must include Key Influencers visual)
"""

import json
import os
import tempfile
import logging
import time

logger = logging.getLogger(__name__)

def verify_churn_key_influencers(traj, env_info, task_info):
    """
    Verify the Power BI Churn Analysis task.
    Uses result JSON exported from the Windows VM.
    """
    
    # 1. Setup and retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Copy result from Windows desktop
        copy_from_env("C:/Users/Docker/Desktop/churn_analysis_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not verify task results. Did the report save successfully? Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Validity (10 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 50000: # 50KB min
        score += 10
        feedback_parts.append("Report saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("Report saved but file size is suspiciously small")
    else:
        feedback_parts.append("Report file not found")

    # Criterion 2: Freshness (5 pts)
    if result.get('file_fresh'):
        score += 5
    else:
        feedback_parts.append("File timestamp check failed (was it created before task?)")

    # Criterion 3: Page Name (10 pts)
    page_names = [n.lower() for n in result.get('page_names', [])]
    if "churn drivers" in page_names:
        score += 10
        feedback_parts.append("Page renamed to 'Churn Drivers'")
    else:
        feedback_parts.append(f"Page name incorrect. Found: {result.get('page_names')}")

    # Criterion 4: Key Influencers Visual (25 pts)
    # The visualType is 'keyDrivers'
    visual_types = result.get('visual_types', [])
    has_key_drivers = result.get('key_influencers_found', False)
    
    if has_key_drivers:
        score += 25
        feedback_parts.append("Key Influencers visual added")
    else:
        feedback_parts.append("Key Influencers visual NOT found")

    # Criterion 5: Key Influencers Configuration (10 pts)
    # We check if the extraction script found evidence of "Churn" being used in that visual
    full_layout = result.get('full_layout_search', '')
    if "keyDrivers_churn_configured" in full_layout or ("keyDrivers" in full_layout and "Churn" in full_layout):
        score += 10
        feedback_parts.append("Key Influencers configured for Churn analysis")
    elif has_key_drivers:
        feedback_parts.append("Key Influencers visual empty/unconfigured")

    # Criterion 6: Card Visuals (10 pts)
    card_count = result.get('card_count', 0)
    if card_count >= 2:
        score += 10
        feedback_parts.append(f"Found {card_count} KPI Cards")
    elif card_count == 1:
        score += 5
        feedback_parts.append("Found 1 KPI Card (expected 2)")
    else:
        feedback_parts.append("KPI Cards missing")

    # Criterion 7: DAX Measures (30 pts total)
    measures = result.get('model_measures_found', [])
    if "Total_Customers" in measures:
        score += 15
        feedback_parts.append("Measure 'Total_Customers' found")
    else:
        feedback_parts.append("Measure 'Total_Customers' missing")

    if "Churn_Rate" in measures:
        score += 15
        feedback_parts.append("Measure 'Churn_Rate' found")
    else:
        feedback_parts.append("Measure 'Churn_Rate' missing")

    # 3. Final Determination
    # Pass threshold: 65 pts. Critical: Must have the AI visual.
    passed = (score >= 65) and has_key_drivers

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }