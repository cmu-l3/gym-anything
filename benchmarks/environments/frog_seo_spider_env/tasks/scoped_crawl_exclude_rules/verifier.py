#!/usr/bin/env python3
"""
Verifier for Scoped Crawl Exclude Rules task.

Scoring System (100 points total):
1. CSV file exists in correct directory (10 pts)
2. CSV created after task start (10 pts)
3. CSV contains books.toscrape.com URLs (15 pts)
4. NO '/category/' URLs present (30 pts) - CRITICAL
5. Crawl limit respected (<= 50 URLs) (15 pts)
6. Standard SF columns present (10 pts)
7. Book detail pages present (>= 2 /catalogue/ URLs) (10 pts)

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scoped_crawl(traj, env_info, task_info):
    """Verify scoped crawl task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load result file
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Extract values
    file_created = result.get('file_created', False)
    total_rows = result.get('total_rows', 0)
    category_count = result.get('category_urls_count', 0)
    catalogue_count = result.get('catalogue_urls_count', 0)
    target_count = result.get('target_domain_count', 0)
    has_cols = result.get('has_standard_cols', False)
    
    # 1. CSV file exists (10 pts)
    if result.get('latest_csv_path'):
        score += 10
        feedback_parts.append("CSV file found (10/10)")
    else:
        feedback_parts.append("No CSV file found (0/10)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Created after task start (10 pts)
    if file_created:
        score += 10
        feedback_parts.append("File created during task (10/10)")
    else:
        feedback_parts.append("File not created during task (0/10)")

    # 3. Contains target domain URLs (15 pts)
    if target_count >= 5:
        score += 15
        feedback_parts.append(f"Target URLs found ({target_count}) (15/15)")
    elif target_count > 0:
        score += 5
        feedback_parts.append(f"Few target URLs found ({target_count}) (5/15)")
    else:
        feedback_parts.append("No books.toscrape.com URLs found (0/15)")

    # 4. NO '/category/' URLs (30 pts)
    # Only award if we actually have some target URLs (to prevent empty file gaming)
    if target_count > 0:
        if category_count == 0:
            score += 30
            feedback_parts.append("Exclude rule working: No category pages found (30/30)")
        else:
            feedback_parts.append(f"Exclude rule FAILED: {category_count} category pages found (0/30)")
    else:
        feedback_parts.append("Cannot verify exclude rule without valid data (0/30)")

    # 5. Crawl limit respected (<= 50) (15 pts)
    if 0 < total_rows <= 50:
        score += 15
        feedback_parts.append(f"Crawl limit respected: {total_rows} URLs (15/15)")
    elif total_rows > 50:
        feedback_parts.append(f"Crawl limit exceeded: {total_rows} URLs (0/15)")
    else:
        feedback_parts.append("File empty (0/15)")

    # 6. Standard columns (10 pts)
    if has_cols:
        score += 10
        feedback_parts.append("Standard columns present (10/10)")
    else:
        feedback_parts.append("Missing standard columns (0/10)")

    # 7. Book detail pages present (10 pts)
    if catalogue_count >= 2:
        score += 10
        feedback_parts.append(f"Product pages found ({catalogue_count}) (10/10)")
    else:
        feedback_parts.append("No product pages found (0/10)")

    # Pass check
    # Must have score >= 70 AND no category pages (if data exists)
    passed = score >= 70
    if target_count > 0 and category_count > 0:
        passed = False # Fail if exclusion didn't work, regardless of score
        feedback_parts.append("FAILED: Category pages were not excluded")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }