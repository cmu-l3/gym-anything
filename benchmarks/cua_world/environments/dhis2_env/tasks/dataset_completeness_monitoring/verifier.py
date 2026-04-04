#!/usr/bin/env python3
"""
Verifier for dataset_completeness_monitoring task.

Scoring (100 points total):
- Visualization saved after task start (25 pts) [MANDATORY]
- Visualization name contains 'Reporting' or 'Completeness' (10 pts)
- Visualization uses 'Reporting Rate' data dimension (15 pts)
- Export file exists in Downloads (20 pts)
- Summary text file exists (15 pts)
- Summary text has substantive content (>200 chars) (10 pts)
- Summary mentions threshold/percent (5 pts)

Pass threshold: 60 points
Mandatory: Visualization saved
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_dataset_completeness_monitoring(traj, env_info, task_info):
    """Verify reporting rates visualization, export, and analysis summary."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/completeness_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    # Extract data sections
    viz_data = result.get('visualization_analysis', {})
    dl_data = result.get('downloads_analysis', {})
    summary_data = result.get('summary_file', {})

    # Criterion 1: Visualization Created (MANDATORY)
    new_viz_count = viz_data.get('new_viz_count', 0)
    if new_viz_count < 1:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new visualization saved in DHIS2. You must save the visualization as a Favorite."
        }
    
    score += 25
    feedback_parts.append(f"Visualization saved (+25)")

    # Criterion 2: Name Check
    completeness_viz_count = viz_data.get('completeness_viz_count', 0)
    if completeness_viz_count > 0:
        score += 10
        feedback_parts.append("Visualization name correct (+10)")
    else:
        feedback_parts.append("Visualization name missing keywords 'Reporting' or 'Completeness'")

    # Criterion 3: Uses Reporting Rate Dimension
    # This is the key technical check for this task
    if viz_data.get('any_uses_reporting_rate', False):
        score += 15
        feedback_parts.append("Correctly used 'Reporting rates' dimension (+15)")
    else:
        feedback_parts.append("Did not use 'Reporting rates' dimension (check Data settings)")

    # Criterion 4: Export File
    valid_exports = dl_data.get('valid_export_count', 0)
    if valid_exports > 0:
        score += 20
        feedback_parts.append(f"Data exported to Downloads (+20)")
    else:
        feedback_parts.append("No exported file found in Downloads")

    # Criterion 5, 6, 7: Summary File
    summary_exists = summary_data.get('exists', False)
    if summary_exists:
        score += 15
        feedback_parts.append("Summary file created (+15)")
        
        length = summary_data.get('length', 0)
        has_district = summary_data.get('has_district', False)
        
        if length > 200 and has_district:
            score += 10
            feedback_parts.append("Summary content substantive (+10)")
        else:
            feedback_parts.append("Summary too short or missing district names")
            
        if summary_data.get('has_percent_or_rate', False):
            score += 5
            feedback_parts.append("Summary mentions rates/percentages (+5)")
    else:
        feedback_parts.append("Summary file /home/ga/Desktop/completeness_summary.txt missing")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }