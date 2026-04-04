#!/usr/bin/env python3
"""
Verifier for anc_pivot_table_analysis task.

Scoring (100 points total):
- At least 1 new visualization created in DHIS2 after task start (25 pts) [MANDATORY]
- Visualization has ANC-related name (15 pts)
- Export file present in Downloads after task start (25 pts)
- Analysis text file /home/ga/Desktop/anc_analysis_notes.txt exists (20 pts)
- Text file has substantive content with district name and ANC keywords (15 pts)

Pass threshold: 60 points
Mandatory: Visualization created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_anc_pivot_table_analysis(traj, env_info, task_info):
    """Verify ANC pivot table was created, exported, and analyzed."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/anc_pivot_table_analysis_result.json", temp_path)
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

        new_viz_count = int(result.get('new_visualization_count', 0))
        anc_viz_count = int(result.get('anc_related_visualization_count', 0))
        new_dl_count = int(result.get('new_downloads_count', 0))
        csv_xlsx_count = int(result.get('csv_xlsx_download_count', 0))
        notes_exists = result.get('notes_file_exists', False)
        if isinstance(notes_exists, str):
            notes_exists = notes_exists.lower() == 'true'
        notes_length = int(result.get('notes_file_length', 0))
        notes_has_district = result.get('notes_has_district_name', False)
        if isinstance(notes_has_district, str):
            notes_has_district = notes_has_district.lower() == 'true'
        notes_has_anc = result.get('notes_has_anc_keywords', False)
        if isinstance(notes_has_anc, str):
            notes_has_anc = notes_has_anc.lower() == 'true'

        # Criterion 1: Visualization created in DHIS2 (MANDATORY)
        if new_viz_count < 1:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new visualization saved in DHIS2. Agent must create and save an ANC pivot table as a favorite.",
                "subscores": {}
            }

        score += 25
        subscores["visualization_created"] = True
        feedback_parts.append(f"New visualization created in DHIS2 ({new_viz_count} total) (+25)")

        # Criterion 2: Visualization has ANC-related name
        if anc_viz_count >= 1:
            score += 15
            subscores["anc_viz_name"] = True
            feedback_parts.append("Visualization has ANC-related name (+15)")
        else:
            subscores["anc_viz_name"] = False
            feedback_parts.append("Visualization doesn't have ANC-related name (e.g., missing 'ANC', 'antenatal', 'coverage')")

        # Criterion 3: Export file in Downloads
        if new_dl_count >= 1:
            score += 25
            subscores["export_file"] = True
            feedback_parts.append(f"Export file(s) found in Downloads ({new_dl_count}) (+25)")
        else:
            subscores["export_file"] = False
            feedback_parts.append("No export file found in Downloads folder")

        # Criterion 4: Analysis text file exists
        if notes_exists:
            score += 20
            subscores["notes_file"] = True
            feedback_parts.append(f"Analysis notes file created ({notes_length} bytes) (+20)")
        else:
            subscores["notes_file"] = False
            feedback_parts.append("Analysis notes file /home/ga/Desktop/anc_analysis_notes.txt not found")

        # Criterion 5: Text file has substantive analytical content
        if notes_exists and notes_length > 100 and (notes_has_district or notes_has_anc):
            score += 15
            subscores["notes_content"] = True
            feedback_parts.append("Notes contain substantive ANC analysis with district references (+15)")
        elif notes_exists:
            subscores["notes_content"] = False
            feedback_parts.append(f"Notes file exists but lacks detail (length={notes_length}, has_district={notes_has_district}, has_anc={notes_has_anc})")
        else:
            subscores["notes_content"] = False

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
