#!/usr/bin/env python3
"""
Verifier for mitotic_spindle_dynamics task.

This is a stub verifier for framework compatibility.
Primary verification is handled externally via VLM checklist verifier.

Scoring (100 points total):
- Criterion 1: All 5 output files exist and post-date task start (10 pts)
- Criterion 2: Both max projections have correct dimensions (~171x196, multi-frame) (15 pts)
- Criterion 3: ROI set is valid ZIP with 2-15 ROIs (20 pts)
- Criterion 4: CSV has correct structure (Mean column, multiple rows, positive values) (25 pts)
- Criterion 5: CSV values show temporal variation across timepoints (15 pts)
- Criterion 6: Montage dimensions indicate single-row multi-frame layout (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_mitotic_spindle_dynamics(traj, env_info, task_info):
    """Verify mitotic spindle dynamics analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/mitotic_spindle_dynamics_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        files = result.get("files", {})
        task_start = result.get("task_start_timestamp", 0)

        # --- Criterion 1: File existence and timestamps (10 pts) ---
        all_exist = True
        for key, finfo in files.items():
            if not finfo.get("exists"):
                all_exist = False
                feedback_parts.append(f"Missing: {key}")
            elif task_start > 0 and not finfo.get("valid_time", False):
                feedback_parts.append(f"Timestamp fail: {key} predates task start")

        if all_exist:
            score += 10
            feedback_parts.append("All 5 output files found")
        else:
            found = sum(1 for f in files.values() if f.get("exists"))
            feedback_parts.append(f"Only {found}/5 files found")

        # --- Criterion 2: Max projection dimensions (15 pts) ---
        proj_score = 0
        for proj_key in ["dna_projection", "tubulin_projection"]:
            finfo = files.get(proj_key, {})
            if finfo.get("exists"):
                w = finfo.get("width", 0)
                h = finfo.get("height", 0)
                n = finfo.get("n_frames", 0)
                # Expect ~171x196, with multiple frames (time series)
                if 100 < w < 300 and 100 < h < 300 and n > 1:
                    proj_score += 7.5
                    feedback_parts.append(f"{proj_key}: {w}x{h}, {n} frames")
                elif w > 0 and h > 0:
                    proj_score += 3
                    feedback_parts.append(f"{proj_key}: {w}x{h}, {n} frames (unexpected dims)")
        score += proj_score

        # --- Criterion 3: ROI set validity (20 pts) ---
        roi_info = files.get("roi_set", {})
        if roi_info.get("exists"):
            roi_count = roi_info.get("roi_count", 0)
            if 2 <= roi_count <= 15:
                score += 20
                feedback_parts.append(f"ROI set valid: {roi_count} ROIs")
            elif roi_count > 0:
                score += 10
                feedback_parts.append(f"ROI set has {roi_count} ROIs (outside 2-15 range)")
            else:
                feedback_parts.append("ROI ZIP exists but contains no .roi files")
        else:
            feedback_parts.append("nuclear_rois.zip not found")

        # --- Criterion 4: CSV structure (25 pts) ---
        csv_info = files.get("dynamics_csv", {})
        if csv_info.get("exists"):
            has_mean = csv_info.get("has_mean_column", False)
            row_count = csv_info.get("row_count", 0)
            mean_min = csv_info.get("mean_min")
            mean_max = csv_info.get("mean_max")

            csv_pts = 0
            if has_mean:
                csv_pts += 10
                feedback_parts.append("CSV has Mean column")
            else:
                feedback_parts.append("CSV missing Mean column")

            if row_count > 10:
                csv_pts += 10
                feedback_parts.append(f"CSV has {row_count} data rows")
            elif row_count > 0:
                csv_pts += 5
                feedback_parts.append(f"CSV has only {row_count} rows (expected N_ROIs * 51)")

            if mean_min is not None and mean_min > 0:
                csv_pts += 5
                feedback_parts.append(f"Mean values: {mean_min:.1f} - {mean_max:.1f}")

            score += csv_pts
        else:
            feedback_parts.append("spindle_dynamics.csv not found")

        # --- Criterion 5: Temporal variation in CSV (15 pts) ---
        if csv_info.get("has_variation", False):
            score += 15
            feedback_parts.append("Temporal variation detected in measurements")
        elif csv_info.get("exists"):
            feedback_parts.append("No temporal variation — may have measured same slice repeatedly")

        # --- Criterion 6: Montage dimensions (15 pts) ---
        mont_info = files.get("montage", {})
        if mont_info.get("exists"):
            w = mont_info.get("width", 0)
            h = mont_info.get("height", 0)
            # Single-row montage of 6 frames: width should be ~6x individual frame width
            # Individual frame is ~171px wide, so montage ~1026px wide
            if w > 0 and h > 0:
                ratio = w / h if h > 0 else 0
                if ratio > 2:  # Width clearly > height (single row of multiple frames)
                    score += 15
                    feedback_parts.append(f"Montage dimensions OK ({w}x{h}, ratio={ratio:.1f})")
                else:
                    score += 5
                    feedback_parts.append(f"Montage aspect ratio unexpected ({w}x{h})")
        else:
            feedback_parts.append("tubulin_montage.tif not found")

        passed = score >= 60

        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " | ".join(feedback_parts) or "No criteria met"
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
