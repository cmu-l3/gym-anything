#!/usr/bin/env python3
"""
Verifier for export_critical_issues_report task.

Checks:
1. CSV file exists and was created during the task.
2. CSV contains specific columns (Due date, Assignee).
3. CSV contains the correct filtered data (Priority=High/Urgent AND Status=Open).
4. CSV row count matches ground truth (5 rows).
"""

import json
import os
import csv
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_critical_issues_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_row_count = metadata.get('expected_row_count', 5)
    target_priorities = [p.lower() for p in metadata.get('target_priorities', ['High', 'Urgent'])]
    forbidden_statuses = [s.lower() for s in metadata.get('forbidden_statuses', ['Closed', 'Rejected'])]
    required_columns = [c.lower() for c in metadata.get('required_columns', ['due date', 'assignee'])]

    # 1. Retrieve Result JSON
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

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Timestamp (30 pts)
    output_exists = result_data.get("output_exists", False)
    created_during_task = result_data.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "CSV file was not created."}
    
    score += 20
    feedback_parts.append("File created")
    
    if created_during_task:
        score += 10
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might be stale")

    # 3. Retrieve and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/exported_report.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in reader.fieldnames] if reader.fieldnames else []
            headers_lower = [h.lower() for h in headers]
            rows = list(reader)
            
        # 4. Verify Columns (20 pts)
        missing_cols = []
        for req in required_columns:
            # Flexible matching: "Assignee" might be "Assigned to"
            found = False
            for h in headers_lower:
                if req in h or (req == "assignee" and "assigned" in h):
                    found = True
                    break
            if not found:
                missing_cols.append(req)
        
        if not missing_cols:
            score += 20
            feedback_parts.append("All required columns present")
        else:
            feedback_parts.append(f"Missing columns: {', '.join(missing_cols)}")
            # Partial credit for columns? No, strict requirement for custom report.

        # 5. Verify Row Count (20 pts)
        row_count = len(rows)
        if row_count == expected_row_count:
            score += 20
            feedback_parts.append(f"Correct row count ({row_count})")
        else:
            feedback_parts.append(f"Incorrect row count: {row_count} (Expected: {expected_row_count})")
            # If they exported everything (likely 15-20 rows), they fail this.

        # 6. Verify Content (Filter Logic) (30 pts)
        priority_failures = 0
        status_failures = 0
        
        for row in rows:
            # Find Priority column (case insensitive)
            p_val = "unknown"
            for k in row.keys():
                if k and "priority" in k.lower():
                    p_val = row[k].lower()
                    break
            
            # Find Status column
            s_val = "unknown"
            for k in row.keys():
                if k and "status" in k.lower():
                    s_val = row[k].lower()
                    break
            
            if p_val not in target_priorities:
                priority_failures += 1
            
            if s_val in forbidden_statuses:
                status_failures += 1
        
        if row_count > 0:
            if priority_failures == 0:
                score += 15
                feedback_parts.append("Priority filter correct")
            else:
                feedback_parts.append(f"Failed priority filter: {priority_failures} rows invalid")

            if status_failures == 0:
                score += 15
                feedback_parts.append("Status filter correct")
            else:
                feedback_parts.append(f"Failed status filter: {status_failures} rows Closed")
        else:
            feedback_parts.append("Empty CSV file")

    except Exception as e:
        feedback_parts.append(f"Error parsing CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }