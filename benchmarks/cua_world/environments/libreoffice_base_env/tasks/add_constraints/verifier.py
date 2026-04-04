#!/usr/bin/env python3
"""
Verifier for add_constraints task.

Checks the HSQLDB script file extracted from the ODB to verify:
1. CHECK constraints (CK_Track_Price, CK_Invoice_Total, CK_Customer_Email)
2. DEFAULT value on Customer.Country
3. Creation and population of DataQualityRule table
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_constraints(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check if ODB was modified
    if not result.get('odb_modified', False):
        return {"passed": False, "score": 0, "feedback": "Database file was not saved/modified."}

    # 2. Retrieve Database Script
    if not result.get('script_exported', False):
        return {"passed": False, "score": 0, "feedback": "Could not extract database script for verification."}
        
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/database_script.txt", temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read database script: {e}"}
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # 3. Analyze Script Content
    # HSQLDB 1.8 script format usually has CREATE TABLE statements or ALTER TABLE statements
    # We search for the specific constraint definitions.
    
    # Check 1: CK_Track_Price (15 pts)
    # Pattern: CONSTRAINT "CK_Track_Price" CHECK("UnitPrice">=0)
    # Note: Spaces might vary, and HSQLDB uppercases SQL keywords
    ck_track_pattern = re.compile(r'CONSTRAINT\s+"CK_Track_Price"\s+CHECK', re.IGNORECASE)
    if ck_track_pattern.search(script_content) and 'UnitPrice' in script_content:
         score += 15
         feedback_parts.append("CK_Track_Price constraint found.")
    else:
         feedback_parts.append("Missing CK_Track_Price constraint.")

    # Check 2: CK_Invoice_Total (15 pts)
    ck_invoice_pattern = re.compile(r'CONSTRAINT\s+"CK_Invoice_Total"\s+CHECK', re.IGNORECASE)
    if ck_invoice_pattern.search(script_content) and 'Total' in script_content:
        score += 15
        feedback_parts.append("CK_Invoice_Total constraint found.")
    else:
        feedback_parts.append("Missing CK_Invoice_Total constraint.")

    # Check 3: CK_Customer_Email (15 pts)
    ck_email_pattern = re.compile(r'CONSTRAINT\s+"CK_Customer_Email"\s+CHECK', re.IGNORECASE)
    if ck_email_pattern.search(script_content) and ('@' in script_content or 'LIKE' in script_content):
        score += 15
        feedback_parts.append("CK_Customer_Email constraint found.")
    else:
        feedback_parts.append("Missing CK_Customer_Email constraint.")

    # Check 4: DEFAULT 'USA' on Customer.Country (10 pts)
    # HSQLDB: ALTER TABLE "Customer" ALTER COLUMN "Country" SET DEFAULT 'USA'
    # Or inside CREATE TABLE: "Country" VARCHAR(..) DEFAULT 'USA'
    default_pattern = re.compile(r'DEFAULT\s+\'USA\'', re.IGNORECASE)
    customer_country_ctx = re.search(r'CREATE\s+TABLE\s+.*"Customer".*\(.*?\)', script_content, re.DOTALL | re.IGNORECASE)
    
    found_default = False
    if default_pattern.search(script_content):
        # Simplistic check: if "DEFAULT 'USA'" exists anywhere, likely correct in this context
        found_default = True
    
    if found_default:
        score += 10
        feedback_parts.append("Default 'USA' found.")
    else:
        feedback_parts.append("Missing DEFAULT 'USA' for Customer Country.")

    # Check 5: DataQualityRule Table Structure (20 pts)
    # Look for CREATE TABLE "DataQualityRule"
    table_pattern = re.compile(r'CREATE\s+TABLE\s+.*"DataQualityRule"', re.IGNORECASE)
    if table_pattern.search(script_content):
        score += 20
        feedback_parts.append("DataQualityRule table created.")
    else:
        feedback_parts.append("DataQualityRule table missing.")

    # Check 6: Data Rows (25 pts total)
    # Look for INSERT INTO ... "DataQualityRule"
    # We expect 4 rows.
    insert_pattern = re.compile(r'INSERT\s+INTO\s+.*"DataQualityRule"', re.IGNORECASE)
    inserts = insert_pattern.findall(script_content)
    
    if len(inserts) >= 4:
        score += 25
        feedback_parts.append(f"Found {len(inserts)}/4 documentation rows.")
    elif len(inserts) > 0:
        partial = int(25 * (len(inserts) / 4))
        score += partial
        feedback_parts.append(f"Found {len(inserts)}/4 documentation rows.")
    else:
        feedback_parts.append("No documentation rows inserted.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }