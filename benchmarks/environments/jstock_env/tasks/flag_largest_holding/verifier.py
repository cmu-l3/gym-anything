#!/usr/bin/env python3
"""
Verifier for flag_largest_holding task.
Verifies that the agent correctly identified the largest holding (AMZN)
and tagged it with "Core Holding" in the JStock portfolio CSV.
"""

import json
import os
import csv
import logging
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flag_largest_holding(traj, env_info, task_info):
    """
    Verify the portfolio CSV content.
    
    Criteria:
    1. AMZN row exists and has "Core Holding" in Comment column. (50 pts)
    2. Other rows (T, GOOGL, F) do NOT have "Core Holding" in Comment. (20 pts)
    3. AMZN financial data (Units, Price) is unchanged. (20 pts)
    4. File was modified during task. (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    target_symbol = "AMZN"
    target_comment_fragment = "Core Holding"
    
    # Setup temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    score = 0
    feedback = []
    
    try:
        # 1. Get Result JSON
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get("file_exists", False):
            return {"passed": False, "score": 0, "feedback": "Portfolio file deleted or missing"}

        # Check modification timestamp (Anti-gaming)
        if result_data.get("file_modified", False):
            score += 10
            feedback.append("File modified during task")
        else:
            feedback.append("File NOT modified (Warning)")

        # 2. Get CSV Content
        copy_from_env(result_data["csv_path"], temp_csv.name)
        
        # Parse CSV
        rows = []
        with open(temp_csv.name, 'r', newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
        if not rows:
            return {"passed": False, "score": 0, "feedback": "Portfolio CSV is empty or invalid"}

        # Analysis
        amzn_found = False
        distractors_clean = True
        integrity_ok = True
        tagged_correctly = False
        
        for row in rows:
            code = row.get("Code", "").strip()
            comment = row.get("Comment", "").strip()
            units = row.get("Units", "0").strip()
            price = row.get("Purchase Price", "0").strip()
            
            if code == target_symbol:
                amzn_found = True
                # Check Tag
                if target_comment_fragment.lower() in comment.lower():
                    tagged_correctly = True
                
                # Check Integrity (AMZN should be 100.0 units @ 170.0)
                # Allowing string comparison or slight float tolerance
                try:
                    if float(units) != 100.0 or float(price) != 170.0:
                        integrity_ok = False
                        feedback.append(f"Data integrity failed for AMZN: Units={units}, Price={price}")
                except ValueError:
                    integrity_ok = False
                    
            elif code in ["T", "GOOGL", "F"]:
                # Check Distractors
                if target_comment_fragment.lower() in comment.lower():
                    distractors_clean = False
                    feedback.append(f"Incorrectly tagged distractor: {code}")

        # Scoring
        if amzn_found and tagged_correctly:
            score += 50
            feedback.append("AMZN correctly identified and tagged")
        elif amzn_found:
            feedback.append("AMZN found but NOT tagged correctly")
        else:
            feedback.append("AMZN row deleted or missing")
            
        if distractors_clean:
            score += 20
            feedback.append("Distractors correctly ignored")
            
        if amzn_found and integrity_ok:
            score += 20
            feedback.append("Data integrity maintained")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        for f in [temp_json.name, temp_csv.name]:
            if os.path.exists(f):
                os.unlink(f)

    # Final Pass Determination
    # Must have tagged correctly and kept integrity
    passed = (score >= 80) and tagged_correctly and integrity_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }