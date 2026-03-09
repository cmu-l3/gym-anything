#!/usr/bin/env python3
"""
Verifier for export_crawl_report task.

Checks that a CSV export file was created with crawl data.
"""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_crawl_report(traj, env_info, task_info):
    """
    Verify that a crawl report was exported successfully.

    Checks:
    1. A new CSV file was created
    2. The file contains valid data (rows)
    3. The file has meaningful content (URLs, etc.)
    4. Screaming Frog was used (still running or closed properly)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_min_rows = metadata.get('expected_min_rows', 3)

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Copy result file from container
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

    # Criterion 1: New file was created (30 pts)
    file_created = result.get('file_created', False)
    new_files_count = result.get('new_files_count', 0)
    modified_files = result.get('modified_files_count', 0)

    if file_created or new_files_count > 0 or modified_files > 0:
        criteria_met += 1
        score += 30
        feedback_parts.append(f"Export file created ({new_files_count} new, {modified_files} modified)")
    else:
        feedback_parts.append("No export file created")

    # Criterion 2: File has valid content (25 pts)
    file_valid = result.get('file_content_valid', False)
    csv_rows = result.get('newest_csv_rows', 0)

    if file_valid and csv_rows >= expected_min_rows:
        criteria_met += 1
        score += 25
        feedback_parts.append(f"CSV has {csv_rows} data rows")
    elif csv_rows > 0:
        score += 15  # Partial credit
        feedback_parts.append(f"CSV has {csv_rows} rows (expected >= {expected_min_rows})")
    else:
        feedback_parts.append(f"CSV has no data rows (expected >= {expected_min_rows})")

    # Criterion 3: Try to verify the actual CSV content (25 pts)
    # MUST contain crawler-test.com URLs to prevent exporting wrong site
    csv_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_valid = False
    csv_headers = []
    domain_verified = False
    try:
        copy_from_env("/tmp/exported_crawl_report.csv", csv_temp.name)
        with open(csv_temp.name, 'r', newline='', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            f.seek(0)
            reader = csv.reader(f)
            rows = list(reader)
            if len(rows) > 1:
                csv_headers = rows[0] if rows else []

                # STRICT: Check that export contains crawler-test.com URLs
                if 'crawler-test' in content.lower():
                    domain_verified = True
                    csv_valid = True
                    criteria_met += 1
                    score += 25
                    # Check for common Screaming Frog columns
                    common_cols = ['Address', 'URL', 'Status Code', 'Content', 'Title']
                    found_cols = [c for c in common_cols if any(c.lower() in h.lower() for h in csv_headers)]
                    feedback_parts.append(f"CSV valid with crawler-test.com data, columns: {', '.join(found_cols[:3]) if found_cols else 'custom'}")
                else:
                    # CSV exists but contains wrong domain
                    score += 5  # Minimal credit for having some export
                    feedback_parts.append("CSV exists but does NOT contain crawler-test.com URLs - wrong domain exported")
    except Exception as e:
        feedback_parts.append(f"Could not verify CSV content: {str(e)[:50]}")
    finally:
        if os.path.exists(csv_temp.name):
            os.unlink(csv_temp.name)

    # Criterion 4: Screaming Frog involvement (20 pts)
    sf_running = result.get('screaming_frog_running', False)
    if sf_running:
        criteria_met += 1
        score += 20
        feedback_parts.append("Screaming Frog active")
    else:
        # Could have been closed after export - partial credit if file exists
        if file_created:
            score += 10
            feedback_parts.append("Screaming Frog closed (export completed)")
        else:
            feedback_parts.append("Screaming Frog not running")

    # STRICT pass criteria: file created + valid content + correct domain
    # Must contain crawler-test.com URLs to prevent gaming with wrong domain
    passed = (file_created or new_files_count > 0) and (csv_rows > 0 or csv_valid) and domain_verified

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "file_created": file_created,
            "csv_rows": csv_rows,
            "csv_valid": csv_valid,
            "domain_verified": domain_verified,
            "screaming_frog_running": sf_running
        }
    }
