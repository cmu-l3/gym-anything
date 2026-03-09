#!/usr/bin/env python3
"""
Verifier for hr_workforce_analytics task.

Scoring (100 points total):
- File saved (15 pts): HR_Workforce_Analytics.pbix exists with substance
- Page named "Workforce Analysis" (20 pts): exact page name in Report/Layout
- Power Query transformation (20 pts): DataMashup M code contains null-filter step
- Performance_Tier column created (20 pts): "Performance_Tier" in M code or layout
- Three required visual types (25 pts): stacked bar, line chart, and slicer all present

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_hr_workforce_analytics(traj, env_info, task_info):
    """Verify HR analytics report with Power Query transformation and three visual types."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/hr_workforce_result.json", temp_file.name)
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

    # Combined searchable text
    mashup_code = result.get('mashup_m_code', '')
    layout_text = result.get('full_layout_search', '')
    model_text = result.get('model_text_sample', '')
    combined = mashup_code + " " + layout_text + " " + model_text

    # --- Criterion 1: File saved (15 pts) ---
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    if file_exists and file_size > 10000:
        score += 15
        feedback_parts.append(f"HR_Workforce_Analytics.pbix saved ({file_size} bytes)")
        details['file_saved'] = True
    elif file_exists:
        score += 5
        feedback_parts.append(f"File exists but small ({file_size} bytes)")
        details['file_saved'] = False
    else:
        feedback_parts.append("HR_Workforce_Analytics.pbix not found on Desktop")
        details['file_saved'] = False

    # --- Criterion 2: Page named "Workforce Analysis" (20 pts) ---
    page_names = [str(n).strip() for n in result.get('page_names', [])]
    page_names_lower = [n.lower() for n in page_names]
    has_correct_page = any('workforce' in n and 'analysis' in n for n in page_names_lower)
    if has_correct_page:
        score += 20
        feedback_parts.append("Page 'Workforce Analysis' found")
        details['page_name_correct'] = True
    else:
        feedback_parts.append(f"Page named 'Workforce Analysis' not found (found: {page_names})")
        details['page_name_correct'] = False

    # --- Criterion 3: Power Query null-filter step (20 pts) ---
    # Common M code patterns for null filtering: Table.SelectRows with null check,
    # or removing null rows, or filtering blanks
    filter_patterns = [
        'Table.SelectRows',
        'null',
        'SelectRows',
        'RemoveRowsWithErrors',
        'Table.RemoveRowsWithErrors',
        'is not null',
        '<> null',
        'each [',  # common start of row filter lambda
    ]
    mashup_lower = mashup_code.lower()
    has_filter = (any(p.lower() in mashup_lower for p in filter_patterns) or
                  'table.selectrows' in mashup_lower or
                  'null' in mashup_lower)
    # More specific check: filter combined with Performance Score column
    has_perf_filter = (('performance' in mashup_lower and ('null' in mashup_lower or 'selectrows' in mashup_lower)) or
                       ('Performance Score' in mashup_code))
    if has_perf_filter or (has_filter and len(mashup_code) > 200):
        score += 20
        feedback_parts.append("Power Query filter step detected in DataMashup M code")
        details['power_query_filter'] = True
    else:
        feedback_parts.append(f"Power Query null-filter step not found in M code (code length: {len(mashup_code)})")
        details['power_query_filter'] = False

    # --- Criterion 4: Performance_Tier conditional column (20 pts) ---
    has_tier = ('Performance_Tier' in combined or
                'performance_tier' in combined.lower() or
                'PerformanceTier' in combined or
                # Also accept if Table.AddColumn is present (used for conditional columns)
                ('Table.AddColumn' in mashup_code and 'performance' in mashup_lower))
    if has_tier:
        score += 20
        feedback_parts.append("Performance_Tier column found in Power Query or data model")
        details['performance_tier'] = True
    else:
        feedback_parts.append("Performance_Tier conditional column not found")
        details['performance_tier'] = False

    # --- Criterion 5: Three required visual types (25 pts) ---
    visual_types_raw = result.get('visual_types', [])
    visual_types = [str(v).lower() for v in visual_types_raw]
    layout_lower = layout_text.lower()

    has_bar = (any('bar' in v or 'stacked' in v or 'column' in v for v in visual_types) or
               'stackedbar' in layout_lower or 'stackedcolumn' in layout_lower or
               'clusteredbar' in layout_lower or 'clusteredcolumn' in layout_lower or
               'barchart' in layout_lower)
    has_line = (any('line' in v for v in visual_types) or
                'linechart' in layout_lower or 'lineChart' in layout_text)
    has_slicer = (any('slicer' in v for v in visual_types) or
                  'slicer' in layout_lower)

    visuals_found = sum([has_bar, has_line, has_slicer])
    if visuals_found == 3:
        score += 25
        feedback_parts.append("All three visuals found (Stacked Bar, Line Chart, Slicer)")
        details['visual_types'] = True
    elif visuals_found == 2:
        score += 15
        missing = [n for n, v in [('Bar', has_bar), ('Line', has_line), ('Slicer', has_slicer)] if not v]
        feedback_parts.append(f"2/3 required visuals found; missing: {missing}")
        details['visual_types'] = False
    elif visuals_found == 1:
        score += 8
        feedback_parts.append(f"Only 1/3 required visuals found (found: {visual_types_raw})")
        details['visual_types'] = False
    else:
        feedback_parts.append(f"No required visuals found (found: {visual_types_raw})")
        details['visual_types'] = False

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": details,
        "subscores": {
            "file_saved": file_exists,
            "page_names": page_names,
            "visual_types_found": visual_types_raw,
            "mashup_code_length": len(mashup_code)
        }
    }
