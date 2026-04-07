#!/usr/bin/env python3
"""
Verifier for the Polyglot Audit Report task.
Reads the exported CSV and compares it row-by-row against the hidden ground truth 
JSON to ensure accurate querying and joining from both MariaDB and MongoDB.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification framework error: copy_from_env not available."}

    # Initialize score and feedback
    score = 0
    feedback_parts = []
    
    # Expected headers from task spec
    expected_headers = ["User_Email", "Network", "Publish_Date", "Post_Content", "Post_URL"]

    # Retrieve and load task_result.json
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_meta = json.load(f)
            
        csv_exists = result_meta.get("csv_exists", False)
        created_during_task = result_meta.get("created_during_task", False)
        
        # Criterion 1: File Existence & Anti-Gaming Timestamp (20 pts)
        if not csv_exists:
            return {
                "passed": False,
                "score": 0,
                "feedback": "audit_report.csv was not found at /workspace/audit_report.csv."
            }
            
        score += 10
        feedback_parts.append("CSV file generated")
        
        if created_during_task:
            score += 10
            feedback_parts.append("File created during task session")
        else:
            feedback_parts.append("WARNING: File timestamp precedes task start (potential gaming)")

        # Load Ground Truth
        copy_from_env("/tmp/ground_truth.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            ground_truth = json.load(f)
            
        # Load CSV
        copy_from_env("/tmp/audit_report.csv", tmp_csv.name)
        
        with open(tmp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            
            # Criterion 2: Correct Headers (10 pts)
            if not headers:
                return {
                    "passed": False,
                    "score": score,
                    "feedback": " | ".join(feedback_parts) + " | CSV file is empty."
                }
                
            headers = [h.strip() for h in headers]
            if headers == expected_headers:
                score += 10
                feedback_parts.append("Headers match exactly")
            else:
                feedback_parts.append(f"Headers mismatch. Expected {expected_headers}, got {headers}")
                # Without exact headers, parsing accuracy falls back to index mapping, but task requires exact names.
                # Reverting to DictReader if possible, but failing strict header check points.
                
            # Move pointer back, load as DictReader using their headers
            f.seek(0)
            dict_reader = csv.DictReader(f)
            rows = list(dict_reader)
            
            # Criterion 3: Completeness (30 pts)
            expected_count = len(ground_truth)
            actual_count = len(rows)
            
            if actual_count == expected_count:
                score += 30
                feedback_parts.append(f"Correct row count ({actual_count})")
            elif actual_count > 0:
                proportion = min(actual_count / expected_count, 1.0)
                score += int(30 * proportion)
                feedback_parts.append(f"Incomplete data: {actual_count}/{expected_count} rows")
            else:
                feedback_parts.append("Data rows missing")

            # Criterion 4: Join Integrity & Accuracy (30 pts)
            # Verifies that for a given Post_URL, the Email and Content match the ground truth
            correct_joins = 0
            
            # We must map to expected columns even if they misnamed them slightly
            email_col = next((h for h in dict_reader.fieldnames if "email" in h.lower()), "User_Email")
            url_col = next((h for h in dict_reader.fieldnames if "url" in h.lower()), "Post_URL")
            content_col = next((h for h in dict_reader.fieldnames if "content" in h.lower()), "Post_Content")
            
            for row in rows:
                row_url = row.get(url_col, "").strip()
                row_email = row.get(email_col, "").strip()
                row_content = row.get(content_col, "").strip()
                
                if row_url in ground_truth:
                    gt_record = ground_truth[row_url]
                    if row_email == gt_record["email"] and row_content == gt_record["content"]:
                        correct_joins += 1

            if expected_count > 0:
                accuracy_ratio = correct_joins / expected_count
                score += int(30 * accuracy_ratio)
                if accuracy_ratio == 1.0:
                    feedback_parts.append("100% Join accuracy")
                else:
                    feedback_parts.append(f"Join accuracy: {correct_joins}/{expected_count} records matched ground truth")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        feedback_parts.append(f"Verification script encountered an error: {e}")
        
    finally:
        for tmp_file in [tmp_result.name, tmp_gt.name, tmp_csv.name]:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)

    passed = score >= 90 # High threshold because script should perfectly pull data
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }