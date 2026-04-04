#!/usr/bin/env python3
"""
Verifier for Chinook DB Reconciliation Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_db_reconciliation(traj, env_info, task_info):
    """
    Verifies the reconciliation task by checking:
    1. DBeaver connection existence (15 pts)
    2. SQL script existence and valid syntax (5+10 pts)
    3. CSV report existence and structure (10+5+5 pts)
    4. Accuracy of reported counts against ground truth (40 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- 1. Connection Verification (15 pts) ---
    if result.get('connection_found'):
        conn_details = result.get('connection_details', {}).get('details', {})
        name = conn_details.get('name', '')
        path = conn_details.get('path', '')
        
        # Check Name Exactness
        if name == 'ChinookProd':
            score += 15
            feedback.append("DBeaver connection 'ChinookProd' found.")
        elif 'chinookprod' in name.lower().replace(' ', ''):
            score += 10
            feedback.append(f"Connection found but name '{name}' is not exactly 'ChinookProd'.")
        else:
            score += 5
            feedback.append("Connection found but name is incorrect.")
            
        # Optional: Check path correctness (no points, just feedback)
        if 'chinook_prod.db' not in path:
            feedback.append(f"Warning: Connection points to '{path}', expected 'chinook_prod.db'.")
    else:
        feedback.append("No 'ChinookProd' connection found in DBeaver.")

    # --- 2. SQL Script Verification (15 pts) ---
    if result.get('sql_exists'):
        score += 5
        feedback.append("SQL reconciliation script exists.")
        
        if result.get('sql_valid'):
            score += 10
            feedback.append("SQL script contains expected commands (ATTACH, comparison logic).")
        else:
            feedback.append("SQL script appears empty or missing key logic (ATTACH/SELECT).")
    else:
        feedback.append("Reconciliation SQL script not found.")

    # --- 3. CSV Report Structure (20 pts) ---
    csv_rows = result.get('csv_data', [])
    ground_truth = result.get('ground_truth', {})
    
    if result.get('csv_exists'):
        score += 10
        feedback.append("CSV report file exists.")
        
        # Check for pre-existing file gaming
        if not result.get('csv_created_during_task'):
            score -= 10
            feedback.append("WARNING: CSV file timestamp predates task start.")
        
        # Check Row Count (should be 4 data rows)
        if len(csv_rows) == 4:
            score += 5
            feedback.append("CSV contains exactly 4 data rows.")
        else:
            feedback.append(f"CSV contains {len(csv_rows)} rows (expected 4).")
            
        # Check Columns
        if len(csv_rows) > 0:
            keys = [k.lower() for k in csv_rows[0].keys()]
            required = ['changecategory', 'tablename', 'recordsaffected', 'direction', 'details']
            if all(r in keys for r in required):
                score += 5
                feedback.append("CSV columns are correct.")
            else:
                feedback.append(f"CSV missing required columns. Found: {keys}")
    else:
        feedback.append("CSV reconciliation report not found.")

    # --- 4. Data Accuracy (40 pts) ---
    # We look for rows in the CSV that correspond to our categories
    # The agent might name categories slightly differently, so we try to map them or rely on row content
    
    # Map of category keywords to ground truth keys
    cat_map = {
        'new_customers': ['new', 'customer', 'insert'],
        'deleted_invoices': ['delete', 'invoice', 'remove'],
        'price_changes': ['price', 'unitprice', 'cost'],
        'country_changes': ['country', 'location', 'region']
    }
    
    gt_map = {
        'new_customers': ground_truth.get('new_customers', 3),
        'deleted_invoices': ground_truth.get('deleted_invoices', 5),
        'price_changes': ground_truth.get('price_changes', 10),
        'country_changes': ground_truth.get('country_changes', 2)
    }
    
    correct_counts = 0
    
    # Iterate through ground truth categories
    for gt_key, expected_val in gt_map.items():
        keywords = cat_map[gt_key]
        found = False
        
        # Search for a matching row in CSV
        for row in csv_rows:
            # Check 'changecategory' or 'tablename' or 'details' for keywords
            row_text = str(row.values()).lower()
            if all(k in row_text for k in keywords[:1]): # Match at least the primary keyword
                try:
                    val = int(row.get('recordsaffected', -1))
                    if val == expected_val:
                        found = True
                        correct_counts += 1
                        feedback.append(f"✓ {gt_key}: Count {val} is correct.")
                    else:
                        feedback.append(f"✗ {gt_key}: Count {val} incorrect (expected {expected_val}).")
                except:
                    feedback.append(f"✗ {gt_key}: 'RecordsAffected' is not a number.")
                break
        
        if not found and not any(k in str(csv_rows).lower() for k in keywords[:1]):
             feedback.append(f"✗ {gt_key}: Category not found in report.")

    score += (correct_counts * 10)

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }