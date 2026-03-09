#!/usr/bin/env python3
"""
Verifier for nonprofit_financial_due_diligence task.

Scoring Breakdown (100 points total):
1. [15 pts] Firefox History: Visited ProPublica Nonprofit Explorer (>=3 pages).
2. [15 pts] Bookmarks: 'Grant Diligence' folder created with >=3 bookmarks.
3. [15 pts] PDF Download: mozilla_990.pdf exists, is recent, and >50KB.
4. [10 pts] JSON File: nonprofit_financials.json exists and is valid.
5. [45 pts] Data Accuracy (15 pts per org):
   - Correct keys present.
   - Tax year is recent (>=2022).
   - Revenue/Expenses are numeric and plausible (> $1M).
   - Highest compensated person is a string.

Pass Threshold: 75/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_nonprofit_financial_due_diligence(traj, env_info, task_info):
    """
    Verify the nonprofit financial due diligence task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check History (15 pts)
    visits = result.get("propublica_visits", 0)
    if visits >= 3:
        score += 15
        feedback.append("History check passed: Visited ProPublica (15/15)")
    elif visits > 0:
        score += 5
        feedback.append(f"History check partial: Only {visits} visits (5/15)")
    else:
        feedback.append("History check failed: No ProPublica visits (0/15)")

    # 2. Check Bookmarks (15 pts)
    folder_exists = result.get("bookmark_folder_exists", False)
    bm_count = result.get("bookmark_count", 0)
    
    if folder_exists:
        if bm_count >= 3:
            score += 15
            feedback.append(f"Bookmarks passed: Folder found with {bm_count} items (15/15)")
        else:
            score += 10
            feedback.append(f"Bookmarks partial: Folder found but only {bm_count}/3 items (10/15)")
    else:
        feedback.append("Bookmarks failed: 'Grant Diligence' folder not found (0/15)")

    # 3. Check PDF Download (15 pts)
    pdf_exists = result.get("pdf_exists", False)
    pdf_fresh = result.get("pdf_fresh", False)
    pdf_size = result.get("pdf_size", 0)
    
    # A full 990 PDF is usually at least 100KB, often MBs.
    if pdf_exists and pdf_fresh and pdf_size > 50000:
        score += 15
        feedback.append("PDF download passed: mozilla_990.pdf is valid (15/15)")
    elif pdf_exists and pdf_fresh:
        score += 5
        feedback.append("PDF download suspicious: File exists but is small (<50KB) (5/15)")
    else:
        feedback.append("PDF download failed: File missing or old (0/15)")

    # 4. Check JSON Existence (10 pts)
    json_exists = result.get("json_exists", False)
    json_fresh = result.get("json_fresh", False)
    
    if json_exists and json_fresh:
        score += 10
        feedback.append("JSON output file exists and is fresh (10/10)")
    else:
        feedback.append("JSON output file missing or not created during task (0/10)")

    # 5. Data Accuracy (45 pts)
    json_content = result.get("json_content", {})
    required_orgs = ["mozilla_foundation", "wikimedia_foundation", "eff"]
    
    for org in required_orgs:
        org_data = json_content.get(org)
        org_score = 0
        if not org_data:
            feedback.append(f"Data missing for {org} (0/15)")
            continue

        # Check fields
        try:
            # Tax year check
            tax_year = org_data.get("tax_year")
            if isinstance(tax_year, (int, str)) and int(tax_year) >= 2022:
                org_score += 3
            
            # Financials plausibility check
            rev = org_data.get("total_revenue", 0)
            exp = org_data.get("total_expenses", 0)
            assets = org_data.get("net_assets", 0)
            
            # Simple check: these orgs have > $1M revenue
            if isinstance(rev, (int, float)) and rev > 1000000:
                org_score += 4
            
            if isinstance(exp, (int, float)) and exp > 1000000:
                org_score += 4
            
            # Person check
            person = org_data.get("highest_compensated_person")
            if person and isinstance(person, str) and len(person) > 3:
                org_score += 4
                
        except Exception as e:
            feedback.append(f"Error parsing data for {org}: {e}")

        score += org_score
        feedback.append(f"Data quality for {org}: {org_score}/15")

    # Final Result
    return {
        "passed": score >= 75,
        "score": score,
        "feedback": "\n".join(feedback)
    }