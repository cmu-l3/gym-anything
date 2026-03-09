#!/usr/bin/env python3
"""
Verifier for customer_rank_tiering@1.

Scoring System (100 points total):
1. File Saved (10 pts): Product_Tier_Report.pbix exists and is fresh.
2. Calculated Columns (25 pts): 'Product_Rank' and 'Performance_Tier' found in model.
3. Measures (15 pts): 'Tier_Revenue' found in model.
4. Visual 1 (20 pts): 100% Stacked Bar Chart present.
5. Visual 2 (15 pts): Multi-Row Card present.
6. Visual 3 (15 pts): Table visual present.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_customer_rank_tiering(traj, env_info, task_info):
    """
    Verifies the Power BI Product Tiering task by inspecting the JSON result
    exported from the Windows environment.
    """
    # 1. Setup access to file from VM
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    # Define remote path (Windows path inside VM)
    remote_path = "C:/Users/Docker/Desktop/task_result.json"
    
    try:
        copy_from_env(remote_path, temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not verify result: Output file not found on desktop."
        }

    # 2. Parse Results
    try:
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Corrupt result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: File Saved (10 pts)
    if result.get('file_exists') and result.get('file_saved_after_start'):
        score += 10
        feedback.append("✅ Report file saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("⚠️ Report file exists but timestamp is old (pre-task?).")
    else:
        feedback.append("❌ Report file 'Product_Tier_Report.pbix' not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: Calculated Columns (25 pts)
    if result.get('calculated_columns_found'):
        score += 25
        feedback.append("✅ Calculated columns 'Product_Rank' and 'Performance_Tier' found.")
    else:
        # Partial credit
        if result.get('rank_col_name'):
            score += 10
            feedback.append("⚠️ 'Product_Rank' found, but 'Performance_Tier' missing.")
        elif result.get('tier_col_name'):
            score += 10
            feedback.append("⚠️ 'Performance_Tier' found, but 'Product_Rank' missing.")
        else:
            feedback.append("❌ Required calculated columns not found in Data Model.")

    # Criterion 3: Measures (15 pts)
    if result.get('measures_found'):
        score += 15
        feedback.append("✅ DAX Measures found.")
    else:
        feedback.append("❌ Measure 'Tier_Revenue' not found in Data Model.")

    # Criterion 4: 100% Stacked Bar Chart (20 pts)
    if result.get('chart_visual_found'):
        score += 20
        feedback.append("✅ 100% Stacked Bar Chart visual present.")
    else:
        feedback.append("❌ 100% Stacked Bar Chart not found.")

    # Criterion 5: Multi-Row Card (15 pts)
    if result.get('card_visual_found'):
        score += 15
        feedback.append("✅ Multi-Row Card visual present.")
    else:
        feedback.append("❌ Multi-Row Card not found.")

    # Criterion 6: Table Visual (15 pts)
    if result.get('table_visual_found'):
        score += 15
        feedback.append("✅ Table visual present.")
    else:
        feedback.append("❌ Table visual not found.")

    # 4. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }