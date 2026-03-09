#!/usr/bin/env python3
"""
Verifier for chinook_fraud_investigation task.

Checks:
1. DBeaver connection 'ChinookFraud' created.
2. CSV file 'fraud_audit.csv' exists and was created during task.
3. CSV contains correct fraudulent Invoice IDs.
4. CSV contains correct columns.
5. CSV does NOT contain valid records (false positives).
"""

import json
import logging
import os
import csv
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth from Setup Script
FINANCIAL_MISMATCH_IDS = {99, 128, 256}
GEO_MISMATCH_IDS = {44, 300}
ALL_FRAUD_IDS = FINANCIAL_MISMATCH_IDS.union(GEO_MISMATCH_IDS)

REQUIRED_COLUMNS = [
    "InvoiceId", "ViolationType", "InvoiceTotal", 
    "CalculatedTotal", "BillingCountry", "CustomerCountry"
]

def verify_chinook_fraud_investigation(traj, env_info, task_info):
    """
    Verify the fraud audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic result metadata
    task_result = {}
    try:
        temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_meta.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}

    score = 0
    feedback = []
    
    # --- Criterion 1: Connection Created (10 pts) ---
    if task_result.get("dbeaver_connection_found", False):
        score += 10
        feedback.append("DBeaver connection 'ChinookFraud' found.")
    else:
        feedback.append("DBeaver connection 'ChinookFraud' NOT found.")

    # --- Criterion 2: CSV Exists & Timestamps (10 pts) ---
    csv_exists = task_result.get("csv_exists", False)
    csv_fresh = task_result.get("csv_created_during_task", False)
    
    if csv_exists and csv_fresh:
        score += 10
        feedback.append("Output CSV exists and was created during task.")
    elif csv_exists:
        score += 5
        feedback.append("Output CSV exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("Output CSV not found.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # --- Load CSV Content ---
    csv_rows = []
    try:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env(task_result["csv_path"], temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8-sig') as f:
            # Handle potentially messy headers (case sensitivity, whitespace)
            reader = csv.DictReader(f)
            # Normalize headers
            reader.fieldnames = [h.strip() for h in reader.fieldnames] if reader.fieldnames else []
            
            # Check for column mapping
            header_map = {}
            for req in REQUIRED_COLUMNS:
                match = next((h for h in reader.fieldnames if h.lower() == req.lower()), None)
                if match:
                    header_map[req] = match
            
            for row in reader:
                csv_rows.append(row)
                
        os.unlink(temp_csv.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV content: {e}"}

    # --- Criterion 3: Column Structure (15 pts) ---
    # We mapped headers above. Check if all required keys exist in map.
    missing_cols = [col for col in REQUIRED_COLUMNS if col not in header_map]
    if not missing_cols:
        score += 15
        feedback.append("CSV has all required columns.")
    else:
        feedback.append(f"CSV missing columns: {missing_cols}")

    # --- Analyze Content ---
    found_ids = set()
    found_financial = set()
    found_geo = set()
    false_positives = set()

    for row in csv_rows:
        try:
            # Flexible ID extraction
            id_col = header_map.get("InvoiceId")
            if not id_col: continue
            
            raw_id = row[id_col]
            if not raw_id: continue
            
            inv_id = int(float(raw_id)) # Handle "99.0" string
            found_ids.add(inv_id)

            if inv_id in FINANCIAL_MISMATCH_IDS:
                found_financial.add(inv_id)
            elif inv_id in GEO_MISMATCH_IDS:
                found_geo.add(inv_id)
            else:
                false_positives.add(inv_id)
                
        except ValueError:
            continue # Skip bad rows

    # --- Criterion 4: Financial Mismatch Detection (25 pts) ---
    # Need all 3 for full points
    fin_found_count = len(found_financial)
    if fin_found_count == 3:
        score += 25
        feedback.append("Correctly identified all financial mismatches.")
    elif fin_found_count > 0:
        partial = int(25 * (fin_found_count / 3))
        score += partial
        feedback.append(f"Identified {fin_found_count}/3 financial mismatches.")
    else:
        feedback.append("No financial mismatches found.")

    # --- Criterion 5: Geo Mismatch Detection (25 pts) ---
    # Need all 2 for full points
    geo_found_count = len(found_geo)
    if geo_found_count == 2:
        score += 25
        feedback.append("Correctly identified all geo mismatches.")
    elif geo_found_count > 0:
        partial = int(25 * (geo_found_count / 2))
        score += partial
        feedback.append(f"Identified {geo_found_count}/2 geo mismatches.")
    else:
        feedback.append("No geo mismatches found.")

    # --- Criterion 6: False Positive Rate (15 pts) ---
    if len(false_positives) == 0 and len(found_ids) > 0:
        score += 15
        feedback.append("No false positives.")
    elif len(false_positives) > 0:
        # Deduct points
        feedback.append(f"Found {len(false_positives)} false positive records (e.g., {list(false_positives)[:3]}).")
    else:
        # Empty file case - already handled by lack of positives
        pass

    # --- Final Result ---
    # Threshold 65: Needs connection (10) + CSV (10) + Columns (15) + at least some valid rows (30+)
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "found_financial": list(found_financial),
            "found_geo": list(found_geo),
            "false_positives": list(false_positives)
        }
    }