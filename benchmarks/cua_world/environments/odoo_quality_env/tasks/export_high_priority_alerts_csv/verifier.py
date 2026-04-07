#!/usr/bin/env python3
import json
import os
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_high_priority_alerts_csv(traj, env_info, task_info):
    """
    Verify that the agent exported the correct high priority alerts to CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    high_priority_targets = metadata.get('high_priority_alerts', [])
    low_priority_targets = metadata.get('low_priority_alerts', [])
    
    # Retrieve result file
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # Criterion 1: CSV File Exists (20 pts)
    if result.get('csv_exists'):
        score += 20
        feedback.append(f"CSV file found: {result.get('csv_filename')}")
    else:
        return {"passed": False, "score": 0, "feedback": "No CSV file found in Downloads"}

    # Criterion 2: File created during task (Anti-gaming) (10 pts)
    if result.get('file_created_during_task'):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates it was not created during this task session")

    # Parse CSV Content
    csv_content = result.get('csv_content', "")
    if not csv_content:
        return {"passed": False, "score": score, "feedback": "CSV file is empty"}

    try:
        # Use csv module to parse string
        f = io.StringIO(csv_content)
        reader = csv.DictReader(f)
        rows = list(reader)
        headers = reader.fieldnames if reader.fieldnames else []
        
        # Verify Format (readable as CSV) (10 pts)
        if len(headers) > 0:
            score += 10
        else:
            return {"passed": False, "score": score, "feedback": "Could not parse CSV headers"}

        # Verify Columns (20 pts)
        # We look for "Name" (or Display Name) and "Priority"
        # Odoo exports might use "Display Name" or "Name" depending on version/selection
        # And "Priority" might be "Priority"
        has_name = any('name' in h.lower() for h in headers)
        has_priority = any('priority' in h.lower() for h in headers)
        
        if has_name and has_priority:
            score += 20
            feedback.append("Required columns (Name, Priority) found")
        else:
            feedback.append(f"Missing required columns. Found: {headers}")

        # Check Content Inclusion/Exclusion (30 pts inclusion, 10 pts exclusion)
        # Normalize rows for searching
        # We assume values might be in any column if the header mapping is ambiguous, 
        # but ideally we check specific columns. Let's search the whole row string for robustness against Odoo export format variations.
        
        found_high = 0
        found_low = 0
        
        row_strings = [str(r.values()) for r in rows]
        
        # Check High Priority Inclusion
        for target in high_priority_targets:
            if any(target in rs for rs in row_strings):
                found_high += 1
            else:
                feedback.append(f"Missing high priority alert: {target}")

        if found_high == len(high_priority_targets):
            score += 30
            feedback.append("All high priority alerts present")
        elif found_high > 0:
            score += 15
            feedback.append("Some high priority alerts present")

        # Check Low Priority Exclusion
        for target in low_priority_targets:
            if any(target in rs for rs in row_strings):
                found_low += 1
                feedback.append(f"Incorrectly included low priority alert: {target}")
        
        if found_low == 0:
            score += 10
            feedback.append("Low priority alerts correctly excluded")

    except Exception as e:
        feedback.append(f"Error parsing CSV content: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }