#!/usr/bin/env python3
"""Verifier for XPath Meta Extraction Audit task.

Scoring (100 points total):
- CSV file exists and was created after task start (10 pts)
- CSV contains books.toscrape.com URLs (15 pts)
- CSV has ≥ 20 data rows (10 pts)
- CSV has extraction columns (checking header names or content) (15 pts)
- At least one column has non-empty extracted values (15 pts)
- Viewport values match expected pattern (proof of specific XPath success) (5 pts)
- Report file exists with ≥ 300 chars (10 pts)
- Report contains numeric counts/percentages (10 pts)
- Report mentions meta tag types by name (5 pts)
- Report includes recommendations (5 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import re
import logging

logger = logging.getLogger(__name__)

def verify_xpath_meta_extraction_audit(traj, env_info, task_info):
    """Verify XPath Meta Extraction Audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load Result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/xpath_meta_extraction_audit_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # --- CSV Verification (70 points total) ---
    
    csv_exists = result.get('csv_exists', False)
    if csv_exists:
        score += 10
        feedback_parts.append("CSV created (10/10)")
    else:
        feedback_parts.append("No valid CSV found (0/10)")

    if csv_exists:
        # Domain Check
        if result.get('csv_has_target_domain', False):
            score += 15
            feedback_parts.append("Target domain URLs found (15/15)")
        else:
            feedback_parts.append("Target domain URLs missing from CSV (0/15)")

        # Row Count Check
        rows = result.get('csv_row_count', 0)
        if rows >= 20:
            score += 10
            feedback_parts.append(f"Sufficient rows: {rows} (10/10)")
        elif rows > 0:
            score += 5
            feedback_parts.append(f"Some rows found: {rows} (5/10)")
        else:
            feedback_parts.append("CSV is empty (0/10)")

        # Columns/Extraction Check
        # We look for indications that custom extraction happened
        # If headers contain "Extraction" or user specific names like "Viewport"
        headers = result.get('csv_columns', '').lower()
        has_extraction_headers = any(x in headers for x in ['extraction', 'viewport', 'charset', 'og:', 'title', 'image'])
        
        if has_extraction_headers:
            score += 15
            feedback_parts.append("Extraction columns detected (15/15)")
        else:
            feedback_parts.append("No obvious extraction columns in header (0/15)")

        # Data Content Check
        if result.get('csv_has_extraction_data', False):
            score += 15
            feedback_parts.append("Extracted data found (15/15)")
        else:
            feedback_parts.append("No extracted data detected (0/15)")
            
        # Specific XPath Proof (Viewport)
        if result.get('csv_has_viewport_data', False):
            score += 5
            feedback_parts.append("Viewport XPath validated (5/5)")
        else:
            feedback_parts.append("Viewport specific data missing (0/5)")

    # --- Report Verification (30 points total) ---
    
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content_preview', '').lower()
    
    if report_exists:
        # Size Check
        size = result.get('report_size', 0)
        if size >= 300:
            score += 10
            feedback_parts.append(f"Report length OK: {size} bytes (10/10)")
        elif size > 50:
            score += 5
            feedback_parts.append(f"Report too short: {size} bytes (5/10)")
        else:
            feedback_parts.append("Report empty or nearly empty (0/10)")
            
        # Numeric Data Check
        # Look for numbers (digits)
        if re.search(r'\d+', report_content):
            score += 10
            feedback_parts.append("Numeric analysis found (10/10)")
        else:
            feedback_parts.append("No numeric counts found in report (0/10)")
            
        # Terminology Check
        tags_found = sum(1 for tag in ['viewport', 'charset', 'og:title', 'og:image', 'open graph'] if tag in report_content)
        if tags_found >= 2:
            score += 5
            feedback_parts.append("Meta tags mentioned (5/5)")
        else:
            feedback_parts.append("Meta tags not specifically mentioned (0/5)")
            
        # Recommendations Check
        recs_found = any(word in report_content for word in ['recommend', 'should', 'missing', 'add', 'fix', 'ensure'])
        if recs_found:
            score += 5
            feedback_parts.append("Recommendations found (5/5)")
        else:
            feedback_parts.append("No recommendations found (0/5)")
            
    else:
        feedback_parts.append("No report file found (0/30)")

    # --- Final Score ---
    passed = score >= 60 and csv_exists and result.get('csv_has_extraction_data', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }