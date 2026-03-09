#!/usr/bin/env python3
"""Verifier for mitosis_timepoint_analysis task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_mitosis_timepoint_analysis(traj, env_info, task_info):
    """
    Verify mitosis time-lapse quantification task.

    Scoring (100 points total):
    - Criterion 1: Result file exists with content, created after task start (20 pts)
    - Criterion 2: At least 4 distinct time frames measured (25 pts)
    - Criterion 3: Area and/or count measurements per frame with positive values (25 pts)
    - Criterion 4: Measurements vary across time frames (not all identical) (20 pts)
    - Criterion 5: Frame identifier column present (10 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/mitosis_timepoint_analysis_result.json", temp_file.name)
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
        # Criterion 1: File exists with content, created after task start
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
            feedback_parts.append("FAIL: ~/ImageJ_Data/results/mitosis_timeseries.csv not found or empty")

        # ----------------------------------------------------------------
        # Criterion 2: At least 4 distinct time frames measured
        # ----------------------------------------------------------------
        distinct_frames = result.get('distinct_frame_count', 0)
        row_count = result.get('row_count', 0)

        # If no explicit frame column, use row count as proxy
        effective_frames = max(distinct_frames, max(0, row_count - 1))  # -1 for header

        if effective_frames >= 4:
            score += 25
            subscores["multiple_timeframes"] = True
            feedback_parts.append(f"Multiple time frames measured: {effective_frames} frames")
        elif effective_frames >= 2:
            # Partial credit not in spec — just fail
            subscores["multiple_timeframes"] = False
            feedback_parts.append(
                f"FAIL: Only {effective_frames} frames measured. "
                "Need at least 4 out of the 5 available time frames."
            )
        else:
            subscores["multiple_timeframes"] = False
            feedback_parts.append(
                f"FAIL: Only {effective_frames} frame(s) detected. "
                "The Mitosis 5D stack has 5 time frames — measure at least 4."
            )

        # ----------------------------------------------------------------
        # Criterion 3: Measurements per frame (area or count)
        # ----------------------------------------------------------------
        has_area = result.get('has_area_data', False)
        has_count = result.get('has_count_data', False)
        area_vals = result.get('area_values', [])
        count_vals = result.get('count_values', [])

        positive_areas = [v for v in area_vals if v > 0]
        positive_counts = [v for v in count_vals if v >= 0]

        if (has_area or has_count) and (len(positive_areas) >= 1 or len(positive_counts) >= 1):
            score += 25
            subscores["measurements_present"] = True
            parts = []
            if positive_areas:
                parts.append(f"area: {min(positive_areas):.0f}–{max(positive_areas):.0f} px²")
            if positive_counts:
                parts.append(f"count: {min(positive_counts):.0f}–{max(positive_counts):.0f}")
            feedback_parts.append(f"Per-frame measurements found ({', '.join(parts)})")
        else:
            subscores["measurements_present"] = False
            feedback_parts.append(
                "FAIL: No per-frame area or cell count measurements found. "
                "Apply thresholding and Analyze Particles at each time frame."
            )

        # ----------------------------------------------------------------
        # Criterion 4: Temporal variation (measurements are not all identical)
        # ----------------------------------------------------------------
        area_variation = result.get('area_variation', False)
        count_variation = result.get('count_variation', False)

        # Also compute variation from the values directly
        combined_vals = positive_areas if positive_areas else positive_counts
        has_variation = False
        if len(combined_vals) >= 2:
            has_variation = max(combined_vals) != min(combined_vals)
        else:
            has_variation = area_variation or count_variation

        if has_variation:
            score += 20
            subscores["temporal_variation"] = True
            feedback_parts.append("Temporal variation detected across time frames")
        else:
            subscores["temporal_variation"] = False
            feedback_parts.append(
                "FAIL: All measurement values are identical across frames — "
                "this suggests the same frame was measured repeatedly. "
                "Navigate to different time points using the T slider."
            )

        # ----------------------------------------------------------------
        # Criterion 5: Frame identifier column present
        # ----------------------------------------------------------------
        has_frame_col = result.get('has_frame_column', False)
        frame_vals = result.get('frame_values', [])

        if has_frame_col or len(set(frame_vals)) >= 2:
            score += 10
            subscores["frame_column"] = True
            feedback_parts.append("Time frame identifier column found")
        else:
            subscores["frame_column"] = False
            feedback_parts.append(
                "Note: No explicit frame index column detected. "
                "Consider adding a 'Frame' or 'Time' column for clarity."
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
                "distinct_frame_count": result.get('distinct_frame_count'),
                "area_values_sample": result.get('area_values', [])[:5],
                "count_values_sample": result.get('count_values', [])[:5],
                "area_variation": result.get('area_variation'),
                "count_variation": result.get('count_variation'),
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
