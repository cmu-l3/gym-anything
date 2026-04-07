#!/usr/bin/env python3
"""
Verifier for Tariff HTS Research task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tariff_hts_research(traj, env_info, task_info):
    """
    Verifies the tariff research task based on:
    1. Report existence and timestamp.
    2. Content analysis (keywords + HTS regex).
    3. Browser history (USITC/CBP visits).
    4. Downloads.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata for verification rules
    metadata = task_info.get('metadata', {})
    product_criteria = metadata.get('product_criteria', [])

    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Report Existence & Timestamp (10 pts) ---
    report = result.get('report', {})
    if report.get('exists') and report.get('modified_after_start'):
        score += 10
        feedback_parts.append("Report created successfully (10/10)")
    elif report.get('exists'):
        score += 5
        feedback_parts.append("Report exists but not modified during task (5/10)")
    else:
        feedback_parts.append("Report file not found (0/10)")

    # --- Criterion 2: Report Content (45 pts) ---
    content = report.get('content', '').lower()
    
    # Helper to check proximity of keyword to HTS pattern
    def check_product_classification(criteria):
        name = criteria['name']
        keywords = criteria['keywords']
        pattern = criteria['hts_pattern']
        
        # 1. Check if product mentioned
        mentioned = any(k in content for k in keywords)
        
        # 2. Check for HTS code pattern
        # Regex finds the specific HTS pattern (e.g., 6912.xx)
        hts_match = re.search(pattern, content, re.IGNORECASE)
        
        if mentioned and hts_match:
            return 15, f"{name} classified ({hts_match.group(0)})"
        elif hts_match:
            return 10, f"{name} code found but product name missing"
        elif mentioned:
            return 5, f"{name} mentioned but missing valid HTS code"
        else:
            return 0, f"{name} missing"

    for criteria in product_criteria:
        pts, msg = check_product_classification(criteria)
        score += pts
        feedback_parts.append(f"{msg} ({pts}/15)")

    # --- Criterion 3: Duty Rates (10 pts) ---
    # Look for percentage sign or "free" near HTS codes
    if re.search(r'(\d+(\.\d+)?%|free)', content):
        score += 10
        feedback_parts.append("Duty rates included (10/10)")
    else:
        feedback_parts.append("Duty rates missing (0/10)")

    # --- Criterion 4: Browser History (25 pts) ---
    history = result.get('history', {})
    if history.get('new_usitc_activity'):
        score += 15
        feedback_parts.append("USITC HTS database visited (15/15)")
    else:
        feedback_parts.append("USITC not visited (0/15)")
        
    if history.get('new_cbp_activity'):
        score += 10
        feedback_parts.append("CBP.gov visited (10/10)")
    else:
        feedback_parts.append("CBP.gov not visited (0/10)")

    # --- Criterion 5: Downloads (5 pts) ---
    downloads = result.get('downloads', {})
    if downloads.get('has_new_gov_download'):
        score += 5
        feedback_parts.append("Reference file downloaded (5/5)")
    else:
        feedback_parts.append("No reference file downloaded (0/5)")
        
    # --- Criterion 6: Report Completeness (5 pts) ---
    # Basic check for file size > 400 bytes implies some substance
    if report.get('size', 0) > 400:
        score += 5
        feedback_parts.append("Report length adequate (5/5)")
    else:
        feedback_parts.append("Report too short (0/5)")

    # --- Final Result ---
    # Pass threshold: 60 points
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }