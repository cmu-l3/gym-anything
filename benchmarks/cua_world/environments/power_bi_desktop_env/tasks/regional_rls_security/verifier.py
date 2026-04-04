#!/usr/bin/env python3
"""
Verifier for regional_rls_security task.

Scoring (100 points total):
- File Saved (10 pts): Exists and created during task.
- RLS Roles (40 pts): 10 pts for each correct role name found in DataModel.
- RLS Filter Logic (10 pts): 'Region' column referenced in model (proxy for filter logic).
- Measure Created (10 pts): 'Total_Sales' found in model.
- Page Name (10 pts): 'Sales Summary' page exists.
- Visuals (20 pts): Clustered Column Chart (10) and Table (10) present.

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_regional_rls_security(traj, env_info, task_info):
    """Verify RLS configuration and report creation in Power BI."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/rls_result.json", temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Saved (10 pts) ---
    if result.get('file_exists') and result.get('created_after_start'):
        score += 10
        feedback_parts.append("File saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File saved but timestamp verification failed (pre-existing?)")
    else:
        feedback_parts.append("Regional_RLS_Report.pbix not found")

    # --- Criterion 2: RLS Roles (40 pts) ---
    found_roles = result.get('roles_found', [])
    required_roles = ["North_Manager", "South_Manager", "East_Manager", "West_Manager"]
    roles_score = 0
    for role in required_roles:
        if role in found_roles:
            roles_score += 10
    
    score += roles_score
    if roles_score == 40:
        feedback_parts.append("All 4 RLS roles created")
    else:
        feedback_parts.append(f"RLS roles found: {len(found_roles)}/4 ({', '.join(found_roles)})")

    # --- Criterion 3: Filter Logic Proxy (10 pts) ---
    # We check if 'Region' is referenced in the model binary near roles.
    # The export script sets 'region_filter_ref' if it finds 'Region' string.
    if result.get('region_filter_ref'):
        score += 10
        feedback_parts.append("Region column referenced in model")
    else:
        feedback_parts.append("Region column reference not found in model")

    # --- Criterion 4: Measure Created (10 pts) ---
    found_measures = result.get('measures_found', [])
    if "Total_Sales" in found_measures:
        score += 10
        feedback_parts.append("Total_Sales measure found")
    else:
        feedback_parts.append("Total_Sales measure missing")

    # --- Criterion 5: Page Name (10 pts) ---
    page_names = result.get('page_names', [])
    if "Sales Summary" in page_names:
        score += 10
        feedback_parts.append("Sales Summary page found")
    else:
        feedback_parts.append(f"Page 'Sales Summary' missing (Found: {page_names})")

    # --- Criterion 6: Visuals (20 pts) ---
    visual_types = result.get('visual_types', [])
    
    # Clustered Column Chart
    has_chart = any(v for v in visual_types if 'clusteredColumnChart' in v or 'ColumnChart' in v)
    if has_chart:
        score += 10
        feedback_parts.append("Column chart present")
    else:
        feedback_parts.append("Column chart missing")

    # Table
    has_table = any(v for v in visual_types if 'tableEx' in v or 'pivotTable' in v)
    if has_table:
        score += 10
        feedback_parts.append("Table visual present")
    else:
        feedback_parts.append("Table visual missing")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }