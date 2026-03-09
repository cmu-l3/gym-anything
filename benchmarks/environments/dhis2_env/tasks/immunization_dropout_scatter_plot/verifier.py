#!/usr/bin/env python3
"""
Verifier for immunization_dropout_scatter_plot@1

Criteria:
1. Visualization Created (20pts)
2. Type is SCATTER (20pts)
3. Data Items (Penta 1 & 3) (15pts)
4. Org Units (District) (15pts)
5. Public Access (Can View) (15pts)
6. Data Exported (CSV) (15pts)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_immunization_dropout_scatter_plot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # Unpack API Analysis
    api_analysis = result.get("api_analysis", {})
    viz_data = api_analysis.get("viz_data", {})
    new_viz_count = api_analysis.get("new_viz_count", 0)
    viz_found = api_analysis.get("found", False)

    # Criterion 1: Visualization Created (20 pts)
    # Check if a specific target was found OR if the total count increased
    if viz_found or new_viz_count > 0:
        score += 20
        feedback.append("Visualization created (+20)")
    else:
        feedback.append("No new visualization found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback)}

    # Criterion 2: Correct Type (SCATTER) (20 pts)
    # If we found the specific viz, check its type. If not, we only have generic count.
    actual_type = viz_data.get("type", "UNKNOWN")
    if actual_type == "SCATTER":
        score += 20
        feedback.append("Correct type: SCATTER (+20)")
    else:
        feedback.append(f"Incorrect type: {actual_type} (Expected SCATTER)")

    # Criterion 3: Correct Data Items (15 pts)
    # Need Penta 1 and Penta 3. In DHIS2 dimensions, these are usually in 'columns' or 'rows'
    # We look for keywords in the 'items' list of dimensions
    if viz_found:
        dims = viz_data.get("columns", []) + viz_data.get("rows", []) + viz_data.get("filters", [])
        data_items = []
        for d in dims:
            if d.get("dimension") == "dx": # dx is Data dimension
                for item in d.get("items", []):
                    data_items.append(item.get("displayName", "").lower())
        
        has_penta1 = any("penta" in i and "1" in i for i in data_items) or any("pentavalent" in i and "1" in i for i in data_items)
        has_penta3 = any("penta" in i and "3" in i for i in data_items) or any("pentavalent" in i and "3" in i for i in data_items)
        
        if has_penta1 and has_penta3:
            score += 15
            feedback.append("Data items correct (Penta 1 & 3) (+15)")
        elif has_penta1 or has_penta3:
            score += 7
            feedback.append("Partially correct data items (+7)")
        else:
            feedback.append("Missing Penta 1/3 data items")
    else:
        feedback.append("Cannot verify data items (Target viz not identified)")

    # Criterion 4: Correct Org Units (15 pts)
    # Check for District level configuration
    if viz_found:
        ou_configured = False
        dims = viz_data.get("columns", []) + viz_data.get("rows", []) + viz_data.get("filters", [])
        for d in dims:
            if d.get("dimension") == "ou": # ou is Org Unit dimension
                # Look for LEVELS-2 (District in Sierra Leone usually level 2 or 3 depending on setup, but mostly we look for 'LEVEL-' keyword or explicit units)
                # The API returns items like "LEVEL-2" or specific unit IDs
                items_str = str(d.get("items", []))
                if "LEVEL-" in items_str or "District" in items_str:
                    ou_configured = True
        
        if ou_configured:
            score += 15
            feedback.append("Org Units configured (+15)")
        else:
            feedback.append("Org Unit configuration unclear")

    # Criterion 5: Public Access (15 pts)
    # Expected: "r-------" (Can view) or "r-r-----" etc.
    if viz_found:
        access = viz_data.get("publicAccess", "")
        if access.startswith("r"):
            score += 15
            feedback.append(f"Public access enabled ({access}) (+15)")
        else:
            feedback.append(f"Public access not enabled ({access})")

    # Criterion 6: Data Exported (15 pts)
    downloads = result.get("downloads", [])
    has_csv = any(f["ext"] == ".csv" for f in downloads)
    has_xls = any(f["ext"] in [".xls", ".xlsx"] for f in downloads)
    
    if has_csv:
        score += 15
        feedback.append("CSV exported (+15)")
    elif has_xls:
        score += 10
        feedback.append("Excel exported instead of CSV (+10)")
    else:
        feedback.append("No export file found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }