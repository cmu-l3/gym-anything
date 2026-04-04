#!/usr/bin/env python3
"""Verifier for Orphan Pages Sitemap Audit task.

Scoring (100 points total):
- Internal Crawl CSV exported (20 pts)
  - Must have rows (indicating crawl happened)
- Orphan/Sitemap CSV exported (25 pts)
  - Identified by filename or header columns
- Two distinct CSVs created (10 pts)
- Report file exists (15 pts)
- Report quality (30 pts)
  - Length >= 300 chars (10 pts)
  - Contains numeric counts (10 pts)
  - Mentions target domain or relevant keywords (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def verify_orphan_pages_sitemap_audit(traj, env_info, task_info):
    """Verify orphan pages audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/orphan_audit_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # --- Criterion 1: Internal CSV (20 pts) ---
    internal_found = result.get('internal_csv_found', False)
    internal_rows = result.get('internal_row_count', 0)
    
    if internal_found and internal_rows >= 5:
        score += 20
        feedback_parts.append(f"Internal CSV valid ({internal_rows} rows) (20/20)")
    elif internal_found:
        score += 10
        feedback_parts.append(f"Internal CSV found but few rows ({internal_rows}) (10/20)")
    else:
        feedback_parts.append("Internal CSV not found (0/20)")

    # --- Criterion 2: Orphan/Sitemap CSV (25 pts) ---
    orphan_found = result.get('orphan_csv_found', False)
    
    if orphan_found:
        score += 25
        feedback_parts.append("Orphan/Sitemap CSV found (25/25)")
    else:
        feedback_parts.append("Orphan/Sitemap CSV not found (0/25)")

    # --- Criterion 3: Distinct Files (10 pts) ---
    new_csv_count = result.get('new_csv_count', 0)
    if new_csv_count >= 2:
        score += 10
        feedback_parts.append("At least 2 CSVs exported (10/10)")
    else:
        feedback_parts.append(f"Only {new_csv_count} CSV(s) exported (0/10)")

    # --- Criterion 4: Report Existence (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_len = result.get('report_length', 0)
    
    if report_exists:
        score += 15
        feedback_parts.append("Report file exists (15/15)")
    else:
        feedback_parts.append("Report file not found (0/15)")

    # --- Criterion 5: Report Content (30 pts) ---
    content_score = 0
    if report_exists:
        # Fetch report content to analyze
        report_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        report_content = ""
        try:
            copy_from_env(result.get('report_path'), report_tmp.name)
            with open(report_tmp.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
        except Exception:
            feedback_parts.append("Failed to read report content")
        finally:
            if os.path.exists(report_tmp.name):
                os.unlink(report_tmp.name)
        
        # Length check
        if len(report_content) >= 300:
            content_score += 10
            feedback_parts.append("Report length OK (10/10)")
        elif len(report_content) > 50:
            content_score += 5
            feedback_parts.append("Report short (5/10)")
            
        # Numbers check (counts)
        if re.search(r'\d+', report_content):
            content_score += 10
            feedback_parts.append("Report contains numbers (10/10)")
            
        # Keywords check
        keywords = ['orphan', 'sitemap', 'link', 'toscrape', 'recommend']
        if any(k in report_content.lower() for k in keywords):
            content_score += 10
            feedback_parts.append("Report contains relevant keywords (10/10)")
            
    score += content_score

    # VLM Verification (Bonus/Confirmation)
    # Using trajectory to confirm sitemap config workflow would be ideal, 
    # but basic file-based verification is robust here.
    
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }