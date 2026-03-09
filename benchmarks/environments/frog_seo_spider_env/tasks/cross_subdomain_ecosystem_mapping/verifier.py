#!/usr/bin/env python3
"""
Verifier for Cross-Subdomain Ecosystem Mapping task.

Scoring System (100 points total):
1. CSV Export Created & Valid (20 pts)
   - File exists at correct path and created during task.
2. Crawl Volume (10 pts)
   - CSV contains > 20 URLs (indicates actual crawling happened).
3. Subdomain Configuration (50 pts total)
   - 'books.toscrape.com' URLs present in CSV (25 pts)
   - 'quotes.toscrape.com' URLs present in CSV (25 pts)
   (This proves the agent enabled 'Crawl All Subdomains')
4. Summary Report (20 pts total)
   - File exists and created during task (10 pts)
   - Contains numeric counts (10 pts)

Pass Threshold: 70 points (Must successfully crawl both subdomains)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cross_subdomain_ecosystem_mapping(traj, env_info, task_info):
    """Verify the cross-subdomain crawling task."""
    
    # Use copy_from_env to get the result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}

    # --- Criterion 1: CSV Export (20 pts) ---
    csv_exists = result.get('csv_exists', False)
    csv_valid_time = result.get('csv_valid_timestamp', False)
    
    if csv_exists and csv_valid_time:
        score += 20
        feedback_parts.append("Valid CSV export found (+20)")
    elif csv_exists:
        feedback_parts.append("CSV exists but timestamp invalid (0/20)")
    else:
        feedback_parts.append("No CSV export found (0/20)")

    # --- Criterion 2: Crawl Volume (10 pts) ---
    row_count = result.get('csv_row_count', 0)
    if row_count > 20:
        score += 10
        feedback_parts.append(f"Crawl volume sufficient: {row_count} URLs (+10)")
    else:
        feedback_parts.append(f"Crawl volume too low: {row_count} URLs (0/10)")

    # --- Criterion 3: Subdomain Verification (50 pts) ---
    has_books = result.get('has_books_subdomain', False)
    has_quotes = result.get('has_quotes_subdomain', False)
    
    if has_books:
        score += 25
        feedback_parts.append("Books subdomain found in crawl (+25)")
    else:
        feedback_parts.append("Books subdomain missing - check 'Crawl All Subdomains' setting (0/25)")
        
    if has_quotes:
        score += 25
        feedback_parts.append("Quotes subdomain found in crawl (+25)")
    else:
        feedback_parts.append("Quotes subdomain missing (0/25)")

    # --- Criterion 4: Summary Report (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_valid_time = result.get('report_valid_timestamp', False)
    report_has_counts = result.get('report_has_counts', False)

    if report_exists and report_valid_time:
        score += 10
        feedback_parts.append("Report file created (+10)")
        if report_has_counts:
            score += 10
            feedback_parts.append("Report contains counts (+10)")
        else:
            feedback_parts.append("Report empty or missing numbers (0/10)")
    else:
        feedback_parts.append("Report file missing or stale (0/20)")

    # Calculate Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }