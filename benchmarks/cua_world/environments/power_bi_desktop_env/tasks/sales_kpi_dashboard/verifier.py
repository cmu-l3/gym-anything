#!/usr/bin/env python3
"""
Verifier for sales_kpi_dashboard task.

Scoring (100 points total):
- File saved (15 pts): Sales_KPI_Dashboard.pbix exists and has substance
- Page structure (20 pts): Has >= 2 pages named "Overview" and "Regional Detail"
- Overview visuals (20 pts): Card and Donut chart visual types present
- Regional visuals (20 pts): Clustered bar chart and slicer present
- DAX measures (25 pts): Total_Revenue and Total_Units appear in data model

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_sales_kpi_dashboard(traj, env_info, task_info):
    """Verify that the agent built a two-page KPI dashboard with correct visuals and DAX measures."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/sales_kpi_result.json", temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result JSON: {e}")
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

    # --- Criterion 1: File exists and has substance (15 pts) ---
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    if file_exists and file_size > 10000:
        score += 15
        feedback_parts.append(f"File saved ({file_size} bytes)")
        details['file_saved'] = True
    elif file_exists:
        score += 5
        feedback_parts.append(f"File exists but very small ({file_size} bytes) — may be empty/corrupt")
        details['file_saved'] = False
    else:
        feedback_parts.append("Sales_KPI_Dashboard.pbix not found on Desktop")
        details['file_saved'] = False

    # --- Criterion 2: Page structure — 2 pages named correctly (20 pts) ---
    page_count = result.get('page_count', 0)
    page_names = [str(n).lower() for n in result.get('page_names', [])]
    has_overview = any('overview' in n for n in page_names)
    has_regional = any('regional' in n or 'detail' in n for n in page_names)

    if page_count >= 2 and has_overview and has_regional:
        score += 20
        feedback_parts.append("Correct 2-page structure (Overview + Regional Detail)")
        details['page_structure'] = True
    elif page_count >= 2:
        score += 10
        feedback_parts.append(f"Has {page_count} pages but names not matching (found: {result.get('page_names', [])})")
        details['page_structure'] = False
    else:
        feedback_parts.append(f"Expected 2 pages, found {page_count}")
        details['page_structure'] = False

    # --- Criterion 3: Overview page visuals — Card + Donut (20 pts) ---
    visual_types_raw = result.get('visual_types', [])
    visual_types = [str(v).lower() for v in visual_types_raw]
    # Also check the full layout text for visual type keywords
    full_layout = result.get('full_layout_search', '').lower()

    has_card = any('card' in v for v in visual_types) or 'card' in full_layout
    has_donut = (any('donut' in v or 'pie' in v for v in visual_types) or
                 'donut' in full_layout or 'doughnut' in full_layout)

    if has_card and has_donut:
        score += 20
        feedback_parts.append("Overview visuals present (Card + Donut)")
        details['overview_visuals'] = True
    elif has_card:
        score += 10
        feedback_parts.append("Card visual present but Donut chart missing")
        details['overview_visuals'] = False
    elif has_donut:
        score += 10
        feedback_parts.append("Donut chart present but Card visual missing")
        details['overview_visuals'] = False
    else:
        feedback_parts.append(f"Missing Card and Donut visuals (found: {visual_types_raw})")
        details['overview_visuals'] = False

    # --- Criterion 4: Regional page visuals — Clustered Bar + Slicer (20 pts) ---
    has_bar = (any('bar' in v or 'clustered' in v or 'column' in v for v in visual_types) or
               'clusteredbar' in full_layout or 'clusteredcolumn' in full_layout or
               'barchart' in full_layout)
    has_slicer = any('slicer' in v for v in visual_types) or 'slicer' in full_layout

    if has_bar and has_slicer:
        score += 20
        feedback_parts.append("Regional visuals present (Clustered Bar + Slicer)")
        details['regional_visuals'] = True
    elif has_bar:
        score += 10
        feedback_parts.append("Bar chart present but Slicer missing")
        details['regional_visuals'] = False
    elif has_slicer:
        score += 10
        feedback_parts.append("Slicer present but Bar chart missing")
        details['regional_visuals'] = False
    else:
        feedback_parts.append("Missing Clustered Bar chart and Slicer")
        details['regional_visuals'] = False

    # --- Criterion 5: DAX measures — Total_Revenue and Total_Units (25 pts) ---
    model_text = result.get('model_text_sample', '')
    layout_search = result.get('full_layout_search', '')
    combined_text = model_text + " " + layout_search

    has_total_revenue = 'Total_Revenue' in combined_text or 'total_revenue' in combined_text.lower()
    has_total_units = 'Total_Units' in combined_text or 'total_units' in combined_text.lower()

    if has_total_revenue and has_total_units:
        score += 25
        feedback_parts.append("Both DAX measures found (Total_Revenue, Total_Units)")
        details['dax_measures'] = True
    elif has_total_revenue:
        score += 12
        feedback_parts.append("Total_Revenue measure found; Total_Units missing")
        details['dax_measures'] = False
    elif has_total_units:
        score += 12
        feedback_parts.append("Total_Units measure found; Total_Revenue missing")
        details['dax_measures'] = False
    else:
        feedback_parts.append("DAX measures Total_Revenue and Total_Units not found in data model")
        details['dax_measures'] = False

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": details,
        "subscores": {
            "file_saved": result.get('file_exists', False),
            "page_count": page_count,
            "page_names": result.get('page_names', []),
            "visual_types": visual_types_raw
        }
    }
