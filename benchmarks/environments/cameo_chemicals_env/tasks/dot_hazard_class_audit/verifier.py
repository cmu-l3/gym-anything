#!/usr/bin/env python3
"""
Verifier for DOT Hazard Class Audit task.
Verifies the CSV output matches the expected ground truth compliance check.
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dot_hazard_class_audit(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the agent correctly audited the hazard classes.
    
    Scoring Criteria:
    1. Output file exists and created during task (10 pts)
    2. Correct Official Class extracted (10 pts * 5 items = 50 pts)
    3. Correct Status (PASS/FAIL) determination (8 pts * 5 items = 40 pts)
    Total: 100 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # Files to retrieve
    remote_result_json = "/tmp/task_result.json"
    remote_csv_output = "/home/ga/Documents/manifest_audit_report.csv"
    
    # 1. Retrieve Metadata JSON
    task_stats = {}
    with tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='.json') as tmp_json:
        try:
            copy_from_env(remote_result_json, tmp_json.name)
            tmp_json.seek(0)
            task_stats = json.load(tmp_json)
        except Exception as e:
            logger.error(f"Failed to load task result JSON: {e}")
        finally:
            try: os.unlink(tmp_json.name)
            except: pass

    # Check basic file existence/creation from metadata
    if not task_stats.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Audit report file not found at ~/Documents/manifest_audit_report.csv"
        }
        
    if not task_stats.get("file_created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Audit report file was not created/modified during the task session (anti-gaming check failed)."
        }

    # 2. Retrieve and Parse CSV Content
    rows = []
    with tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='.csv') as tmp_csv:
        try:
            copy_from_env(remote_csv_output, tmp_csv.name)
            # Read CSV
            with open(tmp_csv.name, 'r', newline='', encoding='utf-8') as f:
                # Use Sniffer to handle potential delimiter variations
                try:
                    dialect = csv.Sniffer().sniff(f.read(1024))
                    f.seek(0)
                    reader = csv.DictReader(f, dialect=dialect)
                except:
                    # Fallback to standard comma
                    f.seek(0)
                    reader = csv.DictReader(f)
                
                # Normalize headers (strip spaces, lowercase)
                if reader.fieldnames:
                    reader.fieldnames = [h.strip().lower() for h in reader.fieldnames]
                
                for row in reader:
                    # Normalize row keys
                    clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                    rows.append(clean_row)
                    
        except Exception as e:
            return {
                "passed": False,
                "score": 10,
                "feedback": f"File exists but could not be parsed as CSV: {str(e)}"
            }
        finally:
            try: os.unlink(tmp_csv.name)
            except: pass

    # 3. Scoring Logic
    score = 10
    feedback_lines = ["File created successfully (+10 pts)"]
    
    # Helper to find column loosely
    def get_val(row, target_keys):
        for k in row:
            for t in target_keys:
                if t in k:
                    return row[k]
        return None

    items_checked = 0
    correct_class_count = 0
    correct_status_count = 0
    
    # We iterate through ground truth and look for corresponding row in user output
    for un_id, gt_data in ground_truth.items():
        # Find row by UN Number
        matching_row = None
        for r in rows:
            r_un = get_val(r, ["un_number", "un number", "un", "id"])
            if r_un and str(un_id) in r_un:
                matching_row = r
                break
        
        if not matching_row:
            feedback_lines.append(f"Missing row for UN {un_id}")
            continue
            
        items_checked += 1
        
        # Check Official Class (10 pts each)
        user_official = get_val(matching_row, ["official_class", "official", "correct_class"])
        expected_official = gt_data["official"]
        
        # Loose match on class (handle "3" vs "3.0" vs "Class 3")
        class_match = False
        if user_official:
            # simple normalization: remove "Class", spaces
            norm_user = user_official.lower().replace("class", "").strip()
            if norm_user == expected_official or norm_user.startswith(expected_official):
                class_match = True
        
        if class_match:
            score += 10
            correct_class_count += 1
        else:
            feedback_lines.append(f"UN {un_id}: Incorrect official class (Expected {expected_official}, Got {user_official})")

        # Check Status (8 pts each)
        user_status = get_val(matching_row, ["status", "result", "pass/fail"])
        expected_status = gt_data["status"]
        
        status_match = False
        if user_status and user_status.upper() == expected_status.upper():
            status_match = True
            
        if status_match:
            score += 8
            correct_status_count += 1
        else:
            feedback_lines.append(f"UN {un_id}: Incorrect status (Expected {expected_status}, Got {user_status})")

    # 4. Final Compilation
    feedback_lines.append(f"Summary: {correct_class_count}/5 official classes correct, {correct_status_count}/5 status determinations correct.")
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_lines)
    }