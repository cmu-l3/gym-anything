#!/usr/bin/env python3
"""
Verifier for tb_programme_data_export task.

Scoring (100 points total):
- At least 1 new file in Downloads after task start (25 pts) [MANDATORY]
- At least 2 new files in Downloads after task start (20 pts)
- At least 1 new visualization created in DHIS2 after task start (25 pts)
- Visualization has TB-related name (15 pts)
- At least 1 CSV/XLSX file in Downloads (15 pts)

Pass threshold: 60 points
Mandatory: At least 1 download present
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_tb_programme_data_export(traj, env_info, task_info):
    """Verify TB programme data was exported and visualization created."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/tb_programme_data_export_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        new_dl_count = int(result.get('new_downloads_count', 0))
        csv_xlsx_count = int(result.get('csv_xlsx_new_count', 0))
        new_viz_count = int(result.get('new_visualization_count', 0))
        tb_viz_count = int(result.get('tb_related_visualization_count', 0))

        # Criterion 1: At least 1 file downloaded (MANDATORY for pass)
        if new_dl_count < 1:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No files found in Downloads folder after task start. Agent must export TB working list and/or visualization data.",
                "subscores": {}
            }

        score += 25
        subscores["has_download"] = True
        feedback_parts.append(f"At least 1 file downloaded ({new_dl_count} total) (+25)")

        # Criterion 2: At least 2 files downloaded
        if new_dl_count >= 2:
            score += 20
            subscores["has_two_downloads"] = True
            feedback_parts.append(f"2+ files downloaded ({new_dl_count}) (+20)")
        else:
            subscores["has_two_downloads"] = False
            feedback_parts.append(f"Only {new_dl_count} file(s) downloaded — need both tracker export and visualization export")

        # Criterion 3: At least 1 CSV/XLSX file
        if csv_xlsx_count >= 1:
            score += 15
            subscores["has_csv_xlsx"] = True
            feedback_parts.append(f"{csv_xlsx_count} CSV/XLSX file(s) downloaded (+15)")
        else:
            subscores["has_csv_xlsx"] = False
            feedback_parts.append("No CSV/XLSX files found in Downloads")

        # Criterion 4: At least 1 new visualization created in DHIS2
        if new_viz_count >= 1:
            score += 25
            subscores["visualization_created"] = True
            feedback_parts.append(f"Visualization created in DHIS2 (+25)")
        else:
            subscores["visualization_created"] = False
            feedback_parts.append("No new visualizations found in DHIS2 (not saved as favorite)")

        # Criterion 5: Visualization has TB-related name
        if tb_viz_count >= 1:
            score += 15
            subscores["tb_viz_named"] = True
            feedback_parts.append("TB-related visualization name found (+15)")
        else:
            subscores["tb_viz_named"] = False
            if new_viz_count >= 1:
                feedback_parts.append("Visualization created but name doesn't mention TB/tuberculosis/notifications")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
