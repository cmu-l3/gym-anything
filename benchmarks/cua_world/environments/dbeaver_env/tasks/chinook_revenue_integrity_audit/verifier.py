#!/usr/bin/env python3
"""
Verifier for Chinook Revenue Integrity Audit task.

Scoring Breakdown (100 pts):
1. Connection Created (10 pts): 'ChinookAudit' connection exists in DBeaver.
2. CSV File Created (10 pts): Output file exists and was created during task.
3. CSV Structure (10 pts): Correct headers present.
4. Anomaly Detection (40 pts): Correct InvoiceIds identified (8 pts each for 5 targets).
5. Value Accuracy (20 pts): Discrepancy values match ground truth within tolerance.
6. SQL Script Saved (10 pts): Query file exists.

Pass Threshold: 60 points
"""

import json
import logging
import os
import tempfile
import csv
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth Data
EXPECTED_INVOICE_IDS = {10, 55, 120, 250, 310}
# Expected discrepancies (Stored - Calculated)
# Note: ID 10 had +5.00 added to Total, so Stored - Calculated should be approx 5.00
EXPECTED_DISCREPANCIES = {
    10: 5.00,
    55: -2.00,
    120: 10.50,
    250: 0.99,
    310: -100.00
}
REQUIRED_HEADERS = ['invoiceid', 'storedtotal', 'calculatedtotal', 'discrepancy']

def verify_chinook_revenue_integrity_audit(traj, env_info, task_info):
    """
    Verify the audit task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    score = 0
    feedback_log = []
    
    # --- Step 1: Fetch Result JSON ---
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- Step 2: Connection Check (10 pts) ---
    if result_data.get('connection_found', False):
        score += 10
        feedback_log.append("✅ DBeaver connection 'ChinookAudit' confirmed.")
    else:
        feedback_log.append("❌ DBeaver connection 'ChinookAudit' not found in config.")

    # --- Step 3: SQL Script Check (10 pts) ---
    if result_data.get('sql_script_exists', False) and result_data.get('sql_script_size', 0) > 10:
        score += 10
        feedback_log.append("✅ SQL script saved.")
    else:
        feedback_log.append("❌ SQL script not found or empty.")

    # --- Step 4: CSV File Checks (10 pts) ---
    csv_exists = result_data.get('csv_exists', False)
    csv_created_during = result_data.get('csv_created_during_task', False)
    
    if csv_exists and csv_created_during:
        score += 10
        feedback_log.append("✅ Output CSV created during task.")
    elif csv_exists:
        score += 5
        feedback_log.append("⚠️ Output CSV exists but timestamp suggests it wasn't created during this session (partial points).")
    else:
        feedback_log.append("❌ Output CSV not found.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_log)}

    # --- Step 5: Analyze CSV Content (Structure: 10 pts, Detection: 40 pts, Accuracy: 20 pts) ---
    csv_path = result_data.get('csv_path')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(csv_path, temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            headers = [h.lower().strip() for h in (reader.fieldnames or [])]
            
            # Check Headers (10 pts)
            headers_valid = all(req in headers for req in REQUIRED_HEADERS)
            if headers_valid:
                score += 10
                feedback_log.append("✅ CSV headers are correct.")
            else:
                feedback_log.append(f"❌ Missing required columns. Found: {headers}")
                # We can try to proceed if we can fuzzy match, but strict is safer for now.
                # If headers are totally wrong, we can't grade content.
                if not any('id' in h for h in headers): 
                    return {"passed": False, "score": score, "feedback": "\n".join(feedback_log)}

            # Map actual headers to standard keys if slightly off (simple robustness)
            id_col = next((h for h in headers if 'invoiceid' in h or 'id' in h), None)
            disc_col = next((h for h in headers if 'discrepancy' in h or 'diff' in h), None)

            found_ids = set()
            correct_values_count = 0
            
            for row in reader:
                if not id_col or not disc_col: 
                    break
                
                try:
                    # Clean and parse ID
                    raw_id = row[id_col]
                    if not raw_id: continue
                    inv_id = int(float(raw_id)) # handle "10.0" string
                    
                    # Clean and parse Discrepancy
                    raw_disc = row[disc_col].replace('$', '').replace(',', '')
                    disc_val = float(raw_disc)
                    
                    # Check if this is one of our corrupted IDs
                    if inv_id in EXPECTED_INVOICE_IDS:
                        found_ids.add(inv_id)
                        
                        # Check Value Accuracy
                        expected_val = EXPECTED_DISCREPANCIES[inv_id]
                        # Tolerance: 0.1 to account for float math differences or sign flipping (if they did Calc - Stored)
                        if math.isclose(abs(disc_val), abs(expected_val), abs_tol=0.1):
                            correct_values_count += 1
                        
                except ValueError:
                    continue
            
            # Score Detection (40 pts)
            # 8 points per correct ID found
            detected_count = len(found_ids)
            score += (detected_count * 8)
            feedback_log.append(f"🔍 Anomalies Detected: {detected_count}/5")
            
            # Score Accuracy (20 pts)
            # 4 points per correct calculation
            score += (correct_values_count * 4)
            if correct_values_count < detected_count:
                feedback_log.append(f"⚠️ Value Accuracy: {correct_values_count}/{detected_count} calculations were correct.")
            else:
                feedback_log.append("✅ All calculated discrepancies match ground truth.")

    except Exception as e:
        feedback_log.append(f"❌ Error processing CSV content: {str(e)}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # --- Step 6: VLM Verification (Bonus/Confirmation) ---
    # Only if score is borderline or for additional confidence. 
    # For now, we rely on the strong file-based signals.
    
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_log)
    }