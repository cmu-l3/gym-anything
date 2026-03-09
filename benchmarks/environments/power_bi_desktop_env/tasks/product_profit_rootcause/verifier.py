#!/usr/bin/env python3
"""
Verifier for product_profit_rootcause task.

Scoring (100 points total):
- Report file saved (10 pts)
- Power Query Merge Logic (25 pts): Checks for 'Table.NestedJoin'
- Two Sources Referenced (10 pts): Checks for filenames in M code
- DAX Measure 'Total_Profit' (20 pts): Checks DataModel
- Decomposition Tree Visual (25 pts): Checks for 'decompositionTreeMap'
- Card Visual (10 pts): Checks for 'card'

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_profit_rootcause(traj, env_info, task_info):
    """
    Verify the Power BI Root Cause Analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Use a safe temporary file path
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Copy the result JSON file from the Windows VM
        # Note: The export script saves to C:\\Users\\Docker\\Desktop\\rootcause_result.json
        # path conversion might be needed depending on how the Docker cp works, 
        # usually defaults to unix style paths for the container API
        copy_from_env("C:/Users/Docker/Desktop/rootcause_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve verification results. Did the agent run the export script? Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Logic
    score = 0
    feedback = []
    
    # 1. File Saved (10 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 10
        feedback.append("File 'Profit_RootCause.pbix' saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("File exists but timestamp verification failed (possible pre-existing file).")
    else:
        feedback.append("Target file 'Profit_RootCause.pbix' not found.")

    # 2. Power Query Merge (25 pts)
    # The export script greps DataMashup binary for 'Table.NestedJoin'
    if result.get('pq_merge_found'):
        score += 25
        feedback.append("Power Query Merge operation detected (Table.NestedJoin/Table.Join found).")
    else:
        feedback.append("No Merge operation detected in Power Query (Table.NestedJoin missing).")

    # 3. Sources Referenced (10 pts)
    if result.get('pq_sources_found'):
        score += 10
        feedback.append("Both source tables (orders, products) referenced in M code.")
    else:
        feedback.append("One or both source tables not found in M code.")

    # 4. DAX Measure (20 pts)
    if result.get('measure_found'):
        score += 20
        feedback.append("DAX Measure 'Total_Profit' found in Data Model.")
    else:
        feedback.append("Measure 'Total_Profit' not found in Data Model.")

    # 5. Visuals (35 pts)
    visuals_found = result.get('visual_types', [])
    
    if result.get('visual_tree_found'):
        score += 25
        feedback.append("Decomposition Tree visual found.")
    else:
        feedback.append(f"Decomposition Tree visual missing. Found: {visuals_found}")
        
    if result.get('visual_card_found'):
        score += 10
        feedback.append("Card visual found.")
    else:
        feedback.append("Card visual missing.")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }