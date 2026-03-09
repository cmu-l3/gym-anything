#!/usr/bin/env python3
"""
Verifier for normalize_address_table task.

Verifies:
1. 'CustomerAddress' table exists in the ODB file.
2. Table has correct schema (7 specific columns, PK, NOT NULL).
3. Table contains exactly 59 rows copied from Customer.
4. Data integrity check on specific records (spot checks).
5. Database was actually modified during the task.
"""

import json
import os
import zipfile
import re
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_normalize_address_table(traj, env_info, task_info):
    """
    Verify the LibreOffice Base migration task by inspecting the ODB file.
    The ODB file is a ZIP containing a 'database/script' file (HSQLDB).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_rows = metadata.get('expected_row_count', 59)
    spot_checks = metadata.get('spot_checks', [])

    score = 0
    feedback_parts = []
    
    # Temporary directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Fetch result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check basics
        if not result.get("db_exists"):
            return {"passed": False, "score": 0, "feedback": "Database file not found"}
        
        if not result.get("db_modified"):
            feedback_parts.append("WARNING: Database file timestamp not updated (did you save?)")
            # We don't fail immediately, maybe they saved very quickly, but it's suspicious.
        else:
            score += 5
            feedback_parts.append("Database file saved")

        # 2. Fetch ODB file
        submitted_db_path = result.get("submitted_db_path")
        local_odb_path = os.path.join(temp_dir, "chinook.odb")
        try:
            copy_from_env(submitted_db_path, local_odb_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {e}"}

        # 3. Extract and Parse HSQLDB Script
        # LibreOffice Base (HSQLDB embedded) stores SQL structure in database/script inside the ZIP
        db_script_content = ""
        try:
            with zipfile.ZipFile(local_odb_path, 'r') as z:
                if 'database/script' in z.namelist():
                    db_script_content = z.read('database/script').decode('utf-8', errors='replace')
                else:
                    return {"passed": False, "score": score, "feedback": "Invalid ODB format: database/script missing"}
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Corrupt ODB file"}

        # --- Verification Logic ---
        
        # A. Check Table Creation (DDL)
        # Look for: CREATE TABLE "CustomerAddress" (...)
        # HSQLDB stores names in quotes if they preserve case
        table_regex = re.search(r'CREATE\s+TABLE\s+(PUBLIC\.)?"CustomerAddress"\s*\((.*?)\)', db_script_content, re.IGNORECASE | re.DOTALL)
        
        if table_regex:
            score += 15
            feedback_parts.append("Table 'CustomerAddress' created")
            
            columns_def = table_regex.group(2)
            
            # Check columns
            required_cols = ["AddressId", "CustomerId", "Address", "City", "State", "Country", "PostalCode"]
            missing_cols = [col for col in required_cols if f'"{col}"' not in columns_def]
            
            if not missing_cols:
                score += 15
                feedback_parts.append("All columns present")
            else:
                feedback_parts.append(f"Missing columns: {', '.join(missing_cols)}")

            # Check Primary Key
            if '"AddressId" INTEGER' in columns_def and 'PRIMARY KEY' in columns_def and ('"AddressId"' in columns_def.split('PRIMARY KEY')[1] if 'CONSTRAINT' in columns_def else True):
                score += 5
                feedback_parts.append("Primary Key defined")
            
            # Check Not Null on CustomerId
            if '"CustomerId" INTEGER NOT NULL' in columns_def:
                score += 5
                feedback_parts.append("CustomerId is NOT NULL")

        else:
            feedback_parts.append("Table 'CustomerAddress' NOT found in schema")

        # B. Check Data Insertion (DML)
        # Look for: INSERT INTO "CustomerAddress" VALUES(...)
        # HSQLDB script format: INSERT INTO "CustomerAddress" VALUES(1,1,'Street',...)
        
        insert_matches = re.findall(r'INSERT\s+INTO\s+(PUBLIC\.)?"CustomerAddress"\s+VALUES\((.*?)\)', db_script_content, re.IGNORECASE)
        row_count = len(insert_matches)
        
        if row_count == expected_rows:
            score += 20
            feedback_parts.append(f"Correct row count ({row_count})")
        elif row_count > 0:
            # Partial credit for some data
            score += 10
            feedback_parts.append(f"Incorrect row count: {row_count} (expected {expected_rows})")
        else:
            feedback_parts.append("No data inserted into CustomerAddress")

        # C. Spot Checks (Value Verification)
        # We need to parse the VALUES part. It's CSV-like but strings are single-quoted.
        # Simple parser for our known structure: 
        # VALUES(AddressId, CustomerId, 'Address', 'City', 'State', 'Country', 'PostalCode')
        
        checks_passed = 0
        checks_total = len(spot_checks)
        check_points_total = 25 # Allocation for spot checks
        
        # Create a map of AddressId -> data string for easy lookup
        # Assuming AddressId is the first value
        data_map = {} 
        for _, val_str in insert_matches:
            # simple split by comma might fail on commas in addresses, but usually ODB escapes them safely or we rely on simple structure here.
            # HSQLDB output: VALUES(1,1,'Address','City','State','Country','Postal')
            parts = val_str.split(',') 
            try:
                # The first item is AddressId (int)
                a_id = int(parts[0].strip())
                data_map[a_id] = val_str
            except ValueError:
                continue

        for check in spot_checks:
            cid = check['id']
            city = check['city']
            country = check['country']
            
            if cid in data_map:
                row_data = data_map[cid]
                # Check if city and country string exist in the row data
                # We use simple substring check to handle potential SQL escaping ('Brazil' vs 'Brazil')
                city_match = f"'{city}'" in row_data
                country_match = f"'{country}'" in row_data
                
                if city_match and country_match:
                    checks_passed += 1
                else:
                    logger.info(f"Spot check failed for ID {cid}: expected {city}/{country} in {row_data}")
            else:
                logger.info(f"Spot check failed: ID {cid} not found")

        if checks_total > 0:
            spot_score = int((checks_passed / checks_total) * check_points_total)
            score += spot_score
            if checks_passed == checks_total:
                feedback_parts.append("All data spot checks passed")
            elif checks_passed > 0:
                feedback_parts.append(f"Partial spot checks passed ({checks_passed}/{checks_total})")
            else:
                feedback_parts.append("Data verification failed")
        
        # D. Appropriate Column Types (heuristic)
        if table_regex:
            columns_def = table_regex.group(2)
            if "VARCHAR" in columns_def and "INTEGER" in columns_def:
                score += 10
                feedback_parts.append("Column types valid")

    # Final Score Calculation
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }