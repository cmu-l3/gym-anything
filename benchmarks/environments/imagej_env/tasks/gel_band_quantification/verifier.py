#!/usr/bin/env python3
"""Verifier for gel_band_quantification task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_gel_band_quantification(traj, env_info, task_info):
    """
    Verify gel electrophoresis band quantification task.

    Scoring (100 points total):
    - Criterion 1: Result file exists with content, created after task start (20 pts)
    - Criterion 2: Multiple band measurements (>= 3 rows) (25 pts)
    - Criterion 3: Intensity/density values present and positive (25 pts)
    - Criterion 4: Relative/normalized intensity values present (15 pts)
    - Criterion 5: Multiple lanes evident (>= 2 distinct lanes or lane-equivalent groupings) (15 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/gel_band_quantification_result.json", temp_file.name)
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
        # Criterion 1: File exists, non-empty, created after task start
        # ----------------------------------------------------------------
        file_exists = result.get('file_exists', False)
        file_size = result.get('file_size_bytes', 0)
        file_time = result.get('file_modified_time', 0)
        task_start = result.get('task_start_timestamp', 0)

        if file_exists and file_size > 30:
            if task_start > 0 and file_time < task_start:
                feedback_parts.append("FAIL: File predates task start")
                subscores["file_created"] = False
            else:
                score += 20
                subscores["file_created"] = True
                feedback_parts.append(f"Result file created ({file_size} bytes)")
        else:
            subscores["file_created"] = False
            feedback_parts.append("FAIL: ~/ImageJ_Data/results/gel_quantification.csv not found or empty")

        # ----------------------------------------------------------------
        # Criterion 2: Multiple band measurements (>= 3 rows)
        # ----------------------------------------------------------------
        row_count = result.get('row_count', 0)
        if row_count >= 3:
            score += 25
            subscores["multiple_bands"] = True
            feedback_parts.append(f"Multiple band measurements: {row_count} rows")
        else:
            subscores["multiple_bands"] = False
            feedback_parts.append(
                f"FAIL: Only {row_count} rows — need at least 3 band measurements. "
                "Each lane should have multiple bands detected."
            )

        # ----------------------------------------------------------------
        # Criterion 3: Intensity values present and positive
        # ----------------------------------------------------------------
        has_intensity = result.get('has_intensity_data', False)
        intensity_vals = result.get('intensity_values', [])
        positive_intensities = [v for v in intensity_vals if v > 0]

        if has_intensity and len(positive_intensities) >= 1:
            score += 25
            subscores["intensity_values"] = True
            feedback_parts.append(
                f"Intensity measurements found "
                f"(range: {min(positive_intensities):.1f}–{max(positive_intensities):.1f})"
            )
        else:
            subscores["intensity_values"] = False
            feedback_parts.append(
                "FAIL: No positive intensity/density values found. "
                "Expected integrated optical density or band area measurements."
            )

        # ----------------------------------------------------------------
        # Criterion 4: Relative/normalized intensity values present
        # ----------------------------------------------------------------
        has_relative = result.get('has_relative_intensity', False)
        relative_vals = result.get('relative_values', [])

        # Also accept if percent-style values (0–100) appear in any column
        all_intensity_vals = positive_intensities
        percent_candidates = [v for v in all_intensity_vals if 0 < v <= 100]

        if has_relative or (len(percent_candidates) >= 2 and max(percent_candidates) <= 100):
            score += 15
            subscores["relative_intensity"] = True
            feedback_parts.append("Relative intensity values found")
        else:
            subscores["relative_intensity"] = False
            feedback_parts.append(
                "FAIL: No relative intensity found. Each band should be expressed as "
                "% of strongest band in its lane."
            )

        # ----------------------------------------------------------------
        # Criterion 5: Multiple lanes evident
        # ----------------------------------------------------------------
        distinct_lanes = result.get('distinct_lanes', 0)
        has_lane_data = result.get('has_lane_data', False)

        if distinct_lanes >= 2 or (has_lane_data and row_count >= 4):
            score += 15
            subscores["multiple_lanes"] = True
            if distinct_lanes >= 2:
                feedback_parts.append(f"Multiple lanes identified: {distinct_lanes} lanes")
            else:
                feedback_parts.append("Multiple lanes evident from data structure")
        else:
            subscores["multiple_lanes"] = False
            feedback_parts.append(
                "FAIL: Could not identify ≥2 distinct lanes. "
                "Gel analysis should define each lane separately."
            )

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
            "details": {
                "file_exists": result.get('file_exists'),
                "row_count": result.get('row_count'),
                "columns": result.get('columns', []),
                "distinct_lanes": result.get('distinct_lanes'),
                "has_intensity": result.get('has_intensity_data'),
                "has_relative": result.get('has_relative_intensity'),
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found — export script likely failed"
        }
    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
