#!/usr/bin/env python3
"""
Verifier for legacy_appointment_reconciliation task.
Checks if the agent correctly reconciled CSV data against the MySQL database.
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_appointment_reconciliation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Check if files were created
    if not result.get("ready_created", False) or not result.get("review_created", False):
        feedback.append("One or both output CSV files were not created.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    score += 10
    feedback.append("Output files exist.")

    # Helper to read CSV from env
    def read_csv_from_env(remote_path):
        if not remote_path: return []
        tfile = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(remote_path, tfile.name)
            with open(tfile.name, 'r', encoding='utf-8') as f:
                # Handle potential BOM or whitespace
                content = f.read().strip()
                if not content: return []
                reader = csv.DictReader(content.splitlines())
                return list(reader)
        except Exception as e:
            logger.error(f"Error reading CSV {remote_path}: {e}")
            return []
        finally:
            if os.path.exists(tfile.name):
                os.unlink(tfile.name)

    ready_rows = read_csv_from_env(result.get("ready_path"))
    review_rows = read_csv_from_env(result.get("review_path"))

    # --- Verification Logic ---
    
    # 1. Verify 'ready_import.csv' (Should contain Alice)
    # Expected: GUID=TEST_GUID_ALICE_001, Date_ISO=2023-12-25
    alice_found = False
    format_correct = True
    
    required_cols_ready = ['GUID', 'Date_ISO', 'Time', 'Reason']
    if ready_rows:
        # Check headers loosely (case insensitive)
        headers = [h.strip() for h in ready_rows[0].keys()]
        if not all(col in headers for col in required_cols_ready):
            feedback.append(f"Missing columns in ready_import.csv. Found: {headers}")
            format_correct = False
        
        for row in ready_rows:
            # Check for Alice
            guid = row.get('GUID', '')
            date_iso = row.get('Date_ISO', '')
            
            if guid == 'TEST_GUID_ALICE_001':
                alice_found = True
                if date_iso == '2023-12-25':
                    score += 15 # Correct date conversion
                    feedback.append("Date conversion correct.")
                else:
                    feedback.append(f"Date conversion incorrect for Alice. Got: {date_iso}, Expected: 2023-12-25")
            
            # Anti-gaming: Ensure Bob or Charlie are NOT here
            if 'TEST_GUID_BOB' in guid or 'Bob' in str(row):
                score -= 10
                feedback.append("Incorrectly included duplicate patient (Bob) in ready list.")
            if 'Charlie' in str(row):
                score -= 10
                feedback.append("Incorrectly included missing patient (Charlie) in ready list.")

    if alice_found:
        score += 25
        feedback.append("Correctly identified and extracted GUID for unique match (Alice).")
    else:
        feedback.append("Failed to identify unique match (Alice) or incorrect GUID.")

    # 2. Verify 'review_required.csv' (Should contain Bob and Charlie)
    bob_found = False
    charlie_found = False
    
    if review_rows:
        for row in review_rows:
            # Flexible checking for names in the row
            row_str = str(row).upper()
            if 'BOB' in row_str and 'TESTDUP' in row_str:
                bob_found = True
            if 'CHARLIE' in row_str and 'TESTMISSING' in row_str:
                charlie_found = True
            
            # Bonus: Check if Error_Type exists
            if 'Error_Type' in row:
                pass # Good job

    if bob_found:
        score += 20
        feedback.append("Correctly flagged duplicate patient (Bob) for review.")
    else:
        feedback.append("Failed to flag duplicate patient (Bob).")

    if charlie_found:
        score += 20
        feedback.append("Correctly flagged missing patient (Charlie) for review.")
    else:
        feedback.append("Failed to flag missing patient (Charlie).")

    # Final tally
    if format_correct:
        score += 10
        feedback.append("CSV format looks correct.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " ".join(feedback)
    }