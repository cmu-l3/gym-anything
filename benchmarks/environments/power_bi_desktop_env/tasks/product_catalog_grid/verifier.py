#!/usr/bin/env python3
"""
Verifier for product_catalog_grid task.

Scoring (100 points total):
- File saved (10 pts)
- Data Model Relationship (10 pts) - Inferred if measures work or checked via schema
- Measure 'Total_Revenue' (10 pts)
- Data Category 'Image URL' (15 pts)
- Data Category 'Web URL' (15 pts)
- Matrix Visual Present (10 pts)
- Sparkline Configured (20 pts)
- URL Icon Enabled (10 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_product_catalog_grid(traj, env_info, task_info):
    """Verify the Power BI Product Catalog task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from the Windows VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Path inside the VM (Windows path)
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File 'Product_Catalog.pbix' saved successfully.")
    else:
        feedback.append("File not saved or not created during task.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Measure Created (10 pts)
    measures = result.get("measures_found", [])
    if "Total_Revenue" in measures:
        score += 10
        feedback.append("Measure 'Total_Revenue' found.")
    else:
        feedback.append("Measure 'Total_Revenue' NOT found.")

    # 3. Data Categories (30 pts total)
    cats = result.get("columns_data_category", {})
    
    # Image URL
    img_cat = cats.get("Image_URL")
    if img_cat == "ImageUrl":
        score += 15
        feedback.append("Column 'Image_URL' correctly categorized.")
    else:
        feedback.append(f"Column 'Image_URL' category incorrect or missing (found: {img_cat}).")
        
    # Web URL
    web_cat = cats.get("Product_Page_URL")
    if web_cat == "WebUrl":
        score += 15
        feedback.append("Column 'Product_Page_URL' correctly categorized.")
    else:
        feedback.append(f"Column 'Product_Page_URL' category incorrect or missing (found: {web_cat}).")

    # 4. Matrix Visual (10 pts)
    v_types = result.get("visual_types", [])
    if "pivotTable" in v_types or "matrix" in v_types:
        score += 10
        feedback.append("Matrix visual found.")
    else:
        feedback.append("No Matrix visual found.")

    # 5. Sparklines (20 pts)
    if result.get("sparklines_found"):
        score += 20
        feedback.append("Sparklines configured in visual.")
    else:
        feedback.append("Sparklines NOT detected in visual configuration.")

    # 6. URL Icon (10 pts)
    if result.get("url_icon_enabled"):
        score += 10
        feedback.append("URL Icons enabled.")
    else:
        feedback.append("URL Icons NOT enabled.")

    # 7. Relationship (10 pts)
    # We infer this from the presence of a valid data model schema and measures
    # Or strict check if we added logic in export_result (not currently explicit, giving benefit if model is valid)
    if result.get("data_model_valid"):
        score += 10
        feedback.append("Data model schema is valid.")
    else:
        feedback.append("Data model schema could not be validated.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }