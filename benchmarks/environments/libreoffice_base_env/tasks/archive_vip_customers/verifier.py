#!/usr/bin/env python3
"""
Verifier for archive_vip_customers task.
Checks if 'GalaInvitees' table exists in ODB and contains correct top 15 customers.
"""

import json
import zipfile
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hsqldb_script(script_content):
    """
    Parses HSQLDB script for CREATE TABLE and INSERT statements regarding GalaInvitees.
    Returns:
        table_def (str): The create table statement if found.
        inserts (list): List of tuples (CustomerId, FullName, Email, TotalSpent).
    """
    table_def = None
    inserts = []
    
    # Normalize line endings
    lines = script_content.splitlines()
    
    # 1. Find CREATE TABLE
    # Pattern: CREATE TABLE "GalaInvitees" (...)
    # HSQLDB usually stores it as: CREATE TABLE "GalaInvitees"("CustomerId" INTEGER NOT NULL PRIMARY KEY, ...)
    # or CREATE TABLE PUBLIC."GalaInvitees"
    for line in lines:
        if 'CREATE TABLE' in line and '"GalaInvitees"' in line:
            table_def = line
            break
            
    # 2. Find INSERTS
    # Pattern: INSERT INTO "GalaInvitees" VALUES(6,'Helena Holy','hholy@gmail.com',49.62)
    # Note: Strings are single-quoted. HSQLDB escapes ' as ''.
    
    # Regex to capture values inside VALUES(...)
    # This is a basic parser; might struggle with complex nested quotes but sufficient for this task's simple data
    insert_pattern = re.compile(r'INSERT INTO (?:PUBLIC\.)?"GalaInvitees" VALUES\((.+)\)')
    
    for line in lines:
        match = insert_pattern.search(line)
        if match:
            val_str = match.group(1)
            # Simple CSV split respecting quotes is hard with regex alone, 
            # but HSQLDB format is fairly regular for these types.
            # We'll use a simple state machine parser for the values
            
            parts = []
            current = []
            in_quote = False
            for char in val_str:
                if char == "'" and (not current or current[-1] != '\\'): # Simple quote check
                    in_quote = not in_quote
                elif char == ',' and not in_quote:
                    parts.append("".join(current))
                    current = []
                    continue
                current.append(char)
            parts.append("".join(current))
            
            # Clean up parts
            cleaned_parts = []
            for p in parts:
                p = p.strip()
                if p.startswith("'") and p.endswith("'"):
                    p = p[1:-1] # Remove quotes
                cleaned_parts.append(p)
                
            if len(cleaned_parts) >= 4:
                try:
                    c_id = int(cleaned_parts[0])
                    name = cleaned_parts[1]
                    email = cleaned_parts[2]
                    spent = float(cleaned_parts[3])
                    inserts.append((c_id, name, email, spent))
                except ValueError:
                    continue # Skip malformed rows
                    
    return table_def, inserts

def verify_archive_vip_customers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # 1. Copy result JSON (contains ground truth)
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        ground_truth = result_data.get('ground_truth', [])
        odb_modified = result_data.get('odb_modified', False)
        
        # 2. Copy ODB file
        copy_from_env("/home/ga/chinook.odb", temp_odb.name)
        
        # 3. Analyze ODB content
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 0, "feedback": "Saved file is not a valid ODB (zip) archive."}
            
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            if 'database/script' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Corrupt ODB: missing database/script."}
            
            with z.open('database/script') as script_file:
                script_content = script_file.read().decode('utf-8', errors='replace')
                
        table_def, inserts = parse_hsqldb_script(script_content)
        
        # --- Scoring ---
        score = 0
        feedback = []
        
        # Criterion 1: Table Creation (20 pts)
        if table_def:
            score += 20
            feedback.append("Table 'GalaInvitees' created.")
        else:
            feedback.append("Table 'GalaInvitees' NOT found.")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
            
        # Criterion 2: Correct Row Count (20 pts)
        row_count = len(inserts)
        if row_count == 15:
            score += 20
            feedback.append("Correct row count (15).")
        else:
            feedback.append(f"Incorrect row count: {row_count} (expected 15).")
            
        # Criterion 3: Data Accuracy (40 pts)
        # We check if the inserted customers match the ground truth
        # Ground truth format: [{'CustomerId': 1, 'FullName': '...', ...}, ...]
        
        gt_map = {item['CustomerId']: item for item in ground_truth}
        
        correct_ids = 0
        correct_names = 0
        correct_values = 0
        
        for row in inserts:
            cid, name, email, spent = row
            
            if cid in gt_map:
                correct_ids += 1
                gt_item = gt_map[cid]
                
                # Check Name format (FirstName LastName)
                # We expect the agent to have concatenated correctly
                if name.lower().strip() == gt_item['FullName'].lower().strip():
                    correct_names += 1
                
                # Check Total Spent (within 0.1 tolerance)
                if abs(spent - gt_item['TotalSpent']) < 0.1:
                    correct_values += 1
        
        # Score calculation for data
        # Max 40 pts for data (split across ID, Name, Value)
        
        # IDs (Selection logic)
        id_score = min(20, (correct_ids / 15) * 20)
        score += id_score
        
        # Values (Accuracy)
        val_score = min(10, (correct_values / 15) * 10)
        score += val_score
        
        # Name Formatting (String manipulation)
        name_score = min(10, (correct_names / 15) * 10)
        score += name_score
        
        if correct_ids < 15:
            feedback.append(f"Only {correct_ids}/15 correct customers selected.")
        if correct_names < 15:
            feedback.append(f"Name formatting issues in {15 - correct_names} rows.")
        if correct_values < 15:
            feedback.append(f"Spending value mismatches in {15 - correct_values} rows.")
            
        # Criterion 4: Persistence (10 pts)
        if odb_modified:
            score += 10
            feedback.append("Database saved successfully.")
        else:
            feedback.append("Warning: Database file timestamp not updated (did you save?).")

        passed = (score >= 80)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": " ".join(feedback),
            "details": {
                "rows_found": row_count,
                "correct_customers": correct_ids,
                "correct_names": correct_names,
                "table_found": bool(table_def)
            }
        }
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)