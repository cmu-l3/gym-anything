#!/usr/bin/env python3
"""Verifier for export_to_csv task.

Checks that the agent exported the SRS document to CSV at the expected path.

Verification criteria:
1. File exists at /home/ga/Documents/srs_export.csv
2. File size >= 100 bytes
3. File is parseable as CSV with at least 2 rows (header + data)
4. Header row contains expected columns (ID and at least one other column)
"""

import csv
import io
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CSV_PATH = "/home/ga/Documents/srs_export.csv"


def verify_export_to_csv(traj, env_info, task_info):
    """Verify the SRS document was exported to CSV."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', CSV_PATH)
    min_size = metadata.get('min_file_size_bytes', 100)

    # Copy CSV file from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_path, tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"File not found at {expected_path}: {e}"
        }

    score = 0
    feedback_parts = []
    details = {}

    try:
        file_size = os.path.getsize(tmp.name)
        details['file_size'] = file_size

        # Check 1: File exists with sufficient size (40 points)
        if file_size >= min_size:
            score += 40
            feedback_parts.append(f"File exists ({file_size} bytes)")
        else:
            feedback_parts.append(f"File too small ({file_size} bytes, expected >= {min_size})")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Check 2: File is valid CSV with multiple rows (35 points)
        with open(tmp.name, newline='', encoding='utf-8', errors='replace') as f:
            content = f.read()

        reader = csv.reader(io.StringIO(content))
        rows = list(reader)
        details['row_count'] = len(rows)

        if len(rows) >= 2:
            score += 35
            feedback_parts.append(f"Valid CSV with {len(rows)} rows")
        elif len(rows) == 1:
            score += 15
            feedback_parts.append("CSV has only a header row — no data rows")
        else:
            feedback_parts.append("CSV is empty")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Check 3: Header contains an ID column (25 points)
        header = [col.strip().upper() for col in rows[0]]
        details['header'] = rows[0]
        if 'ID' in header or any('ID' in col for col in header):
            score += 25
            feedback_parts.append("Header contains ID column")
        else:
            feedback_parts.append(f"Header missing ID column (got: {rows[0][:5]})")

    except Exception as e:
        feedback_parts.append(f"CSV parse error: {e}")
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
