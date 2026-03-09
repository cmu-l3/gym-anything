#!/usr/bin/env python3
"""
Verifier for Structured Data Schema Audit task.

Scoring Criteria (Total 100):
1. Crawl Executed & Domain Verified (15 pts)
   - At least one CSV contains books.toscrape.com URLs
2. Structured Data CSV Exported (20 pts)
   - File exists, created during task, contains structured data columns
3. Internal HTML CSV Exported (15 pts)
   - Standard report exported for cross-reference
4. Sufficient Crawl Coverage (10 pts)
   - At least 50 URLs found in exports
5. Report File Exists (10 pts)
   - File exists at correct path with minimum size
6. Report Content Quality (30 pts)
   - Contains specific keywords and recommendations
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_structured_data_audit(traj, env_info, task_info):
    """Verify the structured data audit task."""
    
    # 1. Setup: Copy result file from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Result Data
    metadata = task_info.get('metadata', {})
    min_urls = metadata.get('min_urls_expected', 50)
    min_report_length = metadata.get('min_report_length', 300)
    
    score = 0
    feedback = []
    
    # --- Criterion 1: Crawl Executed & Domain Verified (15 pts) ---
    domain_found = result.get('target_domain_found', False)
    sf_running = result.get('sf_running', False)
    
    if domain_found:
        score += 15
        feedback.append("Crawl verified on target domain (15/15)")
    else:
        feedback.append("Target domain (books.toscrape.com) NOT found in exports (0/15)")
        
    # --- Criterion 2: Structured Data CSV Exported (20 pts) ---
    struct_csv_found = result.get('structured_data_csv_found', False)
    has_jsonld = result.get('has_jsonld_col', False)
    struct_rows = result.get('structured_data_rows', 0)
    
    if struct_csv_found and (has_jsonld or struct_rows > 0):
        score += 20
        feedback.append(f"Structured Data CSV found with {struct_rows} rows (20/20)")
    elif struct_csv_found:
        score += 10
        feedback.append("Structured Data CSV found but empty or missing specific columns (10/20)")
    else:
        feedback.append("Structured Data CSV export NOT found (0/20)")

    # --- Criterion 3: Internal HTML CSV Exported (15 pts) ---
    internal_csv_found = result.get('internal_html_csv_found', False)
    internal_rows = result.get('internal_html_rows', 0)
    
    if internal_csv_found and internal_rows > 0:
        score += 15
        feedback.append(f"Internal HTML CSV found with {internal_rows} rows (15/15)")
    else:
        feedback.append("Internal HTML CSV export NOT found (0/15)")

    # --- Criterion 4: Sufficient Crawl Coverage (10 pts) ---
    # Use the max row count from either CSV
    max_rows = max(struct_rows, internal_rows)
    
    if max_rows >= min_urls:
        score += 10
        feedback.append(f"Crawl coverage sufficient ({max_rows} URLs) (10/10)")
    elif max_rows > 0:
        # Partial credit
        partial = int(10 * (max_rows / min_urls))
        score += partial
        feedback.append(f"Crawl coverage partial ({max_rows}/{min_urls} URLs) ({partial}/10)")
    else:
        feedback.append("No URLs found in exports (0/10)")

    # --- Criterion 5: Report File Exists (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    
    if report_exists and report_size >= min_report_length:
        score += 10
        feedback.append(f"Report file exists and meets length requirement ({report_size} bytes) (10/10)")
    elif report_exists:
        score += 5
        feedback.append(f"Report file exists but is too short ({report_size} < {min_report_length} bytes) (5/10)")
    else:
        feedback.append("Report file NOT found (0/10)")

    # --- Criterion 6: Report Content Quality (30 pts) ---
    report_valid = result.get('report_content_valid', False)
    
    if report_valid and report_exists:
        score += 30
        feedback.append("Report content valid (contains expected keywords) (30/30)")
    elif report_exists:
        feedback.append("Report content missing specific structured data keywords (0/30)")
    else:
        feedback.append("No report to analyze (0/30)")

    # --- Final Result ---
    # Pass threshold: 60 points + Domain Verified
    passed = (score >= 60) and domain_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }