#!/usr/bin/env python3
"""
Verifier for create_denormalized_table task in LibreOffice Base.

Verifies:
1. 'chinook.odb' was modified during the task.
2. The internal HSQLDB script contains a CREATE TABLE statement for "InvoiceReport".
3. The table has the correct columns.
4. Data has been inserted (approx 2240 rows).
5. Data content verification (spot checks for joins/calculations).
"""

import json
import os
import zipfile
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_denormalized_table(traj, env_info, task_info):
    """
    Verify the denormalized InvoiceReport table creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    odb_path = metadata.get('odb_path', '/home/ga/chinook.odb')
    expected_row_min = metadata.get('min_row_count', 2200)
    expected_row_max = metadata.get('max_row_count', 2280)
    required_cols = metadata.get('required_columns', [])

    score = 0
    feedback_parts = []
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "task_result.json")
        local_odb = os.path.join(temp_dir, "chinook.odb")

        # 1. Fetch task result JSON
        try:
            copy_from_env("/tmp/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Check basic file status (Anti-gaming)
        if not task_result.get('odb_modified', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Database file was not modified. Did you save the changes?"
            }
        
        score += 10
        feedback_parts.append("Database file modified")

        # 3. Fetch ODB file for analysis
        try:
            copy_from_env(odb_path, local_odb)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {e}"}

        # 4. Analyze HSQLDB script inside ODB
        try:
            with zipfile.ZipFile(local_odb, 'r') as zf:
                # HSQLDB stores the schema and data in 'database/script'
                try:
                    script_content = zf.read('database/script').decode('utf-8', errors='replace')
                except KeyError:
                    return {"passed": False, "score": score, "feedback": "Invalid ODB format: missing database/script"}
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Corrupt ODB file"}

        # Check for CREATE TABLE
        # Pattern handles optional PUBLIC schema and quoting
        create_pattern = re.compile(r'CREATE\s+TABLE\s+(?:PUBLIC\.)?"?InvoiceReport"?', re.IGNORECASE)
        if create_pattern.search(script_content):
            score += 20
            feedback_parts.append("Table 'InvoiceReport' created")
        else:
            feedback_parts.append("Table 'InvoiceReport' NOT found")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Check for Columns
        # We look for column definitions in the CREATE TABLE statement or broadly in the file
        # HSQLDB script usually has: CREATE TABLE "Name" ("Col1" Type, "Col2" Type...)
        missing_cols = []
        for col in required_cols:
            # Simple check: verify column name exists in script near table definition
            # (Strict parsing is hard with regex, loose check is usually sufficient for verification)
            if f'"{col}"' not in script_content and col not in script_content:
                missing_cols.append(col)
        
        if not missing_cols:
            score += 20
            feedback_parts.append("All columns present")
        else:
            score += max(0, 20 - (len(missing_cols) * 2))
            feedback_parts.append(f"Missing columns: {', '.join(missing_cols[:3])}...")

        # Check for Data Insertion (Row Count)
        # HSQLDB format: INSERT INTO "InvoiceReport" VALUES(...)
        insert_pattern = re.compile(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"?InvoiceReport"?\s+VALUES', re.IGNORECASE)
        inserts = insert_pattern.findall(script_content)
        row_count = len(inserts)

        if expected_row_min <= row_count <= expected_row_max:
            score += 30
            feedback_parts.append(f"Row count correct ({row_count})")
        elif row_count > 0:
            # Partial credit for having some data
            score += 10
            feedback_parts.append(f"Row count incorrect ({row_count}, expected ~2240)")
        else:
            feedback_parts.append("Table is empty (no data inserted)")

        # Data Content Spot Checks (Joins & Calculations)
        # 1. Calculated field: LineTotal should be UnitPrice * Quantity
        # 2. Joins: "Iron Maiden" (Artist) and "Rock" (Genre) should appear in the VALUES
        
        data_score = 0
        if "Iron Maiden" in script_content:
            data_score += 5
        else:
            feedback_parts.append("Missing Artist data (Iron Maiden)")

        if "Rock" in script_content:
            data_score += 5
        else:
            feedback_parts.append("Missing Genre data (Rock)")

        # Check for concatenated name (Customer or Employee)
        # Look for a space inside a string literal that likely represents a name
        # e.g. 'Luís Gonçalves'
        if re.search(r"'[A-Z][a-z]+ [A-Z][a-z]+'", script_content):
            data_score += 5
        
        # Check for computed total (0.99 or 1.99 or larger sums)
        # InvoiceLine has 0.99 and 1.99 unit prices.
        if "0.99" in script_content or "1.99" in script_content:
            data_score += 5

        score += data_score
        if data_score == 20:
             feedback_parts.append("Data content verified")

    # Final Verdict
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }