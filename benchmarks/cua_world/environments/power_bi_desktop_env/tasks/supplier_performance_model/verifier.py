#!/usr/bin/env python3
"""
Verifier for supplier_performance_model task.

Checks:
1. PBIX file exists and was created during the task.
2. Contains required visuals (Treemap, Table).
3. Contains DAX measure 'Total_Order_Value' using SUMX.
4. Contains Data Model elements indicating relationships.

Scoring:
- File Valid: 20 pts
- Data Model (Measure + Relationships): 40 pts
- Visuals (Treemap + Table + PageName): 40 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_supplier_performance_model(traj, env_info, task_info):
    """Verify the Power BI supplier performance report."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/supplier_perf_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve or parse task result file. Did the agent save the file?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Validity (20 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        if result.get('file_size_bytes', 0) > 5000:  # Minimum size for valid PBIX
            score += 20
            feedback.append("✅ Report file saved successfully.")
        else:
            score += 5
            feedback.append("⚠️ Report file exists but is suspiciously small.")
    else:
        feedback.append("❌ Report file not found or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Data Model & DAX (40 pts)
    # Measure Name
    if result.get('has_measure_name'):
        score += 15
        feedback.append("✅ Measure 'Total_Order_Value' found.")
    else:
        feedback.append("❌ Measure 'Total_Order_Value' not found.")
        
    # SUMX usage
    if result.get('has_sumx_function'):
        score += 15
        feedback.append("✅ SUMX function usage detected.")
    else:
        feedback.append("❌ SUMX function not detected in model.")
        
    # Relationships (Columns present)
    if result.get('relationships_columns_found'):
        score += 10
        feedback.append("✅ Key relationship columns found in model.")
    else:
        feedback.append("❌ Relationship columns (SupplierID/ProductID) missing from model.")

    # Criterion 3: Visuals & Page (40 pts)
    # Treemap
    if result.get('has_treemap'):
        score += 15
        feedback.append("✅ Treemap visual created.")
    else:
        feedback.append("❌ Treemap visual missing.")
        
    # Table
    if result.get('has_table'):
        score += 15
        feedback.append("✅ Table visual created.")
    else:
        feedback.append("❌ Table visual missing.")
        
    # Page Name
    if result.get('page_name_match'):
        score += 10
        feedback.append("✅ Page renamed to 'Supplier Performance'.")
    else:
        feedback.append("⚠️ Page name 'Supplier Performance' not found.")

    # Final Pass Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }