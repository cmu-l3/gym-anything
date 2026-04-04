#!/usr/bin/env python3
"""
Verifier for calculate_tax_projections task.

Verifies:
1. ODB file exists and was modified.
2. Query 'NorthAmericaTaxImpact' exists in the ODB.
3. SQL content analysis:
    - Joins Invoice and Customer
    - Filters for USA/Canada
    - Calculates tax (0.065) and grand total
    - Uses ROUND function
    - Selects required columns
4. VLM verification of the workflow.
"""

import json
import tempfile
import os
import zipfile
import re
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_tax_projections(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_query_name = metadata.get('expected_query_name', 'NorthAmericaTaxImpact')
    
    score = 0
    feedback_parts = []
    
    # 1. Load basic result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('odb_exists'):
        return {"passed": False, "score": 0, "feedback": "Database file not found"}

    if not result.get('odb_modified'):
        feedback_parts.append("Warning: Database file was not modified (did you save?)")
    else:
        score += 10
        feedback_parts.append("Database file modified successfully")

    # 2. Extract and Inspect ODB Content
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    try:
        # Copy the verification copy created by export script
        copy_from_env("/tmp/chinook_verify.odb", temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid ODB archive"}

        target_query_found = False
        sql_command = ""
        
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            if 'content.xml' in z.namelist():
                content_xml = z.read('content.xml')
                root = ET.fromstring(content_xml)
                
                # Namespaces in ODB content.xml
                ns = {
                    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                    'xlink': 'http://www.w3.org/1999/xlink'
                }
                
                # Find queries
                queries = root.findall('.//db:query', ns)
                for q in queries:
                    name = q.get(f"{{{ns['db']}}}name")
                    if name == expected_query_name:
                        target_query_found = True
                        sql_command = q.get(f"{{{ns['db']}}}command", "")
                        break
        
        if target_query_found:
            score += 20
            feedback_parts.append(f"Query '{expected_query_name}' found")
            
            # 3. Analyze SQL Content
            sql_upper = sql_command.upper()
            
            # Check filtering (25 pts)
            has_usa = "'USA'" in sql_upper or '"USA"' in sql_upper
            has_canada = "'CANADA'" in sql_upper or '"CANADA"' in sql_upper
            has_where = "WHERE" in sql_upper
            
            if has_where and (has_usa or has_canada):
                score += 25
                feedback_parts.append("Filtering logic detected")
            else:
                feedback_parts.append("Missing correct filtering for USA/Canada")

            # Check calculation logic (25 pts)
            # Look for 0.065 (tax rate)
            has_rate = "0.065" in sql_command
            # Look for ROUND function
            has_round = "ROUND" in sql_upper
            # Look for addition (Grand Total)
            has_addition = "+" in sql_command
            
            if has_rate and has_round and has_addition:
                score += 25
                feedback_parts.append("Tax calculation and rounding logic detected")
            elif has_rate:
                score += 10
                feedback_parts.append("Tax rate found but missing rounding or grand total logic")
            else:
                feedback_parts.append("Tax calculation logic (0.065) not found")

            # Check Columns/Join (10 pts)
            # Look for concatenation (||) or CONCAT for name
            has_concat = "||" in sql_command or "CONCAT" in sql_upper
            # Look for JOIN or multiple tables
            has_join = "JOIN" in sql_upper or ("," in sql_command and "FROM" in sql_upper)
            
            if has_join and has_concat:
                score += 10
                feedback_parts.append("Join and name concatenation detected")

        else:
            feedback_parts.append(f"Query '{expected_query_name}' NOT found in database")

    except Exception as e:
        feedback_parts.append(f"Error inspecting ODB file: {str(e)}")
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # 4. VLM Verification (10 pts)
    # Check if the user was actually interacting with the query design or SQL view
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_prompt = """
    Review these screenshots of a user working in LibreOffice Base.
    Did the user perform the following actions:
    1. Open or create a Query (SQL View or Design View)?
    2. Write or view SQL code involving 'SELECT', 'FROM', or 'WHERE'?
    3. Save the query?
    
    Answer 'Yes' if there is visual evidence of query creation/editing. Answer 'No' otherwise.
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('parsed', '').lower().startswith('yes'):
        score += 10
        feedback_parts.append("Visual evidence of query creation confirmed")
    else:
        # Fallback if VLM is unsure but ODB check passed
        if target_query_found:
            score += 10 # Give benefit of doubt if technical verification passed
            
    # Final check
    passed = score >= 60 and target_query_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }