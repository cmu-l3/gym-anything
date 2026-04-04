#!/usr/bin/env python3
"""
Verifier for cross_source_analysis task.

Scoring (100 points total):
- File saved (15 pts): Integrated_Analysis.pbix exists with substance
- Both tables loaded (20 pts): DataMashup M code references both sales_data and employee_performance
- Region conditional column (20 pts): "Region" column added in Power Query for employee table
- Sales_Per_Head measure (20 pts): measure name in data model or layout
- Scatter Chart + Matrix visuals (25 pts): both scatterChart and pivotTable in report layout

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_cross_source_analysis(traj, env_info, task_info):
    """Verify multi-source integration report with conditional column, relationship, and complex visuals."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/cross_source_result.json", temp_file.name)
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

    mashup_code = result.get('mashup_m_code', '')
    layout_text = result.get('full_layout_search', '')
    model_text = result.get('model_text_sample', '')
    combined = mashup_code + " " + layout_text + " " + model_text
    mashup_lower = mashup_code.lower()
    layout_lower = layout_text.lower()

    # --- Criterion 1: File saved (15 pts) ---
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    if file_exists and file_size > 10000:
        score += 15
        feedback_parts.append(f"Integrated_Analysis.pbix saved ({file_size} bytes)")
        details['file_saved'] = True
    elif file_exists:
        score += 5
        feedback_parts.append(f"File exists but very small ({file_size} bytes)")
        details['file_saved'] = False
    else:
        feedback_parts.append("Integrated_Analysis.pbix not found on Desktop")
        details['file_saved'] = False

    # --- Criterion 2: Both tables loaded (20 pts) ---
    # Both CSV filenames must appear in the DataMashup M code
    has_sales = ('sales_data' in mashup_lower or 'sales_data.csv' in mashup_lower)
    has_employee = ('employee_performance' in mashup_lower or 'employee_performance.csv' in mashup_lower)

    if has_sales and has_employee:
        score += 20
        feedback_parts.append("Both data sources (sales_data + employee_performance) found in DataMashup")
        details['both_tables'] = True
    elif has_sales or has_employee:
        score += 8
        missing = 'employee_performance' if has_sales else 'sales_data'
        feedback_parts.append(f"Only one data source found; missing: {missing}")
        details['both_tables'] = False
    else:
        feedback_parts.append(f"Neither CSV filename found in DataMashup M code (code length: {len(mashup_code)})")
        details['both_tables'] = False

    # --- Criterion 3: Region conditional column in employee table (20 pts) ---
    # Check for Power Query conditional column creation that maps cities to regions
    has_region_col = (
        # Check for "Region" column being added
        ('Table.AddColumn' in mashup_code and 'region' in mashup_lower) or
        # Check for city names appearing in M code (part of the conditional mapping)
        (any(city.lower() in mashup_lower for city in ['new york', 'chicago', 'los angeles', 'houston']) and
         'region' in mashup_lower) or
        # Check for conditional column type keywords
        ('if' in mashup_lower and 'region' in mashup_lower and 'east' in mashup_lower.lower()) or
        # Check layout for Region column from employee table
        ('employee' in combined.lower() and 'region' in combined.lower())
    )
    if has_region_col:
        score += 20
        feedback_parts.append("Region conditional column found in Power Query (city → cardinal direction mapping)")
        details['region_column'] = True
    else:
        feedback_parts.append("Region conditional column not found in employee table Power Query steps")
        details['region_column'] = False

    # --- Criterion 4: Sales_Per_Head measure (20 pts) ---
    has_sph = ('Sales_Per_Head' in combined or
               'sales_per_head' in combined.lower() or
               'SalesPerHead' in combined)
    if has_sph:
        score += 20
        feedback_parts.append("Sales_Per_Head measure found in data model or layout")
        details['sales_per_head'] = True
    else:
        feedback_parts.append("Sales_Per_Head DAX measure not found")
        details['sales_per_head'] = False

    # --- Criterion 5: Scatter Chart + Matrix both present (25 pts) ---
    visual_types_raw = result.get('visual_types', [])
    visual_types = [str(v).lower() for v in visual_types_raw]

    has_scatter = (any('scatter' in v for v in visual_types) or
                   'scatterChart' in layout_text or 'scatter' in layout_lower)
    has_matrix = (any('pivot' in v or 'matrix' in v for v in visual_types) or
                  'pivotTable' in layout_text or 'matrix' in layout_lower)

    if has_scatter and has_matrix:
        score += 25
        feedback_parts.append("Both Scatter Chart and Matrix visuals found")
        details['complex_visuals'] = True
    elif has_scatter:
        score += 12
        feedback_parts.append("Scatter Chart found but Matrix missing")
        details['complex_visuals'] = False
    elif has_matrix:
        score += 12
        feedback_parts.append("Matrix found but Scatter Chart missing")
        details['complex_visuals'] = False
    else:
        feedback_parts.append(f"Neither Scatter Chart nor Matrix found (found: {visual_types_raw})")
        details['complex_visuals'] = False

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": details,
        "subscores": {
            "file_saved": file_exists,
            "page_names": result.get('page_names', []),
            "visual_types_found": visual_types_raw,
            "mashup_code_length": len(mashup_code),
            "has_sales_data": has_sales if file_exists else False,
            "has_employee_data": has_employee if file_exists else False
        }
    }
