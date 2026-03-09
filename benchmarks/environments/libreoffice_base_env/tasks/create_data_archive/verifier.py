#!/usr/bin/env python3
"""
Verifier for create_data_archive task.

Verification Logic:
1. Extract 'database/script' from the HSQLDB ODB file (it's a ZIP).
2. Parse the script to find:
   - CREATE TABLE statements for Archive tables.
   - INSERT statements for Archive tables (to count archived rows).
   - INSERT statements for Original tables (to count remaining rows).
3. Compare counts against ground truth calculated during setup.
4. Verify data integrity: (Remaining + Archived) should equal Original Total.
"""

import json
import os
import re
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_data_archive(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temporary directory for processing
    work_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch result JSON
        result_json_path = os.path.join(work_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Check basics
        if not result.get("odb_exists", False):
            return {"passed": False, "score": 0, "feedback": "Database file not found."}
        
        if not result.get("odb_modified", False):
            return {"passed": False, "score": 0, "feedback": "Database file was not modified (Checksum identical). Did you save?"}

        # 3. Fetch Ground Truth
        gt_path = os.path.join(work_dir, "ground_truth.json")
        try:
            copy_from_env("/tmp/ground_truth.json", gt_path)
            with open(gt_path, 'r') as f:
                gt = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {str(e)}"}

        # 4. Fetch Database File
        odb_path = os.path.join(work_dir, "chinook.odb")
        copy_from_env("/home/ga/chinook.odb", odb_path)

        # 5. Extract and Parse HSQLDB Script
        # The ODB file is a ZIP. The data is in 'database/script'.
        # HSQLDB persists data as SQL INSERT statements in this file.
        try:
            with zipfile.ZipFile(odb_path, 'r') as zf:
                if 'database/script' not in zf.namelist():
                     return {"passed": False, "score": 0, "feedback": "Invalid ODB file: database/script not found inside archive."}
                
                script_content = zf.read('database/script').decode('utf-8', errors='replace')
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read ODB file content: {str(e)}"}

        # --- Parsing Logic ---
        
        # Helper to count INSERTs for a specific table
        # HSQLDB format: INSERT INTO "TableName" VALUES(...)
        def count_inserts(table_name):
            # Regex handles optional schema "PUBLIC", quoting, and case insensitivity
            pattern = rf'INSERT\s+INTO\s+(?:PUBLIC\.)?"?{re.escape(table_name)}"?\s+VALUES'
            return len(re.findall(pattern, script_content, re.IGNORECASE))

        # Helper to check CREATE TABLE
        def table_exists(table_name):
            pattern = rf'CREATE\s+(?:CACHED\s+|MEMORY\s+|TEXT\s+)?TABLE\s+(?:PUBLIC\.)?"?{re.escape(table_name)}"?\s*\('
            return bool(re.search(pattern, script_content, re.IGNORECASE))
        
        # Helper to check columns (simple string check in the create statement)
        def check_columns(table_name, required_cols):
            # Extract the CREATE TABLE statement content
            pattern = rf'CREATE\s+(?:CACHED\s+|MEMORY\s+|TEXT\s+)?TABLE\s+(?:PUBLIC\.)?"?{re.escape(table_name)}"?\s*\(([^;]+)\)'
            match = re.search(pattern, script_content, re.IGNORECASE)
            if not match:
                return False
            cols_def = match.group(1)
            return all(col in cols_def for col in required_cols)

        score = 0
        feedback_parts = []
        passed = False

        # Criterion A: Tables Created (30 pts)
        inv_archive_exists = table_exists("InvoiceArchive")
        line_archive_exists = table_exists("InvoiceLineArchive")
        
        if inv_archive_exists:
            score += 15
            feedback_parts.append("✅ Table 'InvoiceArchive' created.")
        else:
            feedback_parts.append("❌ Table 'InvoiceArchive' NOT found.")

        if line_archive_exists:
            score += 15
            feedback_parts.append("✅ Table 'InvoiceLineArchive' created.")
        else:
            feedback_parts.append("❌ Table 'InvoiceLineArchive' NOT found.")

        # Criterion B: Data Archived Correctly (40 pts)
        # We allow a small tolerance (+/- 1) for manual selection errors if any
        
        count_inv_archive = count_inserts("InvoiceArchive")
        count_line_archive = count_inserts("InvoiceLineArchive")
        
        expected_inv_archive = gt['archive_invoices']
        expected_line_archive = gt['archive_lines']
        
        # Check InvoiceArchive counts
        if abs(count_inv_archive - expected_inv_archive) <= 1:
            score += 20
            feedback_parts.append(f"✅ 'InvoiceArchive' has correct row count ({count_inv_archive}).")
        elif count_inv_archive > 0:
            score += 5
            feedback_parts.append(f"⚠️ 'InvoiceArchive' has {count_inv_archive} rows (expected {expected_inv_archive}).")
        else:
            feedback_parts.append(f"❌ 'InvoiceArchive' is empty.")

        # Check InvoiceLineArchive counts
        if abs(count_line_archive - expected_line_archive) <= 5: # higher tolerance for cascading lines
            score += 20
            feedback_parts.append(f"✅ 'InvoiceLineArchive' has correct row count ({count_line_archive}).")
        elif count_line_archive > 0:
            score += 5
            feedback_parts.append(f"⚠️ 'InvoiceLineArchive' has {count_line_archive} rows (expected {expected_line_archive}).")
        else:
            feedback_parts.append(f"❌ 'InvoiceLineArchive' is empty.")

        # Criterion C: Original Data Deleted (30 pts)
        
        count_inv_remaining = count_inserts("Invoice") # Matches 'Invoice' but not 'InvoiceArchive' due to quoting in HSQLDB
        # Note: count_inserts regex is strict on table name end. 
        # But 'Invoice' is substring of 'InvoiceArchive'. 
        # HSQLDB usually quotes: INSERT INTO "Invoice" vs INSERT INTO "InvoiceArchive"
        # The regex 'INSERT INTO "Invoice" VALUES' handles this distinction.
        
        count_line_remaining = count_inserts("InvoiceLine")
        
        expected_inv_remaining = gt['remaining_invoices']
        expected_line_remaining = gt['remaining_lines']
        
        if abs(count_inv_remaining - expected_inv_remaining) <= 1:
            score += 15
            feedback_parts.append(f"✅ 'Invoice' table correctly reduced to {count_inv_remaining} rows.")
        elif count_inv_remaining < gt['total_invoices']:
            score += 5
            feedback_parts.append(f"⚠️ 'Invoice' table has {count_inv_remaining} rows (expected {expected_inv_remaining}).")
        else:
            feedback_parts.append(f"❌ 'Invoice' table still has all {count_inv_remaining} rows (no deletion detected).")

        if abs(count_line_remaining - expected_line_remaining) <= 5:
            score += 15
            feedback_parts.append(f"✅ 'InvoiceLine' table correctly reduced to {count_line_remaining} rows.")
        elif count_line_remaining < gt['total_lines']:
            score += 5
            feedback_parts.append(f"⚠️ 'InvoiceLine' table has {count_line_remaining} rows (expected {expected_line_remaining}).")
        else:
            feedback_parts.append(f"❌ 'InvoiceLine' table still has all {count_line_remaining} rows.")

        # Final Pass Check
        # Requires at least: Tables created, some data moved, and score >= 70
        critical_success = inv_archive_exists and line_archive_exists and (count_inv_archive > 0)
        
        if score >= 70 and critical_success:
            passed = True
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)