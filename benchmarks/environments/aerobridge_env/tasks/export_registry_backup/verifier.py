#!/usr/bin/env python3
"""
Verifier for export_registry_backup task.

Checks:
1. File existence and timestamp (Anti-gaming).
2. JSON validity and structure (Django fixture format).
3. Data completeness (Compare file model counts vs DB counts).
4. Formatting (Pretty-printed indent=2).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_registry_backup(traj, env_info, task_info):
    """
    Verify the registry backup file export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_exists = result.get('file_exists', False)
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start_time', 0)
    valid_json = result.get('valid_json', False)
    is_fixture = result.get('is_fixture_structure', False)
    indent_style = result.get('indentation_style', 'unknown')
    file_counts = result.get('model_counts_file', {})
    db_counts = result.get('model_counts_db', {})
    registry_models_present = result.get('registry_models_present', 0)
    file_size = result.get('file_size', 0)

    # Criteria 1: File Exists (10 pts)
    if file_exists:
        score += 10
        feedback_parts.append("File exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Backup file not found at /home/ga/Documents/registry_backup.json"}

    # Criteria 2: Created during task (10 pts)
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("File timestamp indicates it was created before task start (Anti-gaming)")

    # Criteria 3: Valid JSON (15 pts)
    if valid_json:
        score += 15
        feedback_parts.append("Valid JSON format")
    else:
        feedback_parts.append("Invalid JSON content")

    # Criteria 4: Django Fixture Structure (15 pts)
    if is_fixture:
        score += 15
        feedback_parts.append("Valid Django fixture structure")
    else:
        feedback_parts.append("JSON is not a valid Django fixture list (missing model/pk fields)")

    # Criteria 5: Registry Models Present (20 pts)
    # Require at least 3 distinct registry model types
    if registry_models_present >= 3:
        score += 20
        feedback_parts.append(f"Contains {registry_models_present} registry model types")
    elif registry_models_present > 0:
        score += 10
        feedback_parts.append(f"Partial credit: Contains only {registry_models_present} registry model types (expected >3)")
    else:
        feedback_parts.append("No 'registry.*' models found in export")

    # Criteria 6: Data Integrity / Counts Match (15 pts)
    # Check a few key models
    key_models = ['registry.aircraft', 'registry.person', 'registry.company']
    match_count = 0
    for model in key_models:
        f_count = file_counts.get(model, 0)
        d_count = db_counts.get(model, 0)
        # We allow file to have MORE (duplicates?) or SAME, but definitely not LESS
        # Actually, dumpdata should be exact.
        if f_count == d_count and d_count > 0:
            match_count += 1
    
    if match_count >= 1:
        score += 15
        feedback_parts.append("Data counts match database verification")
    elif registry_models_present > 0:
        # If we have models but counts don't match exactly, give slight partial
        score += 5
        feedback_parts.append("Data counts mismatch against current database")
    else:
        feedback_parts.append("Data validation failed")

    # Criteria 7: Pretty Print Indentation (10 pts)
    if indent_style == "indent_2":
        score += 10
        feedback_parts.append("Correct 2-space indentation")
    elif indent_style == "indent_4":
        score += 5
        feedback_parts.append("Indented with 4 spaces (requested 2)")
    elif indent_style == "other_multiline":
        score += 5
        feedback_parts.append("Indented but size unclear")
    else:
        feedback_parts.append("File appears compact (not pretty-printed)")

    # Criteria 8: Non-trivial size (5 pts)
    if file_size > 100:
        score += 5
    else:
        feedback_parts.append("File is suspiciously small")

    # Final Pass Calculation
    # Pass if score >= 70 AND valid JSON AND registry models present
    passed = (score >= 70) and valid_json and (registry_models_present > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }