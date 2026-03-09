#!/usr/bin/env python3
"""
Verifier for split_invoice_items task.
Parses the ODB file (HSQLDB script) to verify data integrity and logical correctness.
"""

import json
import os
import zipfile
import tempfile
import re
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hsqldb_script(script_content):
    """
    Parses HSQLDB script content to extract rows for Invoice and InvoiceLine.
    Returns lists of dictionaries representing the rows.
    """
    invoices = []
    lines = []
    
    # Regex for parsing SQL INSERT values
    # Matches: INSERT INTO "Table" VALUES(val1, val2, ...)
    # Note: This is a simplified parser. HSQLDB 1.8 script format is fairly regular.
    
    for line in script_content.splitlines():
        if line.startswith('INSERT INTO "Invoice"'):
            # format: INSERT INTO "Invoice" VALUES(1,2,'2009-01-01...','Address',...)
            vals = parse_sql_values(line)
            if vals:
                invoices.append({
                    "InvoiceId": int(vals[0]),
                    "CustomerId": int(vals[1]),
                    "Total": float(vals[8])
                })
        elif line.startswith('INSERT INTO "InvoiceLine"'):
            # format: INSERT INTO "InvoiceLine" VALUES(Id, InvoiceId, TrackId, UnitPrice, Quantity)
            vals = parse_sql_values(line)
            if vals:
                lines.append({
                    "InvoiceLineId": int(vals[0]),
                    "InvoiceId": int(vals[1]),
                    "TrackId": int(vals[2]),
                    "UnitPrice": float(vals[3]),
                    "Quantity": int(vals[4])
                })
                
    return invoices, lines

def parse_sql_values(line):
    """
    Extracts values from a VALUES(...) clause.
    Handles quoted strings containing commas.
    """
    try:
        # Find content inside the outer parenthesis of VALUES(...)
        start = line.find("VALUES(") + 7
        end = line.rfind(")")
        if start < 7 or end == -1:
            return None
        
        content = line[start:end]
        
        # Split by comma, respecting single quotes
        values = []
        current_val = []
        in_quote = False
        
        i = 0
        while i < len(content):
            char = content[i]
            if char == "'":
                # Handle escaped quotes '' inside string
                if in_quote and i + 1 < len(content) and content[i+1] == "'":
                    current_val.append("'")
                    i += 1
                else:
                    in_quote = not in_quote
            elif char == "," and not in_quote:
                val_str = "".join(current_val).strip()
                # Remove surrounding quotes if present
                if val_str.startswith("'") and val_str.endswith("'"):
                    val_str = val_str[1:-1]
                values.append(val_str)
                current_val = []
            else:
                current_val.append(char)
            i += 1
            
        # Append last value
        val_str = "".join(current_val).strip()
        if val_str.startswith("'") and val_str.endswith("'"):
            val_str = val_str[1:-1]
        values.append(val_str)
        
        return values
    except Exception as e:
        logger.error(f"Error parsing line: {line} -> {e}")
        return None

def verify_split_invoice_items(traj, env_info, task_info):
    """
    Verifies that the invoice was split correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Constants from metadata
    metadata = task_info.get('metadata', {})
    ORIG_INV_ID = metadata.get('original_invoice_id', 1)
    CUST_ID = metadata.get('customer_id', 2)
    TRACK_MOVED = metadata.get('track_to_move', 4)
    TRACK_STAYED = metadata.get('track_to_stay', 2)
    EXPECTED_TOTAL = metadata.get('expected_total', 0.99)

    score = 0
    feedback = []
    
    # 1. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not res_data.get("file_modified", False):
        return {"passed": False, "score": 0, "feedback": "Database file was not modified/saved."}

    # 2. Retrieve ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    temp_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env("/tmp/result.odb", temp_odb.name)
        
        # 3. Extract database/script from ODB (which is a zip)
        try:
            with zipfile.ZipFile(temp_odb.name, 'r') as z:
                z.extract("database/script", temp_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Saved file is not a valid ODB archive."}
        except KeyError:
             return {"passed": False, "score": 0, "feedback": "Corrupt ODB: missing database/script."}

        # 4. Parse the script
        with open(os.path.join(temp_dir, "database/script"), 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
            
        invoices, invoice_lines = parse_hsqldb_script(script_content)
        
        # --- VERIFICATION LOGIC ---
        
        # Check 1: Original Invoice Total (20 pts)
        orig_invoice = next((i for i in invoices if i["InvoiceId"] == ORIG_INV_ID), None)
        if not orig_invoice:
            feedback.append("Original Invoice #1 missing!")
        elif abs(orig_invoice["Total"] - EXPECTED_TOTAL) < 0.01:
            score += 20
            feedback.append("Original invoice total updated correctly.")
        else:
            feedback.append(f"Original invoice total is {orig_invoice['Total']}, expected {EXPECTED_TOTAL}.")

        # Check 2: New Invoice Creation (25 pts)
        # Find any invoice for Customer 2 that is NOT ID 1 and has Total 0.99
        # Max ID in original Chinook is 412
        new_invoices = [i for i in invoices if i["CustomerId"] == CUST_ID and i["InvoiceId"] > 412]
        target_new_invoice = None
        
        if not new_invoices:
            feedback.append("No new invoice found for Customer 2 (ID > 412).")
        else:
            # Look for one with correct total
            valid_new = [i for i in new_invoices if abs(i["Total"] - EXPECTED_TOTAL) < 0.01]
            if valid_new:
                target_new_invoice = valid_new[0]
                score += 25  # Created new invoice
                score += 10  # Total is correct (combined criteria for simplicity or split logic)
                feedback.append(f"New invoice created (ID {target_new_invoice['InvoiceId']}) with correct total.")
            else:
                target_new_invoice = new_invoices[0]
                score += 25 # Created, but wrong total
                feedback.append(f"New invoice created (ID {target_new_invoice['InvoiceId']}) but total is wrong ({target_new_invoice['Total']}).")

        # Check 3: Line Item Moved (35 pts)
        # Find line for Track 4
        line_moved = next((l for l in invoice_lines if l["TrackId"] == TRACK_MOVED), None)
        
        if not line_moved:
             feedback.append("Line item for Track 4 deleted/missing!")
        elif target_new_invoice and line_moved["InvoiceId"] == target_new_invoice["InvoiceId"]:
            score += 35
            feedback.append("Line item moved to new invoice successfully.")
        elif line_moved["InvoiceId"] == ORIG_INV_ID:
            feedback.append("Line item for Track 4 still on original invoice.")
        else:
            feedback.append(f"Line item moved to unexpected Invoice ID {line_moved['InvoiceId']}.")

        # Check 4: Original Line Preserved (10 pts)
        line_stayed = next((l for l in invoice_lines if l["TrackId"] == TRACK_STAYED), None)
        if line_stayed and line_stayed["InvoiceId"] == ORIG_INV_ID:
            score += 10
            feedback.append("Original line item (Track 2) preserved on Invoice 1.")
        else:
            feedback.append("Original line item (Track 2) was moved or deleted incorrectly.")

    except Exception as e:
        logger.exception("Verification failed with error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }