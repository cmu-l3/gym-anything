#!/usr/bin/env python3
"""
Verifier for profitability_analysis task.

Scoring (100 points total):
- Report file saved (15 pts): Profitability_Report.pbix exists with substance
- Gross_Profit measure (20 pts): "Gross_Profit" in data model or layout
- Profit_Margin_Pct measure (20 pts): "Profit_Margin_Pct" in data model or layout
- Matrix visual present (20 pts): pivotTable/matrix visual type in report
- CSV exported (25 pts): profit_by_category.csv exists with numeric profit data

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_profitability_analysis(traj, env_info, task_info):
    """Verify profitability analysis report with DAX measures, matrix visual, and CSV export."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/profitability_result.json", temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    details = {}

    # Combined search text (DataModel binary + full layout JSON)
    model_text = result.get('model_text_sample', '')
    layout_text = result.get('full_layout_search', '')
    combined = model_text + " " + layout_text

    # --- Criterion 1: Report file saved (15 pts) ---
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    if file_exists and file_size > 10000:
        score += 15
        feedback_parts.append(f"Profitability_Report.pbix saved ({file_size} bytes)")
        details['file_saved'] = True
    elif file_exists:
        score += 5
        feedback_parts.append(f"File exists but very small ({file_size} bytes)")
        details['file_saved'] = False
    else:
        feedback_parts.append("Profitability_Report.pbix not found on Desktop")
        details['file_saved'] = False

    # --- Criterion 2: Gross_Profit measure (20 pts) ---
    has_gross_profit = ('Gross_Profit' in combined or
                        'gross_profit' in combined.lower() or
                        'GrossProfit' in combined)
    if has_gross_profit:
        score += 20
        feedback_parts.append("Gross_Profit measure found in data model")
        details['gross_profit_measure'] = True
    else:
        feedback_parts.append("Gross_Profit measure not found (check DAX measure creation)")
        details['gross_profit_measure'] = False

    # --- Criterion 3: Profit_Margin_Pct measure (20 pts) ---
    has_margin = ('Profit_Margin_Pct' in combined or
                  'profit_margin_pct' in combined.lower() or
                  'ProfitMarginPct' in combined or
                  'Profit_Margin' in combined)
    if has_margin:
        score += 20
        feedback_parts.append("Profit_Margin_Pct measure found in data model")
        details['profit_margin_measure'] = True
    else:
        feedback_parts.append("Profit_Margin_Pct measure not found")
        details['profit_margin_measure'] = False

    # --- Criterion 4: Matrix visual present (20 pts) ---
    visual_types_raw = result.get('visual_types', [])
    visual_types = [str(v).lower() for v in visual_types_raw]
    has_matrix = (any('pivot' in v or 'matrix' in v for v in visual_types) or
                  'pivotTable' in layout_text or 'tableMatrix' in layout_text or
                  'matrix' in layout_text.lower())
    if has_matrix:
        score += 20
        feedback_parts.append("Matrix visual found in report layout")
        details['matrix_visual'] = True
    else:
        feedback_parts.append(f"Matrix visual not found (found: {visual_types_raw})")
        details['matrix_visual'] = False

    # --- Criterion 5: CSV export (25 pts) ---
    csv_exists = result.get('csv_exists', False)
    csv_row_count = result.get('csv_row_count', 0)
    csv_preview = result.get('csv_preview', '')

    if csv_exists and csv_row_count >= 5:
        # Check that it has numeric data (profit values)
        has_numbers = any(
            any(c.isdigit() for c in line)
            for line in csv_preview.splitlines()
            if line.strip()
        )
        if has_numbers:
            score += 25
            feedback_parts.append(f"profit_by_category.csv exported ({csv_row_count} rows, numeric data confirmed)")
            details['csv_exported'] = True
        else:
            score += 12
            feedback_parts.append(f"profit_by_category.csv exists ({csv_row_count} rows) but no numeric values found")
            details['csv_exported'] = False
    elif csv_exists:
        score += 10
        feedback_parts.append(f"profit_by_category.csv exists but has only {csv_row_count} rows")
        details['csv_exported'] = False
    else:
        feedback_parts.append("profit_by_category.csv not found — export data step missing")
        details['csv_exported'] = False

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": details,
        "subscores": {
            "file_saved": file_exists,
            "visual_types_found": visual_types_raw,
            "csv_row_count": csv_row_count
        }
    }
