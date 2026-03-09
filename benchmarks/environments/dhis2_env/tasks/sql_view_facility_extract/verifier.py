#!/usr/bin/env python3
"""
Verifier for sql_view_facility_extract task.

Scoring (100 points):
- SQL View created (25 pts) [MANDATORY]
- SQL View returns data (rows >= 5) (20 pts)
- SQL Query is valid/non-empty (15 pts)
- SQL Query references 'organisationunit' table (10 pts) - Anti-gaming
- Download file exists (20 pts)
- Download file has content (>500 bytes) (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sql_view_extract(traj, env_info, task_info):
    """Verify SQL View creation and data export."""
    
    # 1. Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # 2. Retrieve result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/task_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
        
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    # 3. Parse Results
    score = 0
    feedback_parts = []
    
    # Data extraction
    sql_search = result.get('sql_view_search', {})
    view_found = sql_search.get('found', False)
    views = sql_search.get('views', [])
    
    execution = result.get('execution', {})
    row_count = int(execution.get('row_count', 0))
    
    downloads = result.get('downloads', {})
    dl_count = downloads.get('count', 0)
    dl_files = downloads.get('files', [])

    # Criterion 1: SQL View Exists (Mandatory)
    if not view_found or not views:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No SQL View found with 'Kenema' in the name. You must create and save the SQL View."
        }
    
    score += 25
    feedback_parts.append("SQL View created (+25)")
    
    # Get the best matching view (the one we executed)
    view = views[0]
    query_content = view.get('query', '').lower()
    
    # Criterion 2: Query Content (Anti-gaming)
    if query_content and len(query_content) > 10:
        score += 15
        feedback_parts.append("Query content present (+15)")
        
        if 'organisationunit' in query_content:
            score += 10
            feedback_parts.append("Query references correct table (+10)")
        else:
            feedback_parts.append("Query does not reference 'organisationunit' table")
    else:
        feedback_parts.append("Query appears empty or too short")

    # Criterion 3: Execution Results
    if row_count >= 5:
        score += 20
        feedback_parts.append(f"View execution successful ({row_count} rows) (+20)")
    elif row_count > 0:
        score += 10
        feedback_parts.append(f"View execution returned few rows ({row_count}) (+10)")
    else:
        feedback_parts.append("View execution returned 0 rows. Check your SQL WHERE clause.")

    # Criterion 4: Downloaded File
    if dl_count > 0:
        score += 20
        feedback_parts.append(f"File downloaded (+20)")
        
        # Check size of largest file
        max_size = max([f.get('size', 0) for f in dl_files])
        if max_size >= 500:
            score += 10
            feedback_parts.append("File has content (+10)")
        else:
            feedback_parts.append("Downloaded file is empty or too small")
    else:
        feedback_parts.append("No file found in Downloads folder")

    # Final Pass/Fail
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }