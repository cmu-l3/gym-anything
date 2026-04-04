#!/usr/bin/env python3
"""
Verifier for generate_marketing_list task.

Checks:
1. CSV file existence and freshness.
2. Table persistence in ODB file.
3. Content validity:
   - Correct set of CustomerIds (Jazz/Blues buyers).
   - Correct 'FormalName' formatting (Last, First).
   - Correct 'FullAddress' formatting (handling NULL State).
"""

import json
import tempfile
import os
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_marketing_list(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: CSV Export (10 pts) ---
    if result.get('csv_exists') and result.get('csv_created_during_task'):
        score += 10
        feedback_parts.append("CSV exported successfully")
    elif result.get('csv_exists'):
        score += 5
        feedback_parts.append("CSV exists but old timestamp")
    else:
        feedback_parts.append("CSV file not found")
        return {"passed": False, "score": 0, "feedback": "CSV file not found"}

    # --- Criterion 2: Table Persistence (20 pts) ---
    if result.get('table_persisted'):
        score += 20
        feedback_parts.append("Database table 'TargetedMailingList' created")
    else:
        feedback_parts.append("Database table NOT saved/persisted")

    # --- Load Data for Content Verification ---
    csv_content = result.get('csv_content_json', "")
    ground_truth = result.get('ground_truth', [])
    
    if not csv_content:
        return {"passed": False, "score": score, "feedback": "CSV file is empty"}
        
    if isinstance(ground_truth, dict) and 'error' in ground_truth:
        return {"passed": False, "score": score, "feedback": f"Ground truth generation error: {ground_truth['error']}"}

    # Parse Agent CSV
    agent_rows = []
    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        # Normalize headers (strip whitespace, lower case comparison)
        headers = [h.strip() for h in reader.fieldnames] if reader.fieldnames else []
        
        # Check required columns
        req_cols = ['CustomerId', 'FormalName', 'FullAddress']
        missing_cols = [c for c in req_cols if c not in [h for h in headers]] # Loose matching? No, strict is better for DB tasks
        
        # If strict match fails, try case-insensitive
        header_map = {}
        for h in headers:
            header_map[h.lower()] = h
            
        mapped_req_cols = {}
        for r in req_cols:
            if r.lower() in header_map:
                mapped_req_cols[r] = header_map[r.lower()]
            else:
                feedback_parts.append(f"Missing column: {r}")
                
        if len(mapped_req_cols) < 3:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        for row in reader:
            agent_rows.append({
                'id': row.get(mapped_req_cols['CustomerId']),
                'name': row.get(mapped_req_cols['FormalName']),
                'addr': row.get(mapped_req_cols['FullAddress'])
            })
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"CSV parse error: {e}"}

    # --- Criterion 3: Correct Segmentation (30 pts) ---
    # Agent must have exactly the customers from ground truth
    gt_ids = set(str(g['CustomerId']) for g in ground_truth)
    agent_ids = set(str(r['id']) for r in agent_rows if r['id'])
    
    # Precision/Recall logic
    if not agent_ids:
        feedback_parts.append("CSV contains no valid CustomerIds")
    else:
        tp = len(gt_ids.intersection(agent_ids))
        fp = len(agent_ids - gt_ids)
        fn = len(gt_ids - agent_ids)
        
        if tp == len(gt_ids) and fp == 0:
            score += 30
            feedback_parts.append("Customer list exactly matches target (Jazz/Blues buyers)")
        elif tp > 0:
            # Partial credit
            overlap_pct = tp / len(gt_ids)
            points = int(20 * overlap_pct)
            if fp > 0: points -= 5
            score += max(0, points)
            feedback_parts.append(f"Customer list match: {int(overlap_pct*100)}% ({fp} false positives)")
        else:
            feedback_parts.append("No correct customers found")

    # --- Criterion 4: FormalName Formatting (20 pts) ---
    # Check "Last, First" for a sample of rows
    name_score = 0
    checks = 0
    valid_format_count = 0
    
    gt_lookup = {str(g['CustomerId']): g for g in ground_truth}
    
    for row in agent_rows:
        if not row['id'] or row['id'] not in gt_lookup: continue
        checks += 1
        expected_name = gt_lookup[row['id']]['FormalName']
        actual_name = row['name']
        
        # Strict or loose? "Last, First"
        if actual_name and actual_name.strip() == expected_name:
            valid_format_count += 1
            
    if checks > 0:
        if valid_format_count / checks > 0.9:
            score += 20
            feedback_parts.append("Name formatting correct")
        elif valid_format_count / checks > 0.5:
            score += 10
            feedback_parts.append("Name formatting mostly correct")
        else:
            feedback_parts.append("Name formatting incorrect")
    else:
        # If no matching IDs, cannot verify formatting
        pass

    # --- Criterion 5: Address Formatting & NULL Handling (20 pts) ---
    # Check "Address, City, State Zip, Country"
    # Crucially, check rows where State is NULL
    
    null_state_customers = [g for g in ground_truth if not g['Parts']['State']]
    addr_score = 0
    
    # Check general address formatting
    valid_addr = 0
    for row in agent_rows:
        if not row['id'] or row['id'] not in gt_lookup: continue
        
        parts = gt_lookup[row['id']]['Parts']
        addr_str = row['addr']
        
        if not addr_str: continue
        
        # Logic: Should contain Address, City, Country
        has_main_parts = (parts['Address'] in addr_str and 
                          parts['City'] in addr_str and 
                          parts['Country'] in addr_str)
        
        # Logic: Should NOT contain the literal word "NULL" or be empty if parts exist
        has_bad_null = "NULL" in addr_str
        
        if has_main_parts and not has_bad_null:
            valid_addr += 1
            
    if checks > 0 and (valid_addr / checks) > 0.8:
        score += 10 # Base formatting points
        
    # Check specifically for NULL state handling
    # Verify that for customers with no state, we don't see "NULL" in the string
    null_state_checks = 0
    null_state_success = 0
    
    for g in null_state_customers:
        cid = str(g['CustomerId'])
        # Find agent row
        agent_row = next((r for r in agent_rows if r['id'] == cid), None)
        if agent_row:
            null_state_checks += 1
            addr = agent_row['addr']
            # If state is missing, address shouldn't say "NULL" and should still look valid
            if addr and "NULL" not in addr and g['Parts']['Country'] in addr:
                null_state_success += 1
                
    if null_state_checks > 0:
        if null_state_success == null_state_checks:
            score += 10
            feedback_parts.append("NULL State handled correctly")
        else:
            feedback_parts.append("NULL State handling failed (found 'NULL' or malformed)")
    else:
        # If no null state customers were in the set (unlikely for Chinook), give benefit of doubt if general addr valid
        if checks > 0 and (valid_addr / checks) > 0.8:
            score += 10

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }