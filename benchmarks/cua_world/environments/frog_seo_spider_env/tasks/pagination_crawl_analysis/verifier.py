#!/usr/bin/env python3
"""Verifier for Pagination Crawl Analysis task.

Scoring (100 points total):
- CSV Export (60 pts):
  - File exists and created during task (10 pts)
  - Contains books.toscrape.com URLs (15 pts)
  - Total internal URL count >= 50 (15 pts)
  - Paginated URL count (containing '/page-') >= 10 (20 pts)
    * CRITICAL: Must have paginated URLs to pass
- Report (40 pts):
  - File exists and created during task (10 pts)
  - File size >= 300 bytes (substantial content) (10 pts)
  - Content appears valid (numbers + keywords) (20 pts)

Pass threshold: 60 points AND (paginated_url_count >= 10)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_pagination_crawl_analysis(traj, env_info, task_info):
    """Verify pagination crawl analysis task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Get metadata requirements
    metadata = task_info.get('metadata', {})
    min_total = metadata.get('min_total_urls', 50)
    min_paginated = metadata.get('min_paginated_urls', 10)

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/pagination_crawl_analysis_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON invalid: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # --- CSV Evaluation (60 pts) ---
    csv_found = result.get('export_csv_found', False)
    domain_found = result.get('target_domain_found', False)
    total_rows = result.get('export_row_count', 0)
    paginated_count = result.get('paginated_url_count', 0)

    if csv_found:
        score += 10
        feedback_parts.append("CSV exported (10/10)")
        
        if domain_found:
            score += 15
            feedback_parts.append("Correct domain found (15/15)")
            
            if total_rows >= min_total:
                score += 15
                feedback_parts.append(f"Total URLs {total_rows} >= {min_total} (15/15)")
            else:
                feedback_parts.append(f"Total URLs {total_rows} < {min_total} (0/15)")
                
            if paginated_count >= min_paginated:
                score += 20
                feedback_parts.append(f"Paginated URLs {paginated_count} >= {min_paginated} (20/20)")
            elif paginated_count > 0:
                # Partial credit for finding some
                score += 5
                feedback_parts.append(f"Paginated URLs {paginated_count} < {min_paginated} (5/20)")
            else:
                feedback_parts.append("No paginated URLs found (0/20)")
        else:
            feedback_parts.append("Export does not contain target domain URLs (0/50)")
    else:
        feedback_parts.append("No valid CSV export found (0/60)")

    # --- Report Evaluation (40 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    report_valid = result.get('report_content_valid', False)

    if report_exists:
        score += 10
        feedback_parts.append("Report file created (10/10)")
        
        if report_size >= 300:
            score += 10
            feedback_parts.append(f"Report length {report_size} bytes (10/10)")
        elif report_size > 50:
            score += 5
            feedback_parts.append(f"Report length {report_size} bytes (too short) (5/10)")
        else:
            feedback_parts.append("Report empty or trivial (0/10)")
            
        if report_valid:
            score += 20
            feedback_parts.append("Report content valid (nums + keywords) (20/20)")
        else:
            feedback_parts.append("Report content missing key elements (0/20)")
    else:
        feedback_parts.append("No report file found (0/40)")

    # --- Final Verdict ---
    # Critical pass condition: Must have discovered paginated URLs
    critical_condition = paginated_count >= min_paginated
    passed = (score >= 60) and critical_condition
    
    if not critical_condition and score >= 60:
        feedback_parts.append("FAILED: Did not discover enough paginated URLs to pass, despite high score.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "csv_found": csv_found,
            "paginated_count": paginated_count,
            "report_found": report_exists,
            "report_valid": report_valid
        }
    }