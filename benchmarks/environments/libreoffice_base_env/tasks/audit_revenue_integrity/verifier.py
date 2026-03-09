#!/usr/bin/env python3
"""
Verifier for audit_revenue_integrity task.

Verifies that:
1. The ODB file was saved and modified.
2. A query named 'Audit_InvoiceDiscrepancies' exists in the ODB.
3. The SQL logic in the query correctly identifies the corrupted invoices (IDs 25, 50, 75)
   by running the extracted SQL against the ground truth SQLite database.
"""

import json
import sqlite3
import zipfile
import tempfile
import os
import xml.etree.ElementTree as ET
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_revenue_integrity(traj, env_info, task_info):
    """
    Verify the financial audit query task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temporary directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        odb_local_path = os.path.join(temp_dir, "chinook.odb")
        sqlite_local_path = os.path.join(temp_dir, "ground_truth.sqlite")

        # 1. Retrieve files from container
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
            
            # Retrieve the ODB file
            if result.get("odb_exists"):
                copy_from_env(result["odb_path"], odb_local_path)
            
            # Retrieve the ground truth SQLite
            copy_from_env("/tmp/ground_truth.sqlite", sqlite_local_path)
            
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task artifacts: {str(e)}"
            }

        # Scoring Variables
        score = 0
        feedback_parts = []
        
        # 2. Check File Modification (Anti-gaming)
        if result.get("odb_modified", False):
            score += 10
            feedback_parts.append("Database saved successfully")
        else:
            feedback_parts.append("Database NOT saved (modifications lost)")
            # If not saved, we can't check the query, but we continue to verify what we can
        
        # 3. Parse ODB to find the Query
        query_sql = None
        query_found = False
        
        try:
            if zipfile.is_zipfile(odb_local_path):
                with zipfile.ZipFile(odb_local_path, 'r') as z:
                    if 'content.xml' in z.namelist():
                        content_xml = z.read('content.xml')
                        root = ET.fromstring(content_xml)
                        
                        # Namespaces in ODB content.xml
                        ns = {
                            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                            'xlink': 'http://www.w3.org/1999/xlink'
                        }
                        
                        # Find the specific query
                        # <db:query db:name="Audit_InvoiceDiscrepancies" db:command="...">
                        query_el = root.find(".//db:query[@db:name='Audit_InvoiceDiscrepancies']", ns)
                        
                        if query_el is not None:
                            query_found = True
                            query_sql = query_el.get('{urn:oasis:names:tc:opendocument:xmlns:database:1.0}command')
                            score += 20
                            feedback_parts.append("Query 'Audit_InvoiceDiscrepancies' found")
                        else:
                            feedback_parts.append("Query 'Audit_InvoiceDiscrepancies' NOT found in database")
        except Exception as e:
            feedback_parts.append(f"Error parsing ODB file: {str(e)}")

        if not query_found or not query_sql:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        # 4. Static Analysis of SQL
        # Expected keywords: SELECT, FROM, JOIN, GROUP BY, SUM, HAVING
        upper_sql = query_sql.upper()
        keywords_present = 0
        required_keywords = ["SELECT", "FROM", "GROUP BY", "SUM", "HAVING"]
        
        for kw in required_keywords:
            if kw in upper_sql:
                keywords_present += 1
        
        # JOIN check (could be implicit via comma)
        if "JOIN" in upper_sql or ("," in upper_sql and "WHERE" in upper_sql):
            keywords_present += 1
            
        static_score = int((keywords_present / (len(required_keywords) + 1)) * 20)
        score += static_score
        
        if keywords_present < 4:
            feedback_parts.append("SQL missing key aggregation/filtering clauses")

        # 5. Dynamic Verification (Run SQL against Ground Truth)
        # We need to adapt the HSQLDB SQL from LibreOffice to run on SQLite
        # 1. Replace double quotes with nothing (SQLite tolerates them, but just in case) or keep them.
        #    SQLite handles "Table"."Column" fine.
        # 2. HSQLDB might use specific function syntax.
        
        execution_success = False
        correct_rows_returned = False
        
        try:
            conn = sqlite3.connect(sqlite_local_path)
            cursor = conn.cursor()
            
            # Attempt to run the exact SQL
            # If it fails, try simple sanitization
            try:
                cursor.execute(query_sql)
                rows = cursor.fetchall()
            except sqlite3.Error:
                # Fallback: strict double quotes might be issue if logic is complex
                # But standard SQL usually runs on both.
                # Try replacing " with "" (empty) if it fails? No, " is standard identifier quote.
                # Just report error if it fails.
                feedback_parts.append("SQL syntax not compatible with verification engine")
                rows = []
                raise

            # Check results
            # Expected corrupted InvoiceIds: 25, 50, 75
            expected_ids = {25, 50, 75}
            returned_ids = set()
            
            # Assuming InvoiceId is the first column or at least present
            # The task asked for specific columns, but order might vary.
            # We look for integer values that match our IDs in the row.
            
            for row in rows:
                # Find the invoice ID in the row (it's likely the first column, but let's check all)
                for cell in row:
                    if cell in expected_ids:
                        returned_ids.add(cell)
            
            # Check precision: Did we get ONLY the bad ones?
            # If query returns ALL rows (no HAVING clause working), returned_ids will cover expected_ids
            # but len(rows) will be huge.
            
            total_rows = len(rows)
            
            if total_rows == 3 and returned_ids == expected_ids:
                correct_rows_returned = True
                score += 50
                feedback_parts.append("Query correctly identifies exactly the 3 corrupted invoices")
            elif total_rows > 3 and expected_ids.issubset(returned_ids):
                score += 10
                feedback_parts.append(f"Query found the corrupted invoices but returned {total_rows} rows (filtering failed)")
            elif len(returned_ids) > 0:
                score += 5
                feedback_parts.append("Query found some corrupted invoices but missed others")
            else:
                feedback_parts.append("Query did not find the expected corrupted invoices")

            conn.close()
            execution_success = True

        except Exception as e:
            feedback_parts.append(f"SQL execution failed verification: {str(e)}")

        # Final Evaluation
        passed = (score >= 80) and correct_rows_returned
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }