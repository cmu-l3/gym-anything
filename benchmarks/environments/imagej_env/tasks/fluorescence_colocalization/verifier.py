#!/usr/bin/env python3
"""Verifier for fluorescence_colocalization task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_fluorescence_colocalization(traj, env_info, task_info):
    """
    Verify fluorescence colocalization analysis task.

    Scoring (100 points total):
    - Criterion 1: Result file exists with content, created after task start (25 pts)
    - Criterion 2: Red channel measurements present (area/intensity) (25 pts)
    - Criterion 3: Green channel measurements present (area/intensity) (25 pts)
    - Criterion 4: Colocalization metric present (Pearson/Manders/overlap) (25 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/fluorescence_colocalization_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_file.name)
            except Exception:
                pass

        score = 0
        feedback_parts = []
        subscores = {}

        # ----------------------------------------------------------------
        # Criterion 1: File exists with content and was created after task start
        # ----------------------------------------------------------------
        file_exists = result.get('file_exists', False)
        file_size = result.get('file_size_bytes', 0)
        file_time = result.get('file_modified_time', 0)
        task_start = result.get('task_start_timestamp', 0)
        row_count = result.get('row_count', 0)

        if file_exists and file_size > 30:
            if task_start > 0 and file_time < task_start:
                feedback_parts.append("FAIL: Result file predates task start (pre-existing file)")
                subscores["file_created"] = False
            else:
                score += 25
                subscores["file_created"] = True
                feedback_parts.append(f"Result file created ({file_size} bytes, {row_count} rows)")
        else:
            subscores["file_created"] = False
            if not file_exists:
                feedback_parts.append("FAIL: ~/ImageJ_Data/results/colocalization_results.csv not found")
            else:
                feedback_parts.append(f"FAIL: File is too small ({file_size} bytes) to contain real measurements")

        # ----------------------------------------------------------------
        # Criterion 2: Red channel data present
        # ----------------------------------------------------------------
        if result.get('has_red_data', False) and (
            result.get('has_area_data', False) or result.get('has_intensity_data', False)
        ):
            score += 25
            subscores["red_channel"] = True
            feedback_parts.append("Red channel measurements found")
        else:
            subscores["red_channel"] = False
            feedback_parts.append("FAIL: No red channel data found (look for 'red', 'channel1', 'ch1', 'rhodamine')")

        # ----------------------------------------------------------------
        # Criterion 3: Green channel data present
        # ----------------------------------------------------------------
        if result.get('has_green_data', False) and (
            result.get('has_area_data', False) or result.get('has_intensity_data', False)
        ):
            score += 25
            subscores["green_channel"] = True
            feedback_parts.append("Green channel measurements found")
        else:
            subscores["green_channel"] = False
            feedback_parts.append("FAIL: No green channel data found (look for 'green', 'channel2', 'ch2', 'fitc')")

        # ----------------------------------------------------------------
        # Criterion 4: Colocalization metric present
        # ----------------------------------------------------------------
        has_coloc = result.get('has_colocalization_metric', False)
        coloc_vals = result.get('colocalization_values', [])

        # Validate that any detected colocalization values are in [0, 1]
        valid_coloc_vals = [v for v in coloc_vals if 0.0 <= v <= 1.0]

        if has_coloc:
            score += 25
            subscores["colocalization_metric"] = True
            if valid_coloc_vals:
                feedback_parts.append(
                    f"Colocalization metric found (value range: "
                    f"{min(valid_coloc_vals):.3f}–{max(valid_coloc_vals):.3f})"
                )
            else:
                feedback_parts.append("Colocalization metric keyword found")
        else:
            subscores["colocalization_metric"] = False
            feedback_parts.append(
                "FAIL: No colocalization metric found. Expected Pearson r, Manders M1/M2, "
                "overlap coefficient, or IoU"
            )

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
            "details": {
                "file_exists": result.get('file_exists'),
                "file_size_bytes": result.get('file_size_bytes'),
                "row_count": result.get('row_count'),
                "columns": result.get('columns', []),
                "has_red_data": result.get('has_red_data'),
                "has_green_data": result.get('has_green_data'),
                "has_colocalization_metric": result.get('has_colocalization_metric'),
                "colocalization_values": result.get('colocalization_values', []),
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found — export script likely failed or result file was not created"
        }
    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
