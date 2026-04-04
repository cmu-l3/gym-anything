#!/usr/bin/env python3
"""
Verifier for implement_loyalty_tiers task.

Verification Logic:
1. Extract 'database/script' from the ODB (zip) file.
2. Parse 'INSERT INTO "Invoice"' statements to calculate true spending per CustomerId.
3. Parse 'CREATE TABLE "Customer"' to ensure 'LoyaltyTier' column exists.
4. Parse 'INSERT INTO "Customer"' statements to check if 'LoyaltyTier' is populated correctly based on spending.

Tier Logic:
- Platinum: > 45.00
- Gold: 40.00 - 45.00 (inclusive)
- Silver: < 40.00
"""

import json
import os
import zipfile
import tempfile
import re
import logging
from collections import defaultdict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_loyalty_tiers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("db_modified", False):
        return {"passed": False, "score": 0, "feedback": "Database file was not saved/modified."}

    # Copy the ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    odb_path = temp_odb.name
    temp_odb.close()

    try:
        copy_from_env("/home/ga/chinook.odb", odb_path)
    except Exception as e:
        if os.path.exists(odb_path):
            os.unlink(odb_path)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve database file: {e}"}

    # Analyze ODB content
    score = 0
    feedback = []
    
    try:
        with zipfile.ZipFile(odb_path, 'r') as z:
            if 'database/script' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Corrupt ODB file: database/script missing"}
            
            script_content = z.read('database/script').decode('utf-8', errors='ignore')
            
    except zipfile.BadZipFile:
        os.unlink(odb_path)
        return {"passed": False, "score": 0, "feedback": "Invalid ODB file format (not a valid zip)"}

    os.unlink(odb_path)

    # --- 1. Calculate Ground Truth from Invoices ---
    # Parse: INSERT INTO "Invoice" VALUES(1,2,'2009-01-01 00:00:00.000000','123 Main St','City','State','Country','12345',1.98)
    # Schema: "InvoiceId","CustomerId","InvoiceDate","BillingAddress",...,"Total"
    # Note: Values are usually positional. Total is typically last.
    
    # Let's find the CREATE TABLE "Invoice" to be sure of position, 
    # but for HSQLDB 1.8 default export, we can usually infer.
    # Chinook Invoice table: InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingState, BillingCountry, BillingPostalCode, Total
    
    customer_spending = defaultdict(float)
    
    # Regex to capture values inside VALUES(...)
    # This is a simplified parser; assumes standard formatting in .script file
    insert_pattern = re.compile(r'INSERT INTO "Invoice" VALUES\((.+)\)')
    
    for line in script_content.splitlines():
        if line.startswith('INSERT INTO "Invoice"'):
            match = insert_pattern.search(line)
            if match:
                # Split by comma, respecting quotes is hard with simple split, but HSQLDB numbers aren't quoted.
                # Total is last, CustomerId is 2nd.
                # A safer way to split ignoring internal commas in strings:
                # But "Total" and "CustomerId" are numeric, so they won't contain commas.
                # Structure: ID, CustID, Date, 'Addr', 'City', 'State', 'Country', 'Zip', Total
                
                parts = split_sql_values(match.group(1))
                if len(parts) >= 9:
                    try:
                        cust_id = int(parts[1])
                        total = float(parts[-1]) # Last column is Total
                        customer_spending[cust_id] += total
                    except ValueError:
                        pass

    if not customer_spending:
        feedback.append("Warning: Could not parse Invoice data to establish ground truth.")
    
    # --- 2. Check Customer Table Schema ---
    # Look for CREATE TABLE "Customer" and "LoyaltyTier"
    customer_schema_pattern = re.compile(r'CREATE TABLE "Customer" \((.+?)\)', re.DOTALL)
    schema_match = customer_schema_pattern.search(script_content)
    
    col_added = False
    loyalty_col_index = -1
    
    if schema_match:
        columns_def = schema_match.group(1)
        if '"LoyaltyTier"' in columns_def:
            score += 30
            col_added = True
            feedback.append("Column 'LoyaltyTier' added to Customer table.")
            
            # Determine column index
            # Split definitions by comma, ignoring commas inside parens/quotes if possible
            # Simplified: just count commas at top level
            cols = [c.strip() for c in columns_def.split(',')]
            # Finding exact index is tricky if primary key constraints are mixed in.
            # Usually HSQLDB lists columns then constraints.
            # We'll count how many column definitions appear before LoyaltyTier.
            
            # Robust approach: Parse inserts to find where the string values are
        else:
            feedback.append("Column 'LoyaltyTier' NOT found in Customer table.")
    else:
        feedback.append("Could not find Customer table definition.")

    # --- 3. verify Data Population ---
    # Parse INSERT INTO "Customer"
    # We need to find which value corresponds to LoyaltyTier.
    # If the user added it, it's likely the last column or appended.
    
    correct_tiers = 0
    total_customers = 0
    tier_errors = 0
    
    if col_added and customer_spending:
        # Determine expected tiers
        expected_tiers = {}
        for cust_id, spent in customer_spending.items():
            if spent > 45.00:
                expected_tiers[cust_id] = "Platinum"
            elif 40.00 <= spent <= 45.00:
                expected_tiers[cust_id] = "Gold"
            else:
                expected_tiers[cust_id] = "Silver"
        
        insert_cust_pattern = re.compile(r'INSERT INTO "Customer" VALUES\((.+)\)')
        
        for line in script_content.splitlines():
            if line.startswith('INSERT INTO "Customer"'):
                match = insert_cust_pattern.search(line)
                if match:
                    parts = split_sql_values(match.group(1))
                    if len(parts) < 2: continue
                    
                    try:
                        cust_id = int(parts[0]) # First column is CustomerId
                    except ValueError:
                        continue
                        
                    if cust_id not in expected_tiers:
                        continue
                        
                    total_customers += 1
                    expected = expected_tiers[cust_id]
                    
                    # Search for the expected tier keyword in the values
                    # This avoids needing to know the exact column index
                    found_tier = "None"
                    
                    # Sanitize parts to strings
                    row_values = [str(p).strip("'") for p in parts]
                    
                    if "Platinum" in row_values:
                        found_tier = "Platinum"
                    elif "Gold" in row_values:
                        found_tier = "Gold"
                    elif "Silver" in row_values:
                        found_tier = "Silver"
                    
                    if found_tier == expected:
                        correct_tiers += 1
                    else:
                        tier_errors += 1
                        # feedback.append(f"Cust {cust_id}: Expected {expected}, found {found_tier} (Spent: {customer_spending[cust_id]:.2f})")

        # Scoring logic for data
        if total_customers > 0:
            accuracy = correct_tiers / total_customers
            data_points = 70 * accuracy
            score += int(data_points)
            feedback.append(f"Data Accuracy: {correct_tiers}/{total_customers} records correct ({int(accuracy*100)}%).")
        else:
            feedback.append("No customer records found to verify.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }

def split_sql_values(values_str):
    """
    Splits a SQL VALUES string by comma, ignoring commas inside single quotes.
    E.g., "1, 'Smith, John', 20.0" -> ["1", "'Smith, John'", "20.0"]
    """
    parts = []
    current = []
    in_quote = False
    escape = False
    
    for char in values_str:
        if escape:
            current.append(char)
            escape = False
        elif char == '\\':
            current.append(char)
            escape = True
        elif char == "'":
            in_quote = not in_quote
            current.append(char)
        elif char == ',' and not in_quote:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    
    if current:
        parts.append("".join(current).strip())
        
    return parts