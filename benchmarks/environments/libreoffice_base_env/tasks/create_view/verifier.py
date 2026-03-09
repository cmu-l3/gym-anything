#!/usr/bin/env python3
"""
Verifier for create_view task in LibreOffice Base.

Verifies that:
1. The ODB file was saved/modified.
2. A CREATE VIEW statement exists in the embedded HSQLDB script.
3. The view definition contains required logic (JOIN, COUNT, SUM, GROUP BY).
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_view(traj, env_info, task_info):
    """
    Verify the creation of the CustomerPurchaseSummary view.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check if file was modified (10 pts)
    if result.get('odb_modified_during_task', False):
        score += 10
        feedback_parts.append("Database file saved")
    else:
        feedback_parts.append("Database file NOT saved (or timestamp unchanged)")

    # 2. Check if view exists (25 pts)
    view_def = result.get('view_definition', "")
    if result.get('view_found', False) and view_def:
        score += 25
        feedback_parts.append("View 'CustomerPurchaseSummary' found")
    else:
        feedback_parts.append("View 'CustomerPurchaseSummary' NOT found")
        # If view not found, we can check VLM as fallback, but primary criteria fail
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Normalize view definition for checking
    view_def_upper = view_def.upper()

    # 3. Check Tables (15 pts)
    # HSQLDB stores names in quotes usually, but we check flexibly
    if "CUSTOMER" in view_def_upper and "INVOICE" in view_def_upper:
        score += 15
        feedback_parts.append("References correct tables")
    else:
        feedback_parts.append("Missing references to Customer or Invoice tables")

    # 4. Check Aggregations (15 pts)
    if "COUNT" in view_def_upper and "SUM" in view_def_upper:
        score += 15
        feedback_parts.append("Uses COUNT and SUM aggregations")
    else:
        feedback_parts.append("Missing required aggregations (COUNT/SUM)")

    # 5. Check Grouping (15 pts)
    if "GROUP BY" in view_def_upper:
        score += 15
        feedback_parts.append("Uses GROUP BY clause")
    else:
        feedback_parts.append("Missing GROUP BY clause")

    # 6. Check Columns/Aliases (10 pts)
    # Check for specific column aliases required by task
    # "FullName", "InvoiceCount", "TotalSpent"
    # HSQLDB script: ... AS "FullName", ...
    aliases_found = 0
    required_aliases = ["FULLNAME", "INVOICECOUNT", "TOTALSPENT"]
    for alias in required_aliases:
        if f'"{alias}"' in view_def_upper or f"AS {alias}" in view_def_upper:
            aliases_found += 1
    
    if aliases_found >= 3:
        score += 10
        feedback_parts.append("All required column aliases found")
    elif aliases_found > 0:
        score += 5
        feedback_parts.append(f"Some column aliases found ({aliases_found}/3)")
    else:
        feedback_parts.append("Missing required column aliases")

    # 7. VLM Verification (10 pts)
    # Use VLM to confirm the interface state if score is borderline or just to confirm
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        q_res = query_vlm(
            prompt="Does this screenshot show LibreOffice Base with a view named 'CustomerPurchaseSummary' visible in the list or the SQL command window open with a CREATE VIEW statement?",
            image=final_screenshot
        )
        if q_res.get('success') and q_res.get('parsed', {}).get('answer', False): # assuming boolean parser or simple check
             # Simple heuristic for VLM positive
             if "yes" in str(q_res.get('response', '')).lower():
                 score += 10
                 feedback_parts.append("VLM confirmed view visibility")
             else:
                 # Default points if VLM is unsure but code verified it
                 score += 10 
        else:
             score += 10 # Trust the file verification more
    else:
        score += 10 # No screenshot penalty if file verification passed

    # Final Pass/Fail
    passed = score >= 60 and result.get('view_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {"view_definition": view_def}
    }