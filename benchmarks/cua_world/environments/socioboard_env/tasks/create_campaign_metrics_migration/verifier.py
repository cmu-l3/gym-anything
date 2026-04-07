#!/usr/bin/env python3
"""
Verifier for create_campaign_metrics_migration task.

Evaluates:
1. Table existence and correct schema mapping in the database (via MySQL inspections)
2. Existence and properties of the generated migration file
3. Anti-gaming check to ensure migration wasn't mocked manually before the task started
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_campaign_metrics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    table_exists = result.get("table_exists", False)
    columns = result.get("columns", [])
    mig_exists = result.get("migration_exists", False)
    mig_has_create = result.get("migration_has_create", False)
    mig_has_drop = result.get("migration_has_drop", False)
    task_start = result.get("task_start", 0)
    mig_mtime = result.get("migration_mtime", 0)
    
    # -----------------------------------------------------------------
    # Criterion 1: Table Exists (30 points)
    # -----------------------------------------------------------------
    if table_exists:
        score += 30
        feedback_parts.append("Table campaign_metrics exists (+30)")
    else:
        feedback_parts.append("Table campaign_metrics does NOT exist in DB")
        
    # -----------------------------------------------------------------
    # Criterion 2: Migration File (15 points) and Timestamp Checks
    # -----------------------------------------------------------------
    if mig_exists:
        # Give a small margin (10s) for script execution speeds
        if mig_mtime >= task_start - 10:
            score += 15
            feedback_parts.append("Migration file properly created (+15)")
        else:
            feedback_parts.append("Migration file created BEFORE task started (anti-gaming block)")
    else:
        feedback_parts.append("No suitable migration file found")
        
    # -----------------------------------------------------------------
    # Criterion 3: Migration is Reversible (5 points)
    # -----------------------------------------------------------------
    if mig_has_create and mig_has_drop:
        score += 5
        feedback_parts.append("Migration is reversible (+5)")
    elif mig_has_create:
        score += 2
        feedback_parts.append("Migration has createTable but missing dropTable (+2)")
        
    # -----------------------------------------------------------------
    # Criterion 4: Schema Column Validations (50 points maximum)
    # -----------------------------------------------------------------
    expected_columns = {
        'id': {'types': ['int', 'bigint', 'integer'], 'pts': 4.5},
        'campaign_name': {'types': ['varchar', 'char', 'text'], 'pts': 4.5},
        'platform': {'types': ['varchar', 'char', 'text'], 'pts': 4.5},
        'impressions': {'types': ['bigint', 'int', 'integer'], 'pts': 4.5},
        'clicks': {'types': ['bigint', 'int', 'integer'], 'pts': 4.5},
        'engagement_rate': {'types': ['float', 'double', 'decimal', 'real'], 'pts': 5.0},
        'spend_cents': {'types': ['int', 'integer', 'bigint'], 'pts': 4.5},
        'start_date': {'types': ['date', 'datetime', 'timestamp'], 'pts': 4.5},
        'end_date': {'types': ['date', 'datetime', 'timestamp'], 'pts': 4.5},
        'createdAt': {'types': ['datetime', 'timestamp', 'date'], 'pts': 4.5, 'aliases': ['createdat', 'created_at']},
        'updatedAt': {'types': ['datetime', 'timestamp', 'date'], 'pts': 4.5, 'aliases': ['updatedat', 'updated_at']}
    }
    
    col_score = 0
    cols_found = 0
    
    for exp_name, spec in expected_columns.items():
        search_names = [exp_name.lower()]
        if 'aliases' in spec:
            search_names.extend([a.lower() for a in spec['aliases']])
            
        found_col = next((c for c in columns if c.get('name', '').lower() in search_names), None)
        
        if found_col:
            actual_type = found_col.get('type', '').lower()
            if any(t in actual_type for t in spec['types']):
                col_score += spec['pts']
                cols_found += 1
            else:
                # Assign half points if the column exists but has the wrong type constraint
                col_score += spec['pts'] * 0.5
                
    col_score_int = int(round(min(col_score, 50)))
    score += col_score_int
    
    if table_exists:
        feedback_parts.append(f"Columns correctly matched: {cols_found}/11 (+{col_score_int})")

    # Anti-gaming checks on tables
    current_tables = result.get('current_tables', 0)
    initial_tables = result.get('initial_tables', 0)
    if not table_exists and current_tables <= initial_tables:
        pass # Zero additional penalty since they didn't succeed
        
    passed = score >= 65 and table_exists and mig_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }