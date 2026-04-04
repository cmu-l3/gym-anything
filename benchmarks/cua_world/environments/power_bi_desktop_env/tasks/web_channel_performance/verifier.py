#!/usr/bin/env python3
"""
Verifier for web_channel_performance task.

Scoring (100 points total):
- File saved (15 pts): Channel_Performance.pbix exists with substance
- Power Query type conversion (20 pts): DataMashup M code has number/text type conversion steps
- Revenue_Per_Session measure (25 pts): measure name in data model or layout
- Line chart present (20 pts): lineChart visual type in report layout
- Table + Card + Slicer (20 pts): all three supporting visual types present

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_web_channel_performance(traj, env_info, task_info):
    """Verify web channel performance report with type conversion, DAX measure, and 4 visual types."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/channel_performance_result.json", temp_file.name)
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

    # --- Criterion 1: File saved (15 pts) ---
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    if file_exists and file_size > 10000:
        score += 15
        feedback_parts.append(f"Channel_Performance.pbix saved ({file_size} bytes)")
        details['file_saved'] = True
    elif file_exists:
        score += 5
        feedback_parts.append(f"File exists but small ({file_size} bytes)")
        details['file_saved'] = False
    else:
        feedback_parts.append("Channel_Performance.pbix not found on Desktop")
        details['file_saved'] = False

    # --- Criterion 2: Power Query type conversion (20 pts) ---
    # Look for signs of type conversion in M code
    mashup_lower = mashup_code.lower()
    type_conversion_patterns = [
        'TransformColumnTypes',
        'Number.From',
        'Text.Replace',
        'Int64.Type',
        'type number',
        'type text',
        'Currency.Type',
        'Decimal.Type',
        'Value.FromText',
        'Number.FromText',
        'Table.TransformColumns',
    ]
    has_type_conversion = any(p.lower() in mashup_lower for p in type_conversion_patterns)
    # Additional check: M code has non-trivial content (not just blank report)
    has_meaningful_m = len(mashup_code) > 300

    if has_type_conversion and has_meaningful_m:
        score += 20
        feedback_parts.append("Power Query type conversion steps found in DataMashup M code")
        details['type_conversion'] = True
    elif has_meaningful_m:
        score += 8
        feedback_parts.append(f"M code present ({len(mashup_code)} chars) but explicit type conversion not detected")
        details['type_conversion'] = False
    else:
        feedback_parts.append(f"Power Query type conversion not found (M code length: {len(mashup_code)})")
        details['type_conversion'] = False

    # --- Criterion 3: Revenue_Per_Session measure (25 pts) ---
    has_rps = ('Revenue_Per_Session' in combined or
               'revenue_per_session' in combined.lower() or
               'RevenuePerSession' in combined)
    if has_rps:
        score += 25
        feedback_parts.append("Revenue_Per_Session measure found in data model or layout")
        details['revenue_per_session'] = True
    else:
        feedback_parts.append("Revenue_Per_Session DAX measure not found")
        details['revenue_per_session'] = False

    # --- Criterion 4: Line chart present (20 pts) ---
    visual_types_raw = result.get('visual_types', [])
    visual_types = [str(v).lower() for v in visual_types_raw]
    layout_lower = layout_text.lower()

    has_line = (any('line' in v for v in visual_types) or
                'linechart' in layout_lower or 'lineChart' in layout_text)
    if has_line:
        score += 20
        feedback_parts.append("Line chart visual found")
        details['line_chart'] = True
    else:
        feedback_parts.append(f"Line chart not found (found visual types: {visual_types_raw})")
        details['line_chart'] = False

    # --- Criterion 5: Table + Card + Slicer (20 pts) ---
    has_table = (any('table' in v for v in visual_types) or
                 'tableEx' in layout_text or 'tableVisual' in layout_lower or
                 'table' in layout_lower)
    has_card = (any('card' in v for v in visual_types) or 'card' in layout_lower)
    has_slicer = (any('slicer' in v for v in visual_types) or 'slicer' in layout_lower)

    support_count = sum([has_table, has_card, has_slicer])
    if support_count == 3:
        score += 20
        feedback_parts.append("All supporting visuals found (Table, Card, Slicer)")
        details['support_visuals'] = True
    elif support_count == 2:
        score += 12
        missing = [n for n, v in [('Table', has_table), ('Card', has_card), ('Slicer', has_slicer)] if not v]
        feedback_parts.append(f"2/3 supporting visuals found; missing: {missing}")
        details['support_visuals'] = False
    elif support_count == 1:
        score += 6
        feedback_parts.append("Only 1/3 supporting visuals (Table/Card/Slicer) found")
        details['support_visuals'] = False
    else:
        feedback_parts.append("Table, Card, and Slicer visuals not found")
        details['support_visuals'] = False

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "details": details,
        "subscores": {
            "file_saved": file_exists,
            "visual_types_found": visual_types_raw,
            "mashup_code_length": len(mashup_code)
        }
    }
