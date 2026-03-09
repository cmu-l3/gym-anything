#!/usr/bin/env python3
"""
Verifier for js_rendering_gap_audit task.

Verifies:
1. Screaming Frog crawl data was exported to CSV.
2. CSV contains "Rendered" columns (Proof of JS rendering configuration).
3. CSV contains data for quotes.toscrape.com.
4. Data shows evidence of content gap (Rendered Word Count > Original).
5. Analysis report exists and contains relevant keywords.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_js_rendering_gap_audit(traj, env_info, task_info):
    """
    Verify the JS Rendering Audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Export CSV Created (15 pts)
    # Must be new and contain the target domain
    if result.get('csv_found', False) and result.get('has_target_domain', False):
        score += 15
        feedback_parts.append("Valid export CSV found (15/15)")
    elif result.get('csv_found', False):
        score += 5
        feedback_parts.append("CSV found but wrong domain (5/15)")
    else:
        feedback_parts.append("No export CSV found (0/15)")

    # Criterion 2: JS Rendering Configured (30 pts)
    # Verified by presence of 'Rendered' columns in output
    if result.get('has_rendered_columns', False):
        score += 30
        feedback_parts.append("JS Rendering confirmed via columns (30/30)")
    else:
        feedback_parts.append("No 'Rendered' columns found - JS rendering likely not enabled (0/30)")

    # Criterion 3: Content Gap Detected (20 pts)
    # Data analysis showed Rendered WC > Original WC
    if result.get('gap_detected', False):
        score += 20
        feedback_parts.append("Content gap verified in data (20/20)")
    else:
        feedback_parts.append("No content gap detected in data (0/20)")

    # Criterion 4: Report Created (20 pts)
    if result.get('report_exists', False) and result.get('report_valid', False):
        score += 20
        feedback_parts.append("Analysis report valid (20/20)")
    elif result.get('report_exists', False):
        score += 10
        feedback_parts.append("Report exists but lacks keywords/length (10/20)")
    else:
        feedback_parts.append("No report found (0/20)")

    # Criterion 5: App Running/State (15 pts)
    # Or just general completion signal if other artifacts are good
    if result.get('sf_running', False) or result.get('csv_found', False):
        score += 15
        feedback_parts.append("App usage verified (15/15)")

    # Pass threshold: 60 points
    # Crucially, simply running a crawl (Text only) gets: 15 (CSV) + 15 (App) + 0 (No Render cols) + 0 (No gap) + 0/20 (Report) = ~30 points. Fail.
    # Enabling JS is required to get the 30 pts + 20 pts.
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }