#!/usr/bin/env python3
"""
Verifier for edit_portfolio_transaction task.
"""

import json
import csv
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_portfolio_transaction(traj, env_info, task_info):
    """
    Verify that the MSFT transaction was edited correctly in the JStock portfolio.
    
    Expected changes in buyportfolio.csv for MSFT row:
    - Broker: 9.99
    - Clearing Fee: 0.03
    - Comment: 'Q1 2024 core holding'
    - Net Purchase Value: Updated correctly (Purchase Value + fees)
    
    AAPL and NVDA rows must remain unchanged.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_broker = metadata.get('expected_broker_fee', 9.99)
    expected_clearing = metadata.get('expected_clearing_fee', 0.03)
    expected_comment = metadata.get('expected_comment', "Q1 2024 core holding")

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve result JSON
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('csv_exists', False):
        return {"passed": False, "score": 0, "feedback": "Portfolio CSV file not found"}

    # 2. Retrieve Portfolio CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/final_buyportfolio.csv", temp_csv.name)
        
        rows = []
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                rows.append(row)
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read portfolio CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Analyze Content
    if len(rows) != 3:
        feedback_parts.append(f"Row count incorrect: expected 3, got {len(rows)}")
    else:
        score += 5
        feedback_parts.append("Row count correct (3)")

    # Find MSFT row
    msft_row = next((r for r in rows if r.get('Code') == 'MSFT' or r.get('Symbol') == 'Microsoft Corp.'), None)
    
    if not msft_row:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "MSFT transaction not found in portfolio"
        }

    # Verify MSFT modifications
    # Broker Fee
    try:
        broker_val = float(msft_row.get('Broker', '0').strip().replace('"',''))
        if abs(broker_val - expected_broker) < 0.01:
            score += 25
            feedback_parts.append(f"Broker fee correct ({broker_val})")
        else:
            feedback_parts.append(f"Broker fee incorrect: got {broker_val}, expected {expected_broker}")
    except ValueError:
        feedback_parts.append("Invalid format for Broker fee")

    # Clearing Fee
    try:
        clearing_val = float(msft_row.get('Clearing Fee', '0').strip().replace('"',''))
        if abs(clearing_val - expected_clearing) < 0.01:
            score += 20
            feedback_parts.append(f"Clearing fee correct ({clearing_val})")
        else:
            feedback_parts.append(f"Clearing fee incorrect: got {clearing_val}, expected {expected_clearing}")
    except ValueError:
        feedback_parts.append("Invalid format for Clearing fee")

    # Comment
    comment_val = msft_row.get('Comment', '').strip().replace('"','')
    if expected_comment.lower() in comment_val.lower():
        score += 15
        feedback_parts.append("Comment correct")
    else:
        feedback_parts.append(f"Comment incorrect: got '{comment_val}', expected '{expected_comment}'")

    # Net Purchase Value Check (Purchase Value + Broker + Clearing + Stamp)
    # Original Purchase Value for MSFT (50 * 374.5) = 18725.0
    # Expected Net = 18725.0 + 9.99 + 0.03 = 18735.02
    try:
        net_val = float(msft_row.get('Net Purchase Value', '0').strip().replace('"',''))
        expected_net = 18735.02
        if abs(net_val - expected_net) < 1.0:
            score += 15
            feedback_parts.append(f"Net Purchase Value updated correctly ({net_val})")
        else:
            feedback_parts.append(f"Net Purchase Value incorrect: got {net_val}, expected ~{expected_net}")
    except ValueError:
        feedback_parts.append("Invalid format for Net Purchase Value")

    # 4. Anti-Gaming: Check other rows unchanged
    other_rows_ok = True
    for code in ['AAPL', 'NVDA']:
        row = next((r for r in rows if r.get('Code') == code), None)
        if row:
            try:
                b = float(row.get('Broker', '0').strip().replace('"',''))
                c = float(row.get('Clearing Fee', '0').strip().replace('"',''))
                if b != 0 or c != 0:
                    other_rows_ok = False
                    feedback_parts.append(f"{code} row was modified (should be 0 fees)")
            except:
                pass
    
    if other_rows_ok:
        score += 10
        feedback_parts.append("Other rows unchanged")

    # 5. Timestamp Check
    if result_data.get('csv_modified_during_task', False):
        score += 10
        feedback_parts.append("File saved during task")
    else:
        feedback_parts.append("Warning: File timestamp not updated (did you save?)")

    passed = (score >= 60 and "Broker fee correct" in str(feedback_parts))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }