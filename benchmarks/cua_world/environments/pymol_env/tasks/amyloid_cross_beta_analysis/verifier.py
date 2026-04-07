#!/usr/bin/env python3
"""
Verifier for the Alzheimer's Amyloid Fibril Cross-Beta Architecture Analysis task.

Scoring (100 points total):
  25 pts - Publication figure exists at correct path, is new (post-task-start), and >40KB
  15 pts - Report file exists and has minimum content length (>50 chars)
  30 pts - Report contains the inter-strand distance in the expected range (4.6 - 5.0 Å)
  30 pts - Report contains the inter-sheet distance in the expected range (9.5 - 10.5 Å)

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate: rules out pre-existing image templates.
  - Strict quantitative range checks for the physical dimensions ensures the agent
    must perform actual intra- and inter-chain distance measurements on the NMR state 1 model.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_amyloid_cross_beta_analysis(traj, env_info, task_info):
    """Verify the Amyloid cross-beta analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/amyloid_result.json')

    # securely transfer the result file from the container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (25 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 25
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/amyloid_cross_beta.png")

    # --- Criterion 2: Report existence (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')
    min_chars = metadata.get('min_report_chars', 50)

    if report_exists and len(report_content.strip()) >= min_chars:
        score += 15
        parts.append(f"Report exists and has sufficient length ({len(report_content.strip())} chars)")
    elif report_exists:
        parts.append(f"Report exists but is too short ({len(report_content.strip())} chars)")
    else:
        parts.append("Report not found at /home/ga/PyMOL_Data/amyloid_dimensions.txt")

    # --- Criteria 3 & 4: Distance Extractions (30 pts each) ---
    inter_strand_min = metadata.get('inter_strand_min', 4.6)
    inter_strand_max = metadata.get('inter_strand_max', 5.0)
    inter_sheet_min = metadata.get('inter_sheet_min', 9.5)
    inter_sheet_max = metadata.get('inter_sheet_max', 10.5)

    # Extract all decimal numbers from the report
    all_decimals = [float(n) for n in re.findall(r'\d+\.\d+', report_content)]
    
    valid_inter_strand = [d for d in all_decimals if inter_strand_min <= d <= inter_strand_max]
    if valid_inter_strand:
        score += 30
        parts.append(f"Inter-strand distance correctly reported: {valid_inter_strand[0]:.2f} \u00c5")
    elif all_decimals:
        parts.append(f"Decimals found but none match inter-strand range ({inter_strand_min}-{inter_strand_max} \u00c5)")
    else:
        parts.append("No decimal values found for inter-strand distance")

    valid_inter_sheet = [d for d in all_decimals if inter_sheet_min <= d <= inter_sheet_max]
    if valid_inter_sheet:
        score += 30
        parts.append(f"Inter-sheet distance correctly reported: {valid_inter_sheet[0]:.2f} \u00c5")
    elif all_decimals:
        parts.append(f"Decimals found but none match inter-sheet range ({inter_sheet_min}-{inter_sheet_max} \u00c5)")
    else:
        parts.append("No decimal values found for inter-sheet distance")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts),
        "subscores": {
            "figure_created": fig_exists and fig_is_new,
            "report_created": report_exists,
            "inter_strand_measured": len(valid_inter_strand) > 0,
            "inter_sheet_measured": len(valid_inter_sheet) > 0
        }
    }