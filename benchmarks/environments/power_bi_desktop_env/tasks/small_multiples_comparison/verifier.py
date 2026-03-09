#!/usr/bin/env python3
"""
Verifier for small_multiples_comparison task.

Scoring (100 points total):
- File saved (15 pts)
- Page name "Category Comparison" (15 pts)
- Line Chart present (15 pts)
- Clustered Bar Chart present (15 pts)
- Product_Category bound to visual (10 pts)
- Customer_Type bound to visual (10 pts)
- Avg_Sale_Value measure in model (20 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_small_multiples_comparison(traj, env_info, task_info):
    """Verify Power BI report for small multiples visuals and DAX measure."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # Note: Path must match what is generated in export_result.ps1
        copy_from_env("C:/Users/Docker/Desktop/small_multiples_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse verification result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass

    score = 0
    feedback_parts = []
    
    # 1. File Saved (15 pts)
    file_exists = result.get('file_exists', False)
    file_fresh = result.get('file_created_during_task', False)
    file_size = result.get('file_size_bytes', 0)
    
    if file_exists and file_fresh and file_size > 5000:
        score += 15
        feedback_parts.append("File saved successfully")
    elif file_exists:
        # Penalty if it existed before or is empty, but give some points if valid
        score += 5
        feedback_parts.append("File exists but timestamp/size check warning")
    else:
        feedback_parts.append("File 'Small_Multiples_Report.pbix' not found")

    # 2. Page Name (15 pts)
    page_names = result.get('page_names', [])
    # Case insensitive check
    if any("category comparison" in str(p).lower() for p in page_names):
        score += 15
        feedback_parts.append("Page 'Category Comparison' found")
    else:
        feedback_parts.append(f"Page 'Category Comparison' missing (Found: {page_names})")

    # 3. Visual Types (30 pts total)
    visual_types = [str(v).lower() for v in result.get('visual_types', [])]
    
    # Line Chart
    if 'linechart' in visual_types:
        score += 15
        feedback_parts.append("Line Chart found")
    else:
        feedback_parts.append("Line Chart missing")
        
    # Clustered Bar Chart
    if any(x in visual_types for x in ['clusteredbarchart', 'clusteredcolumnchart', 'bar', 'column']):
        score += 15
        feedback_parts.append("Clustered Bar Chart found")
    else:
        feedback_parts.append("Clustered Bar Chart missing")

    # 4. Small Multiples Field Bindings (20 pts total)
    # The export script checks raw JSON config for these strings
    if result.get('config_has_product_cat', False):
        score += 10
        feedback_parts.append("Product_Category field bound")
    else:
        feedback_parts.append("Product_Category not found in visual config")
        
    if result.get('config_has_customer_type', False):
        score += 10
        feedback_parts.append("Customer_Type field bound")
    else:
        feedback_parts.append("Customer_Type not found in visual config")

    # 5. DAX Measure (20 pts)
    if result.get('model_has_measure', False):
        score += 20
        feedback_parts.append("DAX measure 'Avg_Sale_Value' found")
    else:
        feedback_parts.append("DAX measure 'Avg_Sale_Value' NOT found in model")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }