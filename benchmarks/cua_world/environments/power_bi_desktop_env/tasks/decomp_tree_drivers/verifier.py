#!/usr/bin/env python3
"""
Verifier for decomp_tree_drivers task.

Scoring (100 points total):
- File saved & valid (10 pts): Sales_Decomposition.pbix exists, valid size, created during task.
- Page Name (10 pts): Page named "Sales Drivers".
- Visual Types (30 pts): Decomposition Tree (20) and Multi-Row Card (10) present.
- Data Model (20 pts): Total_Sales and Avg_Order_Value measures found.
- Configuration (30 pts): Decomp Tree has Analyze field (15) and Explain By fields (15).

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_decomp_tree_drivers(traj, env_info, task_info):
    """Verify Decomposition Tree report creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/decomp_tree_result.json", temp_file.name)
    except Exception as e:
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
    
    # 1. File Validation (10 pts)
    file_exists = result.get('file_exists', False)
    created_correctly = result.get('file_created_after_start', False)
    file_size = result.get('file_size_bytes', 0)
    
    if file_exists and created_correctly and file_size > 5000:
        score += 10
        feedback_parts.append("File saved successfully")
    else:
        feedback_parts.append("File missing, too small, or not created during task")
        # Critical failure if no file
        if not file_exists:
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Page Name (10 pts)
    page_names = result.get('page_names', [])
    if any(name.lower() == "sales drivers" for name in page_names):
        score += 10
        feedback_parts.append("Page renamed correctly")
    else:
        feedback_parts.append(f"Page name incorrect (Found: {page_names})")

    # 3. Visual Types (30 pts)
    visuals = result.get('visual_types', [])
    
    # Check for Decomposition Tree (allow internal aliases)
    has_decomp = any(v in ['decompositionTreeMap', 'decompositionTree'] for v in visuals)
    if has_decomp:
        score += 20
        feedback_parts.append("Decomposition Tree present")
    else:
        feedback_parts.append("Decomposition Tree missing")
        
    # Check for Multi-Row Card
    has_card = any(v == 'multiRowCard' for v in visuals)
    if has_card:
        score += 10
        feedback_parts.append("Multi-Row Card present")
    else:
        feedback_parts.append("Multi-Row Card missing")

    # 4. Data Model Measures (20 pts)
    measures = result.get('model_measures', [])
    if 'Total_Sales' in measures:
        score += 10
        feedback_parts.append("Measure 'Total_Sales' found")
    else:
        feedback_parts.append("Measure 'Total_Sales' missing")
        
    if 'Avg_Order_Value' in measures:
        score += 10
        feedback_parts.append("Measure 'Avg_Order_Value' found")
    else:
        feedback_parts.append("Measure 'Avg_Order_Value' missing")

    # 5. Configuration (30 pts)
    # Only verify config if the visual exists
    if has_decomp:
        config = result.get('decomp_tree_config', {})
        
        # Analyze field (15 pts)
        if config.get('analyze_field', False):
            score += 15
            feedback_parts.append("Analyze field configured")
        else:
            feedback_parts.append("Decomp Tree 'Analyze' field empty")
            
        # Explain By fields (15 pts) - Require at least 3 of 4
        # We check count because names are hard to extract from config JSON without query resolution
        explain_count = config.get('explain_by_count', 0)
        if explain_count >= 3:
            score += 15
            feedback_parts.append(f"Explain By configured ({explain_count} fields)")
        elif explain_count > 0:
            score += 5 # Partial credit
            feedback_parts.append(f"Explain By partially configured ({explain_count} fields)")
        else:
            feedback_parts.append("Decomp Tree 'Explain By' field empty")
            
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }