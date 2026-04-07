#!/usr/bin/env python3
"""
Verifier for household_aggregation_mailing_list task.

Checks:
1. Database Integrity: Verify all 6 patients were inserted into fchpat.
2. CSV Existence: Verify the mailing list file was created.
3. CSV Correctness: 
   - Headers match exactly.
   - 3 Rows (Deduplication of Lemoine family).
   - Correct Head of Household selection (Oldest).
   - Correct Member Counts.
"""

import json
import csv
import os
import shutil
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_household_aggregation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_headers = metadata.get('expected_headers', [])
    
    # Temp files for artifacts
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    csv_path = os.path.join(temp_dir, "household_mailing_list.csv")
    db_dump_path = os.path.join(temp_dir, "db_dump.txt")

    score = 0
    feedback_parts = []
    
    try:
        # Load Result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

        # --- CRITERION 1: Database Injection (30 pts) ---
        # Check if patients were actually inserted
        try:
            copy_from_env(result.get("db_dump_path"), db_dump_path)
            with open(db_dump_path, 'r') as f:
                db_content = f.read().lower()
            
            patients_found = 0
            # Simple keyword check for the 6 patients (sufficient proxy for this task)
            required_names = ["jacques", "sophie", "jean", "marie", "lucas", "claire"]
            for name in required_names:
                if name in db_content:
                    patients_found += 1
            
            db_score = (patients_found / 6) * 30
            score += db_score
            feedback_parts.append(f"Database Verification: {patients_found}/6 patients found ({int(db_score)}/30 pts)")
        except Exception as e:
            feedback_parts.append(f"Database check failed: {e}")

        # --- CRITERION 2: CSV Existence & Structure (20 pts) ---
        csv_exists = result.get("csv_exists", False)
        if csv_exists:
            try:
                copy_from_env(result.get("csv_path"), csv_path)
                with open(csv_path, 'r', newline='', encoding='utf-8') as f:
                    reader = csv.DictReader(f)
                    headers = reader.fieldnames
                    rows = list(reader)

                # Check headers
                if headers and  [h.strip() for h in headers] == expected_headers:
                    score += 10
                    feedback_parts.append("CSV Headers: Correct (10/10 pts)")
                else:
                    feedback_parts.append(f"CSV Headers: Incorrect. Expected {expected_headers}, got {headers}")

                score += 10 # File exists
                feedback_parts.append("CSV File: Exists (10/10 pts)")
                
                # --- CRITERION 3: Content Logic (50 pts) ---
                # We expect 3 rows
                if len(rows) == 3:
                    score += 10
                    feedback_parts.append("Row Count: Correct (3 households) (10/10 pts)")
                else:
                    feedback_parts.append(f"Row Count: Incorrect. Expected 3, got {len(rows)}")

                # Verify Households
                # Normalize keys for verification (lowercase city/head name)
                households = {}
                for row in rows:
                    # Robustly handle potential whitespace or casing in keys if headers were slightly off, 
                    # but we strictly checked headers above.
                    city = row.get("City", "").strip().lower()
                    head = row.get("Head_FirstName", "").strip().lower()
                    count = row.get("Member_Count", "0").strip()
                    households[city] = {"head": head, "count": count}

                # Check Lemoine (Paris) - Expecting normalized 'paris'
                # Family 1: Paris. Head: Jacques (1955) vs Sophie (1958). Jacques is older.
                paris = households.get("paris")
                if paris:
                    if paris["head"] == "jacques":
                        score += 10
                        feedback_parts.append("Lemoine Head: Correct (Jacques) (10/10 pts)")
                    else:
                        feedback_parts.append(f"Lemoine Head: Incorrect. Expected Jacques, got {paris['head']}")
                    
                    if paris["count"] == "2":
                        score += 5
                        feedback_parts.append("Lemoine Count: Correct (5/5 pts)")
                    else:
                        feedback_parts.append(f"Lemoine Count: Incorrect. Expected 2, got {paris['count']}")
                else:
                    feedback_parts.append("Household Missing: Paris (Lemoine)")

                # Check Dupuis (Lyon) - Head: Jean (1980) vs Marie (1982) vs Lucas (2010). Jean is oldest.
                lyon = households.get("lyon")
                if lyon:
                    if lyon["head"] == "jean":
                        score += 10
                        feedback_parts.append("Dupuis Head: Correct (Jean) (10/10 pts)")
                    else:
                        feedback_parts.append(f"Dupuis Head: Incorrect. Expected Jean, got {lyon['head']}")

                    if lyon["count"] == "3":
                        score += 5
                        feedback_parts.append("Dupuis Count: Correct (5/5 pts)")
                    else:
                        feedback_parts.append(f"Dupuis Count: Incorrect. Expected 3, got {lyon['count']}")
                else:
                    feedback_parts.append("Household Missing: Lyon (Dupuis)")

                # Check Martin (Strasbourg)
                strasbourg = households.get("strasbourg")
                if strasbourg:
                    if strasbourg["head"] == "claire" and strasbourg["count"] == "1":
                        score += 10
                        feedback_parts.append("Martin Household: Correct (10/10 pts)")
                    else:
                        feedback_parts.append("Martin Household: Incorrect data")
                else:
                    feedback_parts.append("Household Missing: Strasbourg (Martin)")

            except Exception as e:
                feedback_parts.append(f"CSV parsing error: {e}")
        else:
            feedback_parts.append("CSV File: Missing (0/50 pts)")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 75
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }