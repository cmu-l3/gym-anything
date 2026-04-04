#!/usr/bin/env python3
"""Verifier for export_portfolio_csv task."""

import json
import tempfile
import os


def verify_export_portfolio_csv(traj, env_info, task_info):
    """Verify that account transactions were exported to CSV."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_rows = metadata.get('min_rows_expected', 3)
    expected_columns = metadata.get('expected_columns_contain', ['Date', 'Value', 'Type'])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/export_csv_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: CSV file was created (25 points)
    if result.get('csv_found'):
        score += 25
        feedback.append(f"CSV file found: {result.get('csv_file', '')}")
    else:
        feedback.append("No CSV export file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: File has header row (15 points)
    header = result.get('csv_header', '')
    if header:
        score += 15
        feedback.append(f"Header present: {header[:80]}...")
    else:
        feedback.append("No header row detected")

    # Criterion 3: Has expected columns (20 points)
    has_date = result.get('has_date_column', False)
    has_value = result.get('has_value_column', False)
    has_type = result.get('has_type_column', False)

    col_score = 0
    col_names = []
    if has_date:
        col_score += 7
        col_names.append("Date")
    if has_value:
        col_score += 7
        col_names.append("Value")
    if has_type:
        col_score += 6
        col_names.append("Type")

    score += col_score
    if col_names:
        feedback.append(f"Expected columns found: {', '.join(col_names)}")
    else:
        feedback.append("Expected columns (Date, Value, Type) not detected in header")

    # Criterion 4: Sufficient data rows (20 points)
    row_count = result.get('csv_row_count', 0)
    data_rows = max(0, row_count - 1)  # Subtract header
    if data_rows >= min_rows:
        score += 20
        feedback.append(f"Sufficient data: {data_rows} rows (minimum {min_rows})")
    elif data_rows > 0:
        score += 10
        feedback.append(f"Some data: {data_rows} rows (expected >= {min_rows})")
    else:
        feedback.append(f"No data rows (expected >= {min_rows})")

    # Criterion 5: Content correctness - exported data matches source portfolio (20 points)
    # The source portfolio has DEPOSIT, INTEREST, and REMOVAL transactions
    has_deposits = result.get('has_deposit_entries', False)
    has_removals = result.get('has_removal_entries', False)

    content_score = 0
    if has_deposits:
        content_score += 10
        feedback.append("Deposit entries found in export")
    else:
        feedback.append("No deposit entries found (source portfolio has deposits)")

    if has_removals:
        content_score += 10
        feedback.append("Removal/withdrawal entries found in export")
    else:
        # Partial credit if at least deposits are present
        feedback.append("No removal entries found (source portfolio has a withdrawal)")

    score += content_score

    passed = score >= 60 and result.get('csv_found') and data_rows > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
