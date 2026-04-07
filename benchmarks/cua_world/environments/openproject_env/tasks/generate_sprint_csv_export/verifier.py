#!/usr/bin/env python3
"""
Verifier for generate_sprint_csv_export task.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_generate_sprint_csv_export(traj, env_info, task_info):
    """
    Verifies that the agent correctly filtered and exported the Sprint 1 backlog.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/sprint1_export.csv')
    required_content = metadata.get('required_content', [])
    forbidden_content = metadata.get('forbidden_content', [])

    score = 0
    feedback_parts = []
    
    # 1. Get the Result JSON (Metadata)
    # ----------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get("output_exists", False)
    file_created_during_task = result_data.get("file_created_during_task", False)
    output_size = result_data.get("output_size_bytes", 0)

    # 2. Verify File Existence and Creation
    # ----------------------------------------------------------------
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file not found at {expected_path}"
        }
    
    score += 20
    feedback_parts.append("File exists")

    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this task")

    if output_size < 10:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "File exists but is empty or too small."
        }
    
    # 3. Verify CSV Content
    # ----------------------------------------------------------------
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_path, temp_csv.name)
        
        # Parse CSV
        rows = []
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Handle potential BOM or weird formatting from exports
            content = f.read()
            # Basic sanity check that it looks like CSV
            if "," not in content and ";" not in content:
                return {
                    "passed": False, 
                    "score": score, 
                    "feedback": "File content does not appear to be CSV format."
                }
            
            f.seek(0)
            # Try sniffing format, fallback to standard
            try:
                dialect = csv.Sniffer().sniff(f.read(1024))
                f.seek(0)
                reader = csv.DictReader(f, dialect=dialect)
            except csv.Error:
                f.seek(0)
                reader = csv.DictReader(f)
            
            rows = list(reader)

        # 3a. Valid CSV Structure (20 pts)
        if len(rows) > 0 and (reader.fieldnames and len(reader.fieldnames) > 1):
            score += 20
            feedback_parts.append("Valid CSV format")
        else:
            return {
                "passed": False, 
                "score": score, 
                "feedback": "File exists but could not be parsed as a valid CSV with headers."
            }

        # 3b. Check Required Content (Inclusion) (30 pts)
        # Search all values in all rows for the required strings
        # (This is more robust than looking for a specific column name like 'Subject' which might vary by locale or export settings)
        found_count = 0
        missing_items = []
        
        for item in required_content:
            item_found = False
            for row in rows:
                # Check all values in the row
                if any(item.lower() in str(val).lower() for val in row.values() if val):
                    item_found = True
                    break
            if item_found:
                found_count += 1
            else:
                missing_items.append(item)

        if found_count == len(required_content):
            score += 30
            feedback_parts.append("All required items found")
        elif found_count > 0:
            partial_points = int(30 * (found_count / len(required_content)))
            score += partial_points
            feedback_parts.append(f"Found {found_count}/{len(required_content)} required items")
        else:
            feedback_parts.append("No required items found in export")

        # 3c. Check Forbidden Content (Exclusion) (20 pts)
        # Verify the filter was actually applied (Sprint 2 items should NOT be here)
        forbidden_found = False
        for item in forbidden_content:
            for row in rows:
                if any(item.lower() in str(val).lower() for val in row.values() if val):
                    forbidden_found = True
                    break
        
        if not forbidden_found:
            score += 20
            feedback_parts.append("Correctly filtered (no forbidden items)")
        else:
            feedback_parts.append("Failed filtering check: Contains items from other versions")

    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Error verifying CSV content: {str(e)}"
        }
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Final Pass Decision
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }