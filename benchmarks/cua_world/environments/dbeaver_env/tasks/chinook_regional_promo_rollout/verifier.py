#!/usr/bin/env python3
"""
Verifier for Chinook Regional Promo Rollout Task
"""

import json
import base64
import os
import tempfile
import logging
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_regional_promo_rollout(traj, env_info, task_info):
    """
    Verifies that the database schema was modified, promo data inserted correctly, 
    and report generated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env missing"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Task Expectations
    expected_usa_count = 13
    expected_canada_count = 8
    expected_france_count = 5
    
    expected_usa_total = 130.0  # 13 * 10
    expected_canada_total = 120.0 # 8 * 15
    expected_france_total = 100.0 # 5 * 20

    score = 0
    feedback = []

    # 1. Connection (10 pts)
    if result.get("connection_exists", False):
        score += 10
        feedback.append("DBeaver connection 'ChinookOps' created.")
    else:
        feedback.append("DBeaver connection 'ChinookOps' NOT found.")

    # 2. Schema Change (20 pts)
    if result.get("has_column", False):
        score += 20
        feedback.append("Schema modified: 'campaign_tag' column exists.")
    else:
        feedback.append("Schema check failed: 'campaign_tag' column missing.")

    # 3. Promo Insertion Counts (30 pts)
    # 10 pts per country correct count
    u_cnt = result.get("usa_count", 0)
    c_cnt = result.get("canada_count", 0)
    f_cnt = result.get("france_count", 0)
    
    if u_cnt == expected_usa_count: score += 10
    else: feedback.append(f"USA count mismatch: {u_cnt} vs {expected_usa_count}")
    
    if c_cnt == expected_canada_count: score += 10
    else: feedback.append(f"Canada count mismatch: {c_cnt} vs {expected_canada_count}")
    
    if f_cnt == expected_france_count: score += 10
    else: feedback.append(f"France count mismatch: {f_cnt} vs {expected_france_count}")

    # 4. Logic/Totals Accuracy (15 pts)
    # Check if totals match expected (tolerance 1.0)
    u_tot = float(result.get("usa_total") or 0)
    c_tot = float(result.get("canada_total") or 0)
    f_tot = float(result.get("france_total") or 0)
    
    logic_pass = True
    if abs(u_tot - expected_usa_total) > 1.0: logic_pass = False
    if abs(c_tot - expected_canada_total) > 1.0: logic_pass = False
    if abs(f_tot - expected_france_total) > 1.0: logic_pass = False
    
    if logic_pass and (u_cnt + c_cnt + f_cnt) > 0:
        score += 15
        feedback.append("Promo amounts and totals are correct.")
    elif (u_cnt + c_cnt + f_cnt) > 0:
        feedback.append(f"Totals mismatch (USA: {u_tot}, CA: {c_tot}, FR: {f_tot}). Check promo amounts.")

    # 5. Data Integrity (Address Copy) (15 pts)
    # Mismatches should be 0
    mismatches = result.get("address_mismatches", 0)
    if mismatches == 0 and (u_cnt + c_cnt + f_cnt) > 0:
        score += 15
        feedback.append("Billing addresses correctly copied from Customers.")
    elif (u_cnt + c_cnt + f_cnt) > 0:
        feedback.append(f"Address integrity check failed: {mismatches} records have mismatching addresses.")

    # 6. Default Value check (10 pts)
    # Old rows should ideally be 'organic'.
    organic_count = result.get("organic_tag_count", 0)
    non_promo = result.get("non_promo_count", 0)
    
    # We award points if significant number of organic tags found OR if old rows simply aren't corrupted into promo
    # Strict requirement: "Existing invoices should be treated as 'organic'"
    if organic_count >= (non_promo * 0.9) and non_promo > 0:
        score += 10
        feedback.append("Existing rows correctly tagged as 'organic'.")
    else:
        feedback.append(f"Default value check: {organic_count} rows tagged 'organic' out of {non_promo} existing rows.")

    # 7. Report CSV (10 pts)
    if result.get("report_exists", False):
        try:
            content = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8')
            reader = csv.reader(io.StringIO(content))
            header = next(reader)
            # Check for required columns loosely
            header_str = " ".join(header).lower()
            if "country" in header_str and "cost" in header_str:
                score += 10
                feedback.append("Report CSV exists with valid header.")
            else:
                score += 5
                feedback.append("Report CSV exists but header missing expected columns.")
        except:
            score += 5
            feedback.append("Report CSV exists but could not parse.")
    else:
        feedback.append("Report CSV not found.")

    # Final Pass Check
    # Threshold 65: Requires schema change (20) + Insert counts (30) + partial other
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }