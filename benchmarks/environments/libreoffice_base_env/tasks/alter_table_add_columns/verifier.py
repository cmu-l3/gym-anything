#!/usr/bin/env python3
"""
Verifier for alter_table_add_columns task.
Checks if specific columns were added to the HSQLDB schema inside the ODB file.
"""

import json
import tempfile
import os
import zipfile
import re
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_hsqldb_script(odb_path):
    """Extracts the 'database/script' file from the ODB zip archive."""
    try:
        with zipfile.ZipFile(odb_path, 'r') as zf:
            # HSQLDB schema is stored in this file
            content = zf.read('database/script').decode('utf-8', errors='replace')
        return content
    except Exception as e:
        logger.error(f"Failed to read ODB file: {e}")
        return None

def parse_customer_table(script_content):
    """
    Parses the CREATE TABLE "Customer" statement from the HSQLDB script.
    Returns a dictionary of column_name -> definition_string.
    """
    # HSQLDB script format usually looks like:
    # CREATE TABLE "Customer"("CustomerId" INTEGER NOT NULL PRIMARY KEY, "FirstName" VARCHAR(40)...)
    # OR sometimes split across lines.
    
    # Regex to find the Customer table definition
    # Look for CREATE TABLE "Customer"(...)
    match = re.search(r'CREATE\s+TABLE\s+"Customer"\s*\((.*?)\)(?:\s*;|\s*$)', script_content, re.DOTALL | re.IGNORECASE)
    
    columns = {}
    if match:
        content = match.group(1)
        # Split by commas, but ignore commas inside quotes or parens if any
        # Simple split for HSQLDB 1.8 usually works as it doesn't use complex nested types often
        # But let's be safer with a basic parser or split
        parts = split_sql_columns(content)
        for part in parts:
            part = part.strip()
            # Extract column name (quoted)
            col_match = re.match(r'"([^"]+)"\s+(.*)', part)
            if col_match:
                name = col_match.group(1)
                definition = col_match.group(2)
                columns[name] = definition
    
    # Also check for ALTER TABLE statements which might exist if the DB wasn't fully compacted
    # ALTER TABLE "Customer" ADD COLUMN "LoyaltyPoints" INTEGER DEFAULT 0
    alter_matches = re.findall(r'ALTER\s+TABLE\s+"Customer"\s+ADD\s+COLUMN\s+"([^"]+)"\s+(.*)', script_content, re.IGNORECASE)
    for name, definition in alter_matches:
        columns[name] = definition

    return columns

def split_sql_columns(content):
    """Helper to split SQL column definitions by comma."""
    parts = []
    current = []
    paren_depth = 0
    quote_open = False
    
    for char in content:
        if char == '"':
            quote_open = not quote_open
        elif char == '(' and not quote_open:
            paren_depth += 1
        elif char == ')' and not quote_open:
            paren_depth -= 1
        elif char == ',' and paren_depth == 0 and not quote_open:
            parts.append("".join(current))
            current = []
            continue
        current.append(char)
    
    if current:
        parts.append("".join(current))
    return parts

def verify_alter_table_add_columns(traj, env_info, task_info):
    """
    Verifies that LoyaltyPoints and MembershipTier columns were added correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb').name
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Get execution result metadata
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get('odb_exists'):
            return {"passed": False, "score": 0, "feedback": "Database file not found"}
            
        # Check modification status (Anti-gaming)
        if result_data.get('odb_modified'):
            score += 10
            feedback_parts.append("Database file modified")
        else:
            feedback_parts.append("Warning: Database file timestamp suggests no changes saved")

        # 2. Get the ODB file for inspection
        copy_from_env("/tmp/result_chinook.odb", temp_odb)
        
        # 3. Extract and Parse Schema
        script_content = extract_hsqldb_script(temp_odb)
        if not script_content:
            return {"passed": False, "score": score, "feedback": "Could not read database schema from ODB"}
            
        columns = parse_customer_table(script_content)
        logger.info(f"Found columns in Customer table: {list(columns.keys())}")
        
        # 4. Verify 'LoyaltyPoints'
        # Expect: INTEGER, Default 0
        lp_def = columns.get("LoyaltyPoints")
        if lp_def:
            score += 20
            feedback_parts.append("LoyaltyPoints column found")
            
            # Check type (INTEGER or INT)
            if "INTEGER" in lp_def.upper() or " INT " in f" {lp_def.upper()} ":
                score += 15
                feedback_parts.append("LoyaltyPoints is INTEGER")
            else:
                feedback_parts.append(f"LoyaltyPoints wrong type: {lp_def}")
                
            # Check default (DEFAULT 0)
            if "DEFAULT 0" in lp_def.upper():
                score += 10
                feedback_parts.append("LoyaltyPoints default is 0")
            else:
                feedback_parts.append("LoyaltyPoints missing correct default value")
        else:
            feedback_parts.append("LoyaltyPoints column missing")

        # 5. Verify 'MembershipTier'
        # Expect: VARCHAR(20), Default 'Bronze'
        mt_def = columns.get("MembershipTier")
        if mt_def:
            score += 20
            feedback_parts.append("MembershipTier column found")
            
            # Check type and length
            upper_def = mt_def.upper()
            if "VARCHAR" in upper_def and "(20)" in upper_def:
                score += 10
                feedback_parts.append("MembershipTier is VARCHAR(20)")
            elif "VARCHAR" in upper_def:
                score += 5
                feedback_parts.append(f"MembershipTier is VARCHAR but wrong length (expected 20)")
            else:
                feedback_parts.append(f"MembershipTier wrong type: {mt_def}")
            
            # Check default ('Bronze')
            # HSQLDB stores strings as 'string'
            if "DEFAULT 'Bronze'" in mt_def or "DEFAULT 'BRONZE'" in upper_def:
                score += 15
                feedback_parts.append("MembershipTier default is 'Bronze'")
            else:
                feedback_parts.append("MembershipTier missing correct default value")
        else:
            feedback_parts.append("MembershipTier column missing")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)
        if os.path.exists(temp_odb):
            os.unlink(temp_odb)

    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }