#!/usr/bin/env python3
"""
Verifier for Canonical Chain Diagnosis task.

Criteria:
1. Screaming Frog ran (App detection)
2. Canonical Chains CSV exported (File existence + Timestamp)
3. CSV is the *correct* report type (Header analysis for 'Chain Length')
   - Crucial: Standard crawl exports do not show chain length.
   - This proves the agent ran 'Crawl Analysis'.
4. CSV contains valid data from target domain
5. Summary text matches the CSV data count
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_canonical_chain_diagnosis(traj, env_info, task_info):
    """Verify canonical chain diagnosis workflow."""
    
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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

    score = 0
    feedback_parts = []
    
    # --- Evaluation ---

    # 1. App Running (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # 2. CSV Existence & Freshness (20 pts)
    if result.get('csv_fresh', False):
        score += 20
        feedback_parts.append("Report CSV created (20/20)")
    elif result.get('csv_exists', False):
        # Exists but old? likely pre-existing (though setup clears it)
        feedback_parts.append("Report CSV exists but timestamp invalid (0/20)")
    else:
        feedback_parts.append("No Report CSV found (0/20)")

    # 3. Report Correctness (Analysis Run) (30 pts)
    # Checks for specific columns like 'Chain Length' that only exist 
    # if 'Crawl Analysis' was run and the specific report was exported.
    if result.get('csv_is_chain_report', False):
        score += 30
        feedback_parts.append("Correct 'Canonical Chains' report format verified (30/30)")
    else:
        if result.get('csv_fresh', False):
            feedback_parts.append("Wrong report type - missing Chain Length/Canonical columns (0/30)")
        else:
            feedback_parts.append("Report validation skipped (file missing)")

    # 4. Data Validity (20 pts)
    # crawler-test.com has canonical chains, so we expect rows.
    row_count = result.get('csv_row_count', 0)
    domain_ok = result.get('target_domain_found', False)
    
    if row_count > 0 and domain_ok:
        score += 20
        feedback_parts.append(f"Data valid: {row_count} chains found on crawler-test.com (20/20)")
    elif row_count > 0:
        score += 10
        feedback_parts.append(f"Data found ({row_count} rows) but domain not verified (10/20)")
    else:
        feedback_parts.append("Report is empty or contains no data (0/20)")

    # 5. Summary Accuracy (20 pts)
    # The number in text file should match row count within tolerance
    summary_fresh = result.get('summary_fresh', False)
    summary_count = result.get('summary_extracted_count', -1)
    
    if summary_fresh and summary_count != -1:
        # Allow small tolerance (+/- 1 for header confusion or off-by-one)
        if abs(summary_count - row_count) <= 1:
            score += 20
            feedback_parts.append(f"Summary count ({summary_count}) matches data (20/20)")
        else:
            score += 10
            feedback_parts.append(f"Summary count ({summary_count}) mismatches data rows ({row_count}) (10/20)")
    elif summary_fresh:
        score += 5
        feedback_parts.append("Summary file exists but no number found (5/20)")
    else:
        feedback_parts.append("No summary text file found (0/20)")

    # Final logic
    passed = score >= 70  # Requires correct report type + some data
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }