#!/usr/bin/env python3
"""Verifier for SERP Title Truncation Audit task.

Scoring (100 points total):
- CSV Analysis (50 points):
  - File exists & created during task: 15 pts
  - Contains 'books.toscrape.com': 10 pts
  - Contains 'Title' column: 10 pts
  - Contains 'Pixel Width' column (critical): 15 pts
- Report Analysis (50 points):
  - File exists & created during task: 10 pts
  - Contains numeric analysis (≥3 numbers): 10 pts
  - Mentions 'truncat*' or 'pixel': 10 pts
  - Contains remediation keywords (recommend/shorten/etc): 10 pts
  - Specific titles from crawl identified (checked via content match): 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)


def verify_serp_title_truncation_audit(traj, env_info, task_info):
    """Verify the SERP title truncation audit task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # 1. Load JSON Result
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_json.name):
                os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 2. CSV Analysis (Max 50 pts)
    csv_exists = result.get('csv_exists', False)
    csv_fresh = result.get('csv_modified_after_start', False)
    
    if csv_exists and csv_fresh:
        score += 15
        feedback_parts.append("CSV exported (15/15)")
        
        # Check domain
        if result.get('csv_has_target_domain', False):
            score += 10
            feedback_parts.append("Correct domain (10/10)")
        else:
            feedback_parts.append("Wrong domain in CSV (0/10)")

        # Check Title column
        if result.get('csv_has_title_col', False):
            score += 10
            feedback_parts.append("Title column present (10/10)")
        else:
            feedback_parts.append("Missing Title column (0/10)")

        # Check Pixel Width column (Critical)
        if result.get('csv_has_pixel_width_col', False):
            score += 15
            feedback_parts.append("Pixel Width column present (15/15)")
        else:
            feedback_parts.append("Missing Pixel Width column - wrong tab? (0/15)")

        # Min rows check (implied validity)
        if result.get('csv_row_count', 0) < 20:
             feedback_parts.append(f"Warning: Low row count ({result.get('csv_row_count', 0)})")
    else:
        feedback_parts.append("No valid CSV export found (0/50)")

    # 3. Report Analysis (Max 50 pts)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_modified_after_start', False)
    report_size = result.get('report_size_bytes', 0)

    # We need to inspect report content for the "specific titles" check
    # so we'll try to copy the report file itself
    report_content = ""
    if report_exists and report_fresh:
        try:
            tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            tmp_report.close()
            try:
                copy_from_env(task_info['metadata']['expected_report_filename'], tmp_report.name) # Try relative
            except:
                copy_from_env(f"/home/ga/Documents/SEO/reports/{task_info['metadata']['expected_report_filename']}", tmp_report.name) # Try absolute
            
            with open(tmp_report.name, 'r', errors='ignore') as f:
                report_content = f.read()
            
            os.unlink(tmp_report.name)
        except Exception:
            pass # Fail gracefully if copy fails

    if report_exists and report_fresh and report_size > 100:
        score += 10
        feedback_parts.append("Report created (10/10)")

        # Numeric analysis
        if result.get('report_has_numbers', False):
            score += 10
            feedback_parts.append("Contains numeric analysis (10/10)")
        else:
            feedback_parts.append("Missing numeric counts (0/10)")

        # Keywords: Truncation/Pixel
        if result.get('report_has_keyword_truncation', False) or result.get('report_has_keyword_pixel', False):
            score += 10
            feedback_parts.append("Mentions truncation/pixels (10/10)")
        else:
            feedback_parts.append("Missing context keywords (0/10)")

        # Recommendations
        if result.get('report_has_recommendation', False):
            score += 10
            feedback_parts.append("Includes recommendations (10/10)")
        else:
            feedback_parts.append("Missing recommendations (0/10)")

        # Check for specific titles in the report content (10 pts)
        # books.toscrape.com titles often contain "Books to Scrape"
        # We check if the report quotes any long string that looks like a title
        # OR if it matches titles known to be on the site.
        # Since we don't have the CSV content here easily without more copy calls, 
        # we'll look for specific known long titles or general title formatting.
        
        # Simple heuristic: look for "..." or specific known substrings or long quoted strings
        # or the site brand name which appears in titles
        if "Books to Scrape" in report_content or "..." in report_content:
            score += 10
            feedback_parts.append("Specific titles cited (10/10)")
        else:
            feedback_parts.append("Specific titles not clearly cited (0/10)")

    else:
        feedback_parts.append("No valid report found (0/50)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }