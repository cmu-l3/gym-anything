#!/usr/bin/env python3
"""
Verifier for patient_completeness_score task.

Checks:
1. CSV file exists and was created during task.
2. CSV content matches the Ground Truth calculated from the database state.
   - Completeness Score logic (9 specific fields)
   - Correct ranking (Ascending by score)
   - Correct identification of missing fields
"""

import json
import csv
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# The 9 fields defined in the task
FIELDS_TO_CHECK = {
    'FchPat_NomFille': 'Last Name',
    'FchPat_Nee': 'Date of Birth',
    'FchPat_Sexe': 'Sex',
    'FchPat_Titre': 'Title',
    'FchPat_Adresse': 'Address',
    'FchPat_CP': 'Postal Code',
    'FchPat_Ville': 'City',
    'FchPat_Tel1': 'Phone',
    'FchPat_NumSS': 'SSN'
}

def is_populated(value):
    """Check if a DB value is considered populated (not None, not empty string)."""
    if value is None:
        return False
    if isinstance(value, str):
        return len(value.strip()) > 0
    # For dates/numbers, if they are not None, they are populated
    return True

def calculate_score(record):
    """Calculate completeness stats for a DB record."""
    missing = []
    present_count = 0
    
    for field in FIELDS_TO_CHECK.keys():
        val = record.get(field)
        if is_populated(val):
            present_count += 1
        else:
            missing.append(field)
            
    score = round((present_count / 9.0) * 100, 1)
    return {
        'score': score,
        'count': present_count,
        'missing': sorted(missing)
    }

def verify_patient_completeness_score(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # 1. Load Task Result Metadata
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
            
        if not result_meta.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
            
        if not result_meta.get('created_during_task'):
             return {"passed": False, "score": 0, "feedback": "Output CSV file was not created/modified during the task."}

        # 2. Load Agent's CSV
        copy_from_env(result_meta['csv_path'], temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            agent_rows = list(reader)
            agent_headers = reader.fieldnames
            
        # 3. Load DB Ground Truth
        copy_from_env(result_meta['db_dump_path'], temp_db.name)
        with open(temp_db.name, 'r') as f:
            db_rows = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading task files: {str(e)}"}
    finally:
        for tmp in [temp_result, temp_csv, temp_db]:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # === SCORING LOGIC ===
    score = 0
    feedback = []
    
    # Criterion 1: CSV Structure (10 pts)
    required_cols = ['guid', 'nom', 'prenom', 'fields_populated', 'completeness_pct', 'missing_fields']
    if agent_headers and all(col in agent_headers for col in required_cols):
        score += 10
        feedback.append("CSV headers correct.")
    else:
        feedback.append(f"Missing columns. Found: {agent_headers}")
        # Critical failure if we can't parse rows
        if not agent_headers or 'guid' not in agent_headers:
             return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 2: Row Count (10 pts)
    if len(agent_rows) == len(db_rows):
        score += 10
        feedback.append(f"Row count correct ({len(db_rows)}).")
    else:
        feedback.append(f"Row count mismatch: Agent {len(agent_rows)}, DB {len(db_rows)}.")

    # Criterion 3: Accuracy Check (50 pts)
    # We create a map of DB stats to compare efficiently
    db_stats = {}
    for row in db_rows:
        stats = calculate_score(row)
        db_stats[row['guid']] = stats

    accuracy_errors = 0
    missing_field_errors = 0
    
    for agent_row in agent_rows:
        guid = agent_row.get('guid')
        if guid not in db_stats:
            accuracy_errors += 1
            continue
            
        expected = db_stats[guid]
        
        # Check Score
        try:
            agent_score = float(agent_row.get('completeness_pct', -1))
        except:
            agent_score = -1
            
        if abs(agent_score - expected['score']) > 0.11: # float tolerance
            accuracy_errors += 1
        
        # Check Count
        try:
            agent_count = int(agent_row.get('fields_populated', -1))
        except:
            agent_count = -1
        
        if agent_count != expected['count']:
            accuracy_errors += 1
            
        # Check Missing Fields list (parse pipe separated)
        agent_missing_str = agent_row.get('missing_fields', '')
        agent_missing = sorted([x.strip() for x in agent_missing_str.split('|') if x.strip()])
        if agent_missing != expected['missing']:
            # Allow for potential ordering differences or minor naming quirks if logical match?
            # Task asked for "FchPat_Tel1", etc. strictly.
            missing_field_errors += 1

    # Scoring Accuracy
    total_records = len(db_rows)
    if total_records > 0:
        accuracy_pct = (total_records - accuracy_errors) / total_records
        score += int(30 * accuracy_pct)
        if accuracy_pct > 0.9: feedback.append("Score calculations accurate.")
        else: feedback.append(f"Score calc errors in {accuracy_errors} records.")
        
        missing_acc_pct = (total_records - missing_field_errors) / total_records
        score += int(20 * missing_acc_pct)
        if missing_acc_pct > 0.9: feedback.append("Missing fields lists accurate.")
        else: feedback.append(f"Missing fields list errors in {missing_field_errors} records.")

    # Criterion 4: Sorting Order (30 pts)
    # Expected: Ascending by completeness_pct
    sorted_correctly = True
    prev_val = -1.0
    for row in agent_rows:
        try:
            val = float(row.get('completeness_pct', 0))
            if val < prev_val:
                sorted_correctly = False
                break
            prev_val = val
        except:
            sorted_correctly = False
            break
    
    if sorted_correctly and len(agent_rows) > 0:
        score += 30
        feedback.append("Sorting order correct (Ascending).")
    else:
        feedback.append("Sorting order incorrect.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }