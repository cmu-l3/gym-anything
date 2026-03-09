#!/usr/bin/env python3
"""
Verifier for chinook_dedup_cleanup task.

Scoring Criteria (100 pts total):
1. DBeaver Connection 'ChinookDedup' exists: 10 pts
2. Customers table count correct (59): 15 pts
   - Fails if duplicates remain or originals deleted
3. Artists table count correct (275): 15 pts
4. Invoices preserved (412): 10 pts
   - Detects if invoices were deleted instead of reassigned
5. Albums preserved (347): 10 pts
6. No duplicates remaining (SQL check): 10 pts
7. Referential Integrity (No Orphans): 10 pts
8. Report CSV exists & valid: 10 pts
9. SQL Script exists: 10 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_dedup_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy unavailable"}
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_cust = metadata.get('original_customer_count', 59)
    expected_art = metadata.get('original_artist_count', 275)
    expected_inv = metadata.get('original_invoice_count', 412)
    expected_alb = metadata.get('original_album_count', 347)
    
    # Load agent result
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/dedup_result.json", tmp_res.name)
        with open(tmp_res.name) as f:
            res = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {str(e)}"}

    score = 0
    feedback = []

    # 1. Connection (10 pts)
    if res.get('connection_exists'):
        score += 10
        feedback.append("DBeaver connection 'ChinookDedup' found.")
    else:
        feedback.append("Missing DBeaver connection 'ChinookDedup'.")

    # 2. Customer Count (15 pts)
    final_cust = res.get('final_cust_count', -1)
    if final_cust == expected_cust:
        score += 15
        feedback.append(f"Customer count correct ({final_cust}).")
    elif final_cust > expected_cust:
        feedback.append(f"Customer count too high ({final_cust}). Duplicates not removed.")
    else:
        feedback.append(f"Customer count too low ({final_cust}). Original records deleted.")

    # 3. Artist Count (15 pts)
    final_art = res.get('final_artist_count', -1)
    if final_art == expected_art:
        score += 15
        feedback.append(f"Artist count correct ({final_art}).")
    else:
        feedback.append(f"Artist count incorrect ({final_art}, expected {expected_art}).")

    # 4. Invoices Preserved (10 pts)
    final_inv = res.get('final_invoice_count', -1)
    if final_inv == expected_inv:
        score += 10
        feedback.append(f"Invoices preserved ({final_inv}).")
    else:
        feedback.append(f"Data Loss detected: Invoices count is {final_inv} (expected {expected_inv}).")

    # 5. Albums Preserved (10 pts)
    final_alb = res.get('final_album_count', -1)
    if final_alb == expected_alb:
        score += 10
        feedback.append(f"Albums preserved ({final_alb}).")
    else:
        feedback.append(f"Data Loss detected: Albums count is {final_alb} (expected {expected_alb}).")

    # 6. Duplicates Check (10 pts)
    dup_c = res.get('dup_cust_groups', -1)
    dup_a = res.get('dup_artist_groups', -1)
    if dup_c == 0 and dup_a == 0:
        score += 10
        feedback.append("No duplicate groups remain.")
    else:
        feedback.append(f"Duplicates remain: Customers={dup_c}, Artists={dup_a}.")

    # 7. Referential Integrity (10 pts)
    orp_inv = res.get('orphan_invoices', -1)
    orp_alb = res.get('orphan_albums', -1)
    if orp_inv == 0 and orp_alb == 0:
        score += 10
        feedback.append("Referential integrity maintained (no orphans).")
    elif orp_inv > 0 or orp_alb > 0:
        feedback.append(f"Integrity Error: Found orphans (Invoices: {orp_inv}, Albums: {orp_alb}). Did you update FKs before deleting parents?")
    else:
        feedback.append("Could not verify integrity (DB access failed).")

    # 8. Report CSV (10 pts)
    if res.get('report_exists') and res.get('report_valid'):
        score += 10
        # Optional check: verify counts in CSV
        try:
            # We allow string or int in JSON, convert safely
            rem_c = int(str(res.get('report_removed_cust', '0')).strip())
            rem_a = int(str(res.get('report_removed_art', '0')).strip())
            if rem_c == 8 and rem_a == 6:
                feedback.append("Report CSV values match removed count.")
            else:
                feedback.append(f"Report CSV values mismatch (Cust: {rem_c}/8, Art: {rem_a}/6).")
        except:
            pass
    else:
        feedback.append("Dedup report missing or invalid.")

    # 9. SQL Script (10 pts)
    if res.get('script_exists'):
        score += 10
        feedback.append("SQL cleanup script found.")
    else:
        feedback.append("SQL cleanup script missing.")

    passed = (score >= 60) and (orp_inv == 0) and (orp_alb == 0) and (final_inv == expected_inv)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }