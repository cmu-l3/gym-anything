#!/usr/bin/env python3
import json
import os
import csv
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_and_update_broker_fees(traj, env_info, task_info):
    """
    Verify that the agent updated the broker fees and comments for 3 transactions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_broker_fee = metadata.get('expected_broker_fee', 2.99)
    expected_comment = metadata.get('expected_comment', "Fee Audited")
    transactions = metadata.get('transactions', [])
    
    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Load portfolio CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/buyportfolio.csv", temp_csv.name)
        # Read CSV
        rows = []
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            # JStock CSVs might be messy, sometimes strictly quoted
            reader = csv.DictReader(f)
            for row in reader:
                rows.append(row)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load or parse portfolio CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if file was modified (Anti-gaming)
    if result_data.get('file_modified', False):
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File NOT modified (did you save?)")
        
    # 2. Check Row Count
    # We expect 3 data rows
    if len(rows) == 3:
        score += 10
        feedback_parts.append("Correct transaction count (3)")
    else:
        feedback_parts.append(f"Incorrect transaction count: {len(rows)}")
        
    # 3. Check Data Integrity
    # We need to match rows to expected symbols to verify specific updates
    updated_count = 0
    correct_calcs = 0
    
    # Helper to clean float strings
    def parse_float(s):
        try:
            return float(s.replace(',', ''))
        except:
            return 0.0
            
    for expected in transactions:
        symbol = expected['symbol']
        # Find matching row
        # JStock "Code" or "Symbol" field
        match = next((r for r in rows if r.get('Code') == symbol or r.get('Symbol') == symbol), None)
        
        if match:
            # Check Broker Fee
            actual_fee = parse_float(match.get('Broker', '0'))
            # Check Comment
            actual_comment = match.get('Comment', '')
            
            # Check Net Purchase Value logic: (Units * Price) + Fee
            # We trust the file's calc, but we verify it matches our expectation
            actual_net_val = parse_float(match.get('Net Purchase Value', '0'))
            expected_net_val = expected['base_cost'] + expected_broker_fee
            
            row_ok = True
            
            # Fee Check
            if abs(actual_fee - expected_broker_fee) < 0.01:
                score += 15  # 15 pts per correct fee
            else:
                row_ok = False
                feedback_parts.append(f"{symbol}: Fee mismatch ({actual_fee})")
                
            # Comment Check
            if actual_comment.strip().lower() == expected_comment.lower():
                score += 10  # 10 pts per correct comment
            else:
                row_ok = False
                feedback_parts.append(f"{symbol}: Comment mismatch ('{actual_comment}')")
            
            # Calculation Check (minor points)
            if abs(actual_net_val - expected_net_val) < 0.1:
                correct_calcs += 1
                
            if row_ok:
                updated_count += 1
        else:
            feedback_parts.append(f"Missing transaction for {symbol}")

    # Calculation bonus
    if correct_calcs == 3:
        score += 5
        feedback_parts.append("All calculations correct")
        
    # Pass check
    # Max score: 10 (mod) + 10 (count) + 3*(15+10) (rows) + 5 (calc) = 100
    passed = (score >= 85) and (updated_count == 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }