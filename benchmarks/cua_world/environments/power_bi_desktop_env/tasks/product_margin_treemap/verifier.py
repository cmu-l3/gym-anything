#!/usr/bin/env python3
"""
Verifier for product_margin_treemap task.

Scoring (100 points total):
- File saved (10 pts): Product_Margin_Analysis.pbix exists
- Treemap visual (15 pts): 'treemap' visual type found
- Multi-row Card (15 pts): 'multiRowCard' visual type found
- Funnel Chart (15 pts): 'funnel' visual type found
- Page Name (10 pts): "Product Portfolio" found
- Measures (20 pts): 'Total_Profit' and 'Margin_Pct' in DataModel
- Calculated Column (15 pts): 'Profit_Tier' in DataModel

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_product_margin_treemap(traj, env_info, task_info):
    """Verify the Power BI report structure and model."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/treemap_result.json", temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (10 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 10
        feedback_parts.append("File saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp check failed (possible pre-existing file)")
    else:
        feedback_parts.append("Product_Margin_Analysis.pbix not found")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Visuals (45 pts total)
    visuals = result.get('visual_types', [])
    # Clean and lowercase for matching
    visuals_lower = [v.lower() for v in visuals]
    
    if 'treemap' in visuals_lower:
        score += 15
        feedback_parts.append("Treemap present")
    else:
        feedback_parts.append("Treemap missing")

    if 'multirowcard' in visuals_lower:
        score += 15
        feedback_parts.append("Multi-row Card present")
    else:
        feedback_parts.append("Multi-row Card missing")
        
    if 'funnel' in visuals_lower:
        score += 15
        feedback_parts.append("Funnel Chart present")
    else:
        feedback_parts.append("Funnel Chart missing")

    # 3. Page Name (10 pts)
    page_names = result.get('page_names', [])
    if any("product portfolio" in p.lower() for p in page_names):
        score += 10
        feedback_parts.append("Page named 'Product Portfolio'")
    else:
        feedback_parts.append(f"Page name incorrect (Found: {page_names})")

    # 4. Data Model Items (35 pts total)
    found_strings = result.get('data_model_strings_found', [])
    
    if "Total_Profit" in found_strings:
        score += 10
        feedback_parts.append("Measure 'Total_Profit' found")
    else:
        feedback_parts.append("Measure 'Total_Profit' not found")
        
    if "Margin_Pct" in found_strings:
        score += 10
        feedback_parts.append("Measure 'Margin_Pct' found")
    else:
        feedback_parts.append("Measure 'Margin_Pct' not found")
        
    if "Profit_Tier" in found_strings:
        score += 15
        feedback_parts.append("Column 'Profit_Tier' found")
    else:
        feedback_parts.append("Column 'Profit_Tier' not found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }