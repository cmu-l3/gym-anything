#!/usr/bin/env python3
"""
Verifier for transfer_region_accounts task.

Verification Strategy:
1. Extract the 'chinook.odb' file (which is a ZIP archive).
2. Read the 'database/script' file from within the ZIP.
   - This text file contains the SQL 'INSERT' statements that represent the DB state.
3. Parse the 'TransferLog' table to ensure:
   - It exists.
   - It contains records for the specific customers transferred.
4. Parse the 'Customer' table to ensure:
   - Transferred customers now have SupportRepId = 4.
   - Non-transferred customers (e.g., Brazil) still have SupportRepId = 3.
"""

import json
import os
import zipfile
import re
import shutil
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth Data (Standard Chinook Dataset)
# Jane Peacock (EmployeeId 3) Customers in USA or Canada
# Extracted from standard Chinook data
TARGET_CUSTOMER_IDS = {
    14, 15, 29, 30, 31, 32, 33,  # Canada
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28  # USA
}
# Jane Peacock Customers NOT in USA/Canada (Should NOT change)
PRESERVE_CUSTOMER_IDS = {
    1, 2, 3, 4, 5,  # Brazil
    39, 40, 41, 42, 43,  # France
    58, 59  # India
}


def parse_hsqldb_script(script_content):
    """
    Parses HSQLDB script content to extract table data.
    Returns a dictionary of tables, where each table is a list of rows (lists of values).
    Crude parser sufficient for standard HSQLDB INSERT statements.
    """
    tables = {}
    
    # Regex to match INSERT INTO "TableName" VALUES(val1, val2, ...)
    # This is simplified; HSQLDB values are usually comma-separated literals.
    # Strings are single-quoted.
    insert_pattern = re.compile(r'INSERT INTO "([^"]+)" VALUES\((.+)\)')
    
    for line in script_content.splitlines():
        if not line.startswith("INSERT INTO"):
            continue
            
        match = insert_pattern.match(line)
        if match:
            table_name = match.group(1)
            values_str = match.group(2)
            
            # Simple CSV parsing for values (handling quoted strings with commas is tricky, 
            # but for IDs we generally look at the start/end or integers)
            # For this task, we mainly need CustomerId (index 0) and SupportRepId (index 12 for Customer)
            
            # We'll split by comma but respect quotes (quick and dirty)
            values = []
            current_val = []
            in_quote = False
            for char in values_str:
                if char == "'":
                    in_quote = not in_quote
                    current_val.append(char)
                elif char == ',' and not in_quote:
                    values.append("".join(current_val).strip())
                    current_val = []
                else:
                    current_val.append(char)
            values.append("".join(current_val).strip())
            
            if table_name not in tables:
                tables[table_name] = []
            tables[table_name].append(values)
            
    return tables


def verify_transfer_region_accounts(traj, env_info, task_info):
    """Verify the account transfer task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Create temp directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Get Result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        if not result_data.get("odb_modified", False):
            return {"passed": False, "score": 0, "feedback": "Database file was not modified or saved."}
        
        score += 10
        feedback.append("Database file modified.")

        # 2. Get ODB File
        odb_local_path = os.path.join(temp_dir, "chinook_result.odb")
        try:
            copy_from_env("/tmp/chinook_result.odb", odb_local_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {e}"}

        # 3. Extract and Parse 'database/script'
        try:
            with zipfile.ZipFile(odb_local_path, 'r') as zf:
                if 'database/script' not in zf.namelist():
                    return {"passed": False, "score": score, "feedback": "Invalid ODB file (missing database/script)."}
                
                with zf.open('database/script') as script_file:
                    script_content = script_file.read().decode('utf-8', errors='replace')
                    
            db_data = parse_hsqldb_script(script_content)
            
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "ODB file is corrupted or not a valid zip."}

        # 4. Verify 'TransferLog' Table
        if "TransferLog" in db_data:
            score += 20
            feedback.append("TransferLog table created.")
            
            logs = db_data["TransferLog"]
            # Expected columns: CustomerId, OldRepId, NewRepId, TransferDate
            # We just check if the CustomerId (usually first column) matches our target set
            
            logged_ids = set()
            correct_log_details = True
            
            for row in logs:
                try:
                    cust_id = int(row[0])
                    old_rep = int(row[1]) if len(row) > 1 else -1
                    new_rep = int(row[2]) if len(row) > 2 else -1
                    
                    logged_ids.add(cust_id)
                    
                    if old_rep != 3 or new_rep != 4:
                        correct_log_details = False
                except ValueError:
                    continue # header or malformed
            
            # Check overlap with target
            common = logged_ids.intersection(TARGET_CUSTOMER_IDS)
            missing = TARGET_CUSTOMER_IDS - logged_ids
            
            if len(common) == len(TARGET_CUSTOMER_IDS):
                score += 30
                feedback.append(f"All {len(TARGET_CUSTOMER_IDS)} target customers logged correctly.")
            elif len(common) > 0:
                score += int(30 * (len(common) / len(TARGET_CUSTOMER_IDS)))
                feedback.append(f"Logged {len(common)}/{len(TARGET_CUSTOMER_IDS)} customers.")
            else:
                feedback.append("No correct customers found in TransferLog.")
                
            if not correct_log_details:
                feedback.append("Warning: Log entries have incorrect Rep IDs (Expected 3 -> 4).")
        else:
            feedback.append("TransferLog table NOT found.")

        # 5. Verify 'Customer' Table Updates
        if "Customer" in db_data:
            customers = db_data["Customer"]
            
            transferred_correctly = 0
            preserved_correctly = 0
            failed_transfers = 0
            
            for row in customers:
                try:
                    # Customer table structure in Chinook:
                    # 0: CustomerId, ..., 12: SupportRepId
                    cust_id = int(row[0])
                    rep_id = int(row[12])
                    
                    if cust_id in TARGET_CUSTOMER_IDS:
                        if rep_id == 4:
                            transferred_correctly += 1
                        else:
                            failed_transfers += 1
                            
                    if cust_id in PRESERVE_CUSTOMER_IDS:
                        if rep_id == 3:
                            preserved_correctly += 1
                        else:
                            # They moved someone they shouldn't have!
                            pass
                            
                except (ValueError, IndexError):
                    continue
            
            # Score Transfer
            if transferred_correctly == len(TARGET_CUSTOMER_IDS):
                score += 30
                feedback.append("All target customers transferred successfully.")
            else:
                score += int(30 * (transferred_correctly / len(TARGET_CUSTOMER_IDS)))
                feedback.append(f"Transferred {transferred_correctly}/{len(TARGET_CUSTOMER_IDS)} customers.")
                
            # Score Preservation (Anti-destruction)
            if preserved_correctly == len(PRESERVE_CUSTOMER_IDS):
                score += 10
                feedback.append("Other customers correctly preserved.")
            else:
                feedback.append(f"Warning: {len(PRESERVE_CUSTOMER_IDS) - preserved_correctly} unrelated customers were incorrectly modified.")
                
        else:
            feedback.append("Customer table data not found (critical error).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }