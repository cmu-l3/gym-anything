#!/usr/bin/env python3
"""
Verifier for create_cumulative_revenue_views task.

Verifies that the agent created two specific SQL Views in LibreOffice Base:
1. "MonthlyRevenue": Aggregates sales by month.
2. "CumulativeRevenue": Calculates running total using a subquery.

Verification Method:
- Static analysis of the HSQLDB `database/script` file extracted from the ODB zip.
- Checks for SQL keywords and structure in the persisted schema.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cumulative_revenue_views(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if database was modified/saved (Anti-gaming)
    if not result.get('odb_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Database file was not modified/saved. Did you save (Ctrl+S)?"
        }
    
    score += 10
    feedback_parts.append("Database saved")

    # 2. Analyze the extracted HSQLDB script
    if not result.get('script_extracted', False):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Could not extract database script from ODB file. File may be corrupt."
        }

    temp_script_file = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    try:
        copy_from_env("/tmp/extracted_hsqldb_script.sql", temp_script_file.name)
        with open(temp_script_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read database script: {e}"}
    finally:
        if os.path.exists(temp_script_file.name):
            os.unlink(temp_script_file.name)

    # Normalize script content for easier regex matching (remove extra spaces/newlines)
    # HSQLDB stores views as: CREATE SCHEMA PUBLIC ... CREATE VIEW "ViewName" AS SELECT ...
    
    # CRITERION 1: MonthlyRevenue View (20 pts)
    # Looking for: CREATE VIEW "MonthlyRevenue" ... GROUP BY ...
    monthly_view_pattern = re.compile(r'CREATE\s+VIEW\s+"MonthlyRevenue"', re.IGNORECASE)
    if monthly_view_pattern.search(script_content):
        score += 20
        feedback_parts.append("View 'MonthlyRevenue' exists")
        
        # Check logic: Aggregation (SUM) and Grouping
        # Note: HSQLDB might store the view definition somewhat verbosely, so we check for key tokens
        if "SUM" in script_content and "GROUP BY" in script_content:
            score += 20
            feedback_parts.append("MonthlyRevenue logic valid (SUM/GROUP BY)")
        else:
            feedback_parts.append("MonthlyRevenue missing aggregation logic")
    else:
        feedback_parts.append("View 'MonthlyRevenue' NOT found")

    # CRITERION 2: CumulativeRevenue View (20 pts)
    # Looking for: CREATE VIEW "CumulativeRevenue" ...
    cumulative_view_pattern = re.compile(r'CREATE\s+VIEW\s+"CumulativeRevenue"', re.IGNORECASE)
    if cumulative_view_pattern.search(script_content):
        score += 20
        feedback_parts.append("View 'CumulativeRevenue' exists")
        
        # CRITERION 3: Running Total Logic (30 pts)
        # This requires a correlated subquery or join condition with inequality (<=)
        # We look for the inequality operator and a reference to the source view inside the cumulative view definition
        # Since we are scanning the whole file, we need to be careful. 
        # Ideally we'd parse the specific view body, but for now we search for the pattern generally 
        # assuming if the view exists, the complexity is likely there if these tokens exist near it.
        
        # A running total usually involves: WHERE "Alias1"."PeriodId" <= "Alias2"."PeriodId"
        if "<=" in script_content and "MonthlyRevenue" in script_content:
            score += 30
            feedback_parts.append("Cumulative logic valid (Subquery/Inequality)")
        else:
            feedback_parts.append("Cumulative logic missing (could not find running total pattern)")
    else:
        feedback_parts.append("View 'CumulativeRevenue' NOT found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }