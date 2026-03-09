#!/usr/bin/env python3
"""
Verifier for custom_tooltip_report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_tooltip_report(traj, env_info, task_info):
    """
    Verify the Power BI tooltip report task.
    
    Criteria:
    1. File 'Tooltip_Report.pbix' created.
    2. Two pages exist: "Sales Overview" and "Category Detail".
    3. "Category Detail" page has tooltip dimensions (approx 320x240).
    4. "Sales Overview" has Clustered Column and Line charts.
    5. "Category Detail" has Card and Stacked Bar charts.
    6. "Avg_Unit_Price" measure exists in the model.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy function not available"}

    # Retrieve result JSON from the Windows environment
    # Note: Path separator logic might be needed if host is Linux, but copy_from_env source path is in the container (Windows)
    # The container path is C:\Users\Docker\Desktop\tooltip_result.json
    # Standard format for copy_from_env typically handles the OS difference or expects unix-style for linux containers
    # For Windows container, we usually use forward slashes or escaped backslashes
    
    remote_path = "C:/Users/Docker/Desktop/tooltip_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env(remote_path, temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not verify: Result file not found or copy failed."}

    try:
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get("file_exists") and result.get("file_created_after_start"):
        score += 10
        feedback.append("File 'Tooltip_Report.pbix' saved successfully.")
    else:
        feedback.append("File 'Tooltip_Report.pbix' not found or was not created during this session.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Parse pages
    pages = result.get("pages", [])
    page_names = [p.get("name", "") for p in pages]
    
    # 2. Page Existence (20 pts)
    overview_page = next((p for p in pages if "Sales Overview" in p.get("name", "")), None)
    detail_page = next((p for p in pages if "Category Detail" in p.get("name", "")), None)
    
    if overview_page:
        score += 10
        feedback.append("'Sales Overview' page found.")
    else:
        feedback.append("'Sales Overview' page missing.")
        
    if detail_page:
        score += 10
        feedback.append("'Category Detail' page found.")
    else:
        feedback.append("'Category Detail' page missing.")

    # 3. Tooltip Page Sizing (20 pts)
    # Standard tooltip size is usually 320x240, but definitely small (<500px width)
    if detail_page:
        width = detail_page.get("width", 1280)
        height = detail_page.get("height", 720)
        if width < 500 and height < 500:
            score += 20
            feedback.append("Tooltip page sizing is correct.")
        else:
            feedback.append(f"Tooltip page sizing incorrect (found {width}x{height}, expected small format).")
    
    # 4. Visuals on Page 1 (15 pts)
    if overview_page:
        vtypes = [v.lower() for v in overview_page.get("visual_types", [])]
        has_col = any("clusteredcolumn" in v or "column" in v for v in vtypes)
        has_line = any("line" in v for v in vtypes)
        
        if has_col and has_line:
            score += 15
            feedback.append("Overview page visuals correct.")
        elif has_col or has_line:
            score += 7
            feedback.append("Overview page missing one required visual.")
        else:
            feedback.append("Overview page visuals missing.")

    # 5. Visuals on Page 2 (15 pts)
    if detail_page:
        vtypes = [v.lower() for v in detail_page.get("visual_types", [])]
        card_count = sum(1 for v in vtypes if "card" in v)
        has_bar = any("bar" in v or "stacked" in v for v in vtypes)
        
        if card_count >= 1 and has_bar:
            score += 15
            feedback.append("Category Detail visuals correct.")
        else:
            feedback.append(f"Category Detail visuals incomplete (Found {card_count} cards, Bar chart: {has_bar}).")

    # 6. DAX Measure (20 pts)
    if result.get("model_contains_measure"):
        score += 20
        feedback.append("DAX measure 'Avg_Unit_Price' found.")
    else:
        feedback.append("DAX measure 'Avg_Unit_Price' not found in data model.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }