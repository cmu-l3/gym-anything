#!/usr/bin/env python3
"""
Verifier for payment_channel_analysis task.

Scoring (100 points total):
- File saved & valid (10 pts): Channel_Analysis.pbix exists and created during task.
- Page Name (15 pts): Page named "Channel Analysis".
- Combo Chart (20 pts): Visual type 'lineClusteredColumnComboChart' present.
- Treemap (15 pts): Visual type 'treemap' present.
- Calculated Column (20 pts): 'Revenue_Band' found in data model.
- Measure 1 (10 pts): 'Avg_Sale' found in data model.
- Measure 2 (10 pts): 'Order_Count' found in data model.

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_payment_channel_analysis(traj, env_info, task_info):
    """
    Verify the Power BI channel analysis task results.
    """
    # 1. Setup copying from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/channel_analysis_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve or parse result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not verify task: Result file missing or invalid. Did you save the report to the Desktop? Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass

    # 3. Calculate Score
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Exists & Timestamp (10 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 10
        feedback_parts.append("File saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp check failed (re-used old file?)")
    else:
        feedback_parts.append("Channel_Analysis.pbix not found on Desktop")
        # Fail early if file doesn't exist? No, let them get points for partial if verifier somehow runs.
        # But realistically, if file missing, everything else fails.
        return {"passed": False, "score": 0, "feedback": "Report file 'Channel_Analysis.pbix' not found on Desktop."}

    # Criterion 2: Page Name (15 pts)
    # Check if "Channel Analysis" is in the page names list (case insensitive)
    page_names = [p.lower() for p in result.get('page_names', [])]
    if "channel analysis" in page_names:
        score += 15
        feedback_parts.append("Page renamed correctly")
    else:
        feedback_parts.append(f"Page name 'Channel Analysis' not found (Found: {result.get('page_names')})")

    # Criterion 3: Combo Chart (20 pts)
    visuals = result.get('visual_types', [])
    if "lineClusteredColumnComboChart" in visuals:
        score += 20
        feedback_parts.append("Combo chart created")
    else:
        feedback_parts.append("Line and Clustered Column Chart not found")

    # Criterion 4: Treemap (15 pts)
    if "treemap" in visuals:
        score += 15
        feedback_parts.append("Treemap created")
    else:
        feedback_parts.append("Treemap not found")

    # Criterion 5: Revenue_Band Column (20 pts)
    if result.get('has_revenue_band'):
        score += 20
        feedback_parts.append("Revenue_Band column found")
    else:
        feedback_parts.append("Calculated column 'Revenue_Band' not found in model")

    # Criterion 6: Avg_Sale Measure (10 pts)
    if result.get('has_avg_sale'):
        score += 10
        feedback_parts.append("Avg_Sale measure found")
    else:
        feedback_parts.append("Measure 'Avg_Sale' not found")

    # Criterion 7: Order_Count Measure (10 pts)
    if result.get('has_order_count'):
        score += 10
        feedback_parts.append("Order_Count measure found")
    else:
        feedback_parts.append("Measure 'Order_Count' not found")

    # 4. Final Result
    passed = score >= 70
    feedback_str = ". ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }