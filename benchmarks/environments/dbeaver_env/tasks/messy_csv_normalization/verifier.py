#!/usr/bin/env python3
"""
Verifier for Messy CSV Normalization Task

Points distribution:
- Table 'clean_sales' exists: 10 pts
- Correct Row Count: 10 pts
- Schema (Columns) Correct: 10 pts
- Date Format (YYYY-MM-DD): 25 pts
- ID Extraction (Integer IDs): 20 pts
- Amount Cleaned & Numeric: 15 pts
- SQL Script Saved: 10 pts

Pass Threshold: 70 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_messy_csv_normalization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 1. Table Existence (10 pts)
    if result.get('table_exists', False):
        score += 10
        feedback.append("Table 'clean_sales' created.")
    else:
        feedback.append("Table 'clean_sales' NOT found.")
        # Critical failure, usually means nothing else will work well, but we check anyway
        
    # 2. Row Count (10 pts)
    if result.get('row_count_match', False):
        score += 10
        feedback.append(f"Row count correct ({result.get('actual_row_count')}).")
    else:
        feedback.append(f"Row count mismatch: Got {result.get('actual_row_count')}, expected {result.get('expected_row_count')}.")
        
    # 3. Schema (10 pts)
    if result.get('columns_correct', False):
        score += 10
        feedback.append("Table schema contains correct columns.")
    else:
        feedback.append("Table schema missing required columns (SaleId, SaleDate, CustomerId, SaleAmount).")
        
    # 4. Date Format (25 pts)
    if result.get('date_format_correct', False):
        score += 25
        feedback.append("Date format converted to YYYY-MM-DD correctly.")
    else:
        feedback.append("Date format incorrect. Expected YYYY-MM-DD (ISO).")
        
    # 5. ID Extraction (20 pts)
    if result.get('ids_extracted', False):
        score += 20
        feedback.append("Customer IDs extracted from text correctly.")
    else:
        feedback.append("Customer IDs not extracted correctly (contain text/brackets).")
        
    # 6. Amount Numeric/Sum (15 pts)
    # Combine checks: must be numeric type AND sum must match (proving correct parsing of $ and ,)
    if result.get('amount_numeric', False) and result.get('sum_match', False):
        score += 15
        feedback.append("SaleAmount cleaned and stored as numeric values.")
    elif result.get('amount_numeric', False):
        score += 5
        feedback.append("SaleAmount is numeric but values don't sum correctly (parsing error?).")
    else:
        feedback.append("SaleAmount contains non-numeric characters (likely '$' or ',').")
        
    # 7. Script Exists (10 pts)
    if result.get('script_exists', False):
        score += 10
        feedback.append("Transformation script saved.")
    else:
        feedback.append("Transformation script not found.")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }