#!/usr/bin/env python3
"""
Verifier for customer_retention_segmentation task.

Scoring (100 points total):
- Report Saved (10 pts): Customer_Retention.pbix exists and modified during task.
- Calculated Table (20 pts): 'Customer_Profiles' found in data model.
- Recency Logic (20 pts): 'Recency_Days' column found.
- Segmentation Logic (20 pts): 'Status' column found.
- Visuals (10 pts): Donut chart and Table visual present.
- Export Accuracy (20 pts): CSV exists, has data, and only contains 'Lost' customers (Recency > 270).

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_customer_retention(traj, env_info, task_info):
    """
    Verify the customer retention task by analyzing the results exported from the Windows environment.
    """
    
    # 1. Setup: Retrieve result file using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Path inside the Windows VM
        vm_result_path = "C:/Users/Docker/Desktop/customer_retention_result.json"
        copy_from_env(vm_result_path, temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results. Did you run the export script?"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # A. File Existence (10 pts)
    if result.get('pbix_exists') and result.get('created_during_task'):
        score += 10
        feedback.append("✅ PBIX report saved.")
    elif result.get('pbix_exists'):
        score += 5
        feedback.append("⚠️ PBIX report exists but timestamp is old.")
    else:
        feedback.append("❌ PBIX report not found.")

    # B. Calculated Table (20 pts)
    if result.get('has_customer_profiles_table'):
        score += 20
        feedback.append("✅ Calculated Table 'Customer_Profiles' detected.")
    else:
        feedback.append("❌ 'Customer_Profiles' table not found in data model.")

    # C. Recency Logic (20 pts)
    if result.get('has_recency_column'):
        score += 20
        feedback.append("✅ 'Recency_Days' column detected.")
    else:
        feedback.append("❌ 'Recency_Days' column not found.")

    # D. Segmentation Logic (20 pts)
    if result.get('has_status_column'):
        score += 20
        feedback.append("✅ 'Status' column detected.")
    else:
        feedback.append("❌ 'Status' column not found.")

    # E. Visuals (10 pts)
    visuals_ok = result.get('has_donut_visual') and result.get('has_table_visual')
    if visuals_ok:
        score += 10
        feedback.append("✅ Required visuals (Donut + Table) detected.")
    elif result.get('has_donut_visual') or result.get('has_table_visual'):
        score += 5
        feedback.append("⚠️ Some visuals missing.")
    else:
        feedback.append("❌ No required visuals detected.")

    # F. Export Accuracy (20 pts)
    if result.get('csv_exists'):
        row_count = result.get('csv_row_count', 0)
        logic_correct = result.get('csv_logic_correct', False)
        
        if row_count > 0:
            if logic_correct:
                score += 20
                feedback.append(f"✅ Exported CSV valid ({row_count} rows) and filter logic appears correct.")
            else:
                score += 10
                feedback.append("⚠️ Exported CSV exists but contains customers with Recency <= 270 (Filter not applied correctly).")
        else:
            score += 5
            feedback.append("⚠️ Exported CSV is empty.")
    else:
        feedback.append("❌ 'lost_customers.csv' export not found.")

    # 3. Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }