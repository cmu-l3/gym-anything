#!/usr/bin/env python3
"""
Verifier for competitive_benchmark_list_crawl task.

Scoring Breakdown (100 points total):
1. CSV Export Analysis (55 pts)
   - CSV exists and modified during task: 10 pts
   - Contains 'books.toscrape.com': 10 pts
   - Contains 'quotes.toscrape.com': 10 pts
   - Contains 'crawler-test.com': 10 pts
   - Has standard columns (Address, Status Code): 10 pts
   - Sufficient row count (>= 12): 5 pts

2. Report Analysis (40 pts)
   - Report exists and modified during task: 10 pts
   - Mentions all 3 domains: 10 pts
   - Contains numeric data (metrics): 10 pts
   - Contains recommendations/keywords: 10 pts

3. Process Verification (5 pts)
   - Screaming Frog running or closed gracefully: 5 pts

Pass Threshold: 60 points (Must include data from multiple domains)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_competitive_benchmark_list_crawl(traj, env_info, task_info):
    """Verify that the agent performed a multi-domain crawl and created a report."""
    
    # 1. Setup & Read Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score CSV Export (55 pts max)
    csv_exists = result.get("csv_exists", False)
    csv_fresh = result.get("csv_modified_in_task", False)
    
    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("Fresh CSV export found (+10)")
    elif csv_exists:
        # Penalize if file existed before task (though setup should have cleared it)
        score += 5
        feedback_parts.append("CSV found but timestamp unclear (+5)")
    else:
        feedback_parts.append("No CSV export found (0)")

    # Domain coverage
    domains_found = [d for d in result.get("domains_found", []) if d]
    
    if "books.toscrape.com" in domains_found:
        score += 10
        feedback_parts.append("Domain 1 found (+10)")
    if "quotes.toscrape.com" in domains_found:
        score += 10
        feedback_parts.append("Domain 2 found (+10)")
    if "crawler-test.com" in domains_found:
        score += 10
        feedback_parts.append("Domain 3 found (+10)")

    # Structure & Volume
    if result.get("has_standard_columns", False):
        score += 10
        feedback_parts.append("Standard columns present (+10)")
    
    row_count = result.get("row_count", 0)
    if row_count >= 12:
        score += 5
        feedback_parts.append(f"Row count sufficient ({row_count}) (+5)")
    else:
        feedback_parts.append(f"Row count low ({row_count})")

    # 3. Score Report (40 pts max)
    report_exists = result.get("report_exists", False)
    report_fresh = result.get("report_modified_in_task", False)
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Fresh report found (+10)")
        
        # Report content scoring
        if result.get("report_mentions_all_domains", False):
            score += 10
            feedback_parts.append("Report covers all domains (+10)")
        else:
            feedback_parts.append("Report missing some domain names")

        if result.get("report_has_numbers", False):
            score += 10
            feedback_parts.append("Report includes metrics (+10)")
        else:
            feedback_parts.append("Report lacks numeric data")

        if result.get("report_has_recommendations", False):
            score += 10
            feedback_parts.append("Report includes recommendations (+10)")
        else:
            feedback_parts.append("Report lacks recommendations")
            
    elif report_exists:
        score += 5
        feedback_parts.append("Report found but timestamp unclear (+5)")
    else:
        feedback_parts.append("No report found (0)")

    # 4. Process (5 pts)
    # If file was created, app must have run, but we check running state too
    if result.get("sf_running", False) or csv_exists:
        score += 5
        feedback_parts.append("App usage confirmed (+5)")

    # 5. Final Determination
    # Critical pass criteria: Must have exported data from at least 2 domains
    unique_domains = len(set(domains_found))
    passed = (score >= 60) and (unique_domains >= 2)
    
    if unique_domains < 2:
        feedback_parts.append(f"FAILED: Only found data for {unique_domains} domains (min 2 required)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }