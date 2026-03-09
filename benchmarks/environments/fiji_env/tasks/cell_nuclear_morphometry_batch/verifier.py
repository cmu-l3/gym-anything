#!/usr/bin/env python3
"""
Verifier for cell_nuclear_morphometry_batch task.

Scoring (100 points total, pass threshold = 60):

  Criterion 1: CSV created after task start                — 15 pts
  Criterion 2: CSV has required morphometry columns        — 15 pts
  Criterion 3: >= 50 total nuclei (batch processing)      — 20 pts
               (10 pts if >= 20 but < 50)
  Criterion 4: Circularity and solidity all valid (0, 1]  — 15 pts
  Criterion 5: Area values all positive                   — 10 pts
  Criterion 6: Batch summary with QC flags                — 15 pts
               (10 pts if exists but no PASS/FAIL flags)
  Criterion 7: QC overlay image created (> 5 KB)          — 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_cell_nuclear_morphometry_batch(traj, env_info, task_info):
    """
    Verify the batch nuclear morphometry task output.

    Reads /tmp/morphometry_result.json written by export_result.sh via copy_from_env,
    then applies scoring criteria.
    """
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')

    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available in env_info"
        }

    # Copy result JSON from the environment VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/morphometry_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read morphometry export result: {e}",
            "subscores": {}
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: CSV created after task start (15 pts)
    try:
        csv_exists = result.get('csv_exists', False)
        csv_modified = result.get('csv_modified_after_start', False)
        if csv_exists and csv_modified:
            score += 15
            feedback_parts.append("CSV created after task start (15/15)")
            subscores['csv_created'] = True
        elif csv_exists and not csv_modified:
            score += 5
            feedback_parts.append("CSV exists but was not created during this task (5/15)")
            subscores['csv_created'] = False
        else:
            feedback_parts.append("nuclear_measurements.csv not created (0/15)")
            subscores['csv_created'] = False
    except Exception as e:
        logger.warning(f"Criterion 1 check failed: {e}")
        subscores['csv_created'] = False

    # GATE: if CSV does not exist at all, skip remaining CSV-dependent criteria
    if not result.get('csv_exists', False):
        feedback_parts.append("GATE: CSV missing - skipping morphometry checks")
        # Still check summary and overlay
        _check_summary(result, score, feedback_parts, subscores)
        _check_overlay(result, score, feedback_parts, subscores)
        # Recompute score from subscores
        score = sum([
            15 if subscores.get('csv_created') else 0,
            0,   # required_columns
            0,   # nuclei_count
            0,   # value_validity
            0,   # area_positive
            subscores.get('_summary_score', 0),
            subscores.get('_overlay_score', 0),
        ])
        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 2: Required morphometry columns (15 pts)
    try:
        has_required = result.get('has_required_columns', False)
        if has_required:
            score += 15
            feedback_parts.append("Required morphometry columns present (15/15)")
            subscores['required_columns'] = True
        else:
            header_cols = result.get('header_cols', [])
            feedback_parts.append(
                f"Missing required columns (area/circularity/solidity). "
                f"Found: {', '.join(header_cols[:8])} (0/15)"
            )
            subscores['required_columns'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")
        subscores['required_columns'] = False

    # Criterion 3: Total nuclei count (20 pts full, 10 pts partial)
    try:
        total_nuclei = int(result.get('total_nuclei', 0))
        n_images = int(result.get('n_images_processed', 0))
        if total_nuclei >= 50:
            score += 20
            feedback_parts.append(
                f"Batch complete: {total_nuclei} nuclei from {n_images} images (20/20)"
            )
            subscores['nuclei_count'] = True
        elif total_nuclei >= 20:
            score += 10
            feedback_parts.append(
                f"Partial batch: {total_nuclei} nuclei from {n_images} images (10/20) "
                f"- need >= 50 for full credit"
            )
            subscores['nuclei_count'] = 'partial'
        elif total_nuclei > 0:
            score += 3
            feedback_parts.append(
                f"Only {total_nuclei} nuclei detected from {n_images} images (3/20)"
            )
            subscores['nuclei_count'] = False
        else:
            feedback_parts.append("No nuclei detected in CSV data rows (0/20)")
            subscores['nuclei_count'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")
        subscores['nuclei_count'] = False

    # Criterion 4: Circularity and solidity validity (15 pts)
    try:
        circ_valid = result.get('circularity_all_valid', False)
        solid_valid = result.get('solidity_all_valid', False)
        circ_min = result.get('circularity_min', None)
        circ_max = result.get('circularity_max', None)
        solid_min = result.get('solidity_min', None)
        solid_max = result.get('solidity_max', None)

        if circ_valid and solid_valid:
            score += 15
            feedback_parts.append(
                f"Valid circularity [{circ_min:.3f}-{circ_max:.3f}] "
                f"and solidity [{solid_min:.3f}-{solid_max:.3f}] (15/15)"
            )
            subscores['value_validity'] = True
        elif circ_valid or solid_valid:
            score += 7
            which = "circularity" if circ_valid else "solidity"
            feedback_parts.append(
                f"Only {which} values valid; both required (7/15)"
            )
            subscores['value_validity'] = 'partial'
        else:
            issues = []
            if circ_min is not None and (circ_min <= 0 or circ_max > 1.0):
                issues.append(f"circularity range [{circ_min:.3f}-{circ_max:.3f}] out of (0,1]")
            if solid_min is not None and (solid_min <= 0 or solid_max > 1.0):
                issues.append(f"solidity range [{solid_min:.3f}-{solid_max:.3f}] out of (0,1]")
            if not issues:
                issues.append("no circularity/solidity columns found")
            feedback_parts.append(
                f"Invalid or missing morphometry values: {'; '.join(issues)} (0/15)"
            )
            subscores['value_validity'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")
        subscores['value_validity'] = False

    # Criterion 5: Area values all positive (10 pts)
    try:
        area_positive = result.get('area_all_positive', False)
        area_min = result.get('area_min', None)
        if area_positive:
            score += 10
            feedback_parts.append(
                f"All area values positive (min={area_min:.1f} px) (10/10)"
            )
            subscores['area_positive'] = True
        else:
            if area_min is not None:
                feedback_parts.append(
                    f"Area values not all positive (min={area_min}) (0/10)"
                )
            else:
                feedback_parts.append("No area values found or column missing (0/10)")
            subscores['area_positive'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")
        subscores['area_positive'] = False

    # Criterion 6: Batch summary with QC flags (15 pts full, 10 pts partial)
    summary_score = 0
    try:
        summary_exists = result.get('summary_exists', False)
        summary_modified = result.get('summary_modified_after_start', False)
        summary_qc_flags = result.get('summary_has_qc_flags', False)
        summary_size = int(result.get('summary_size_bytes', 0))
        summary_lines = int(result.get('summary_line_count', 0))

        if summary_exists and summary_modified and summary_qc_flags:
            summary_score = 15
            score += summary_score
            feedback_parts.append(
                f"Batch summary with QC flags present ({summary_lines} lines, "
                f"{summary_size} bytes) (15/15)"
            )
            subscores['batch_summary'] = True
        elif summary_exists and summary_modified:
            summary_score = 10
            score += summary_score
            feedback_parts.append(
                f"Batch summary created but missing PASS/FAIL flags (10/15)"
            )
            subscores['batch_summary'] = 'partial'
        elif summary_exists and not summary_modified:
            summary_score = 3
            score += summary_score
            feedback_parts.append(
                "batch_summary.txt exists but not created during this task (3/15)"
            )
            subscores['batch_summary'] = False
        else:
            feedback_parts.append("batch_summary.txt not created (0/15)")
            subscores['batch_summary'] = False
        subscores['_summary_score'] = summary_score
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")
        subscores['batch_summary'] = False
        subscores['_summary_score'] = 0

    # Criterion 7: QC overlay image (10 pts)
    overlay_score = 0
    try:
        overlay_exists = result.get('overlay_exists', False)
        overlay_modified = result.get('overlay_modified_after_start', False)
        overlay_size = int(result.get('overlay_size_bytes', 0))

        if overlay_exists and overlay_modified and overlay_size > 5000:
            overlay_score = 10
            score += overlay_score
            feedback_parts.append(
                f"QC overlay image created ({overlay_size} bytes) (10/10)"
            )
            subscores['qc_overlay'] = True
        elif overlay_exists and overlay_modified and overlay_size > 0:
            overlay_score = 5
            score += overlay_score
            feedback_parts.append(
                f"QC overlay exists but small ({overlay_size} bytes < 5 KB) (5/10)"
            )
            subscores['qc_overlay'] = 'partial'
        elif overlay_exists and not overlay_modified:
            overlay_score = 2
            score += overlay_score
            feedback_parts.append(
                "qc_overlay.png exists but not created during this task (2/10)"
            )
            subscores['qc_overlay'] = False
        else:
            feedback_parts.append("qc_overlay.png not created (0/10)")
            subscores['qc_overlay'] = False
        subscores['_overlay_score'] = overlay_score
    except Exception as e:
        logger.warning(f"Criterion 7 check failed: {e}")
        subscores['qc_overlay'] = False
        subscores['_overlay_score'] = 0

    passed = score >= 60
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "total_nuclei": result.get('total_nuclei', 0),
            "n_images_processed": result.get('n_images_processed', 0),
            "csv_exists": result.get('csv_exists', False),
            "csv_modified_after_start": result.get('csv_modified_after_start', False),
            "circularity_range": [
                result.get('circularity_min'), result.get('circularity_max')
            ],
            "solidity_range": [
                result.get('solidity_min'), result.get('solidity_max')
            ],
            "summary_exists": result.get('summary_exists', False),
            "overlay_size_bytes": result.get('overlay_size_bytes', 0),
        }
    }


def _check_summary(result, score, feedback_parts, subscores):
    """Helper to check summary file (called in gate-fail path)."""
    summary_exists = result.get('summary_exists', False)
    summary_modified = result.get('summary_modified_after_start', False)
    summary_qc_flags = result.get('summary_has_qc_flags', False)
    if summary_exists and summary_modified and summary_qc_flags:
        subscores['_summary_score'] = 15
    elif summary_exists and summary_modified:
        subscores['_summary_score'] = 10
    else:
        subscores['_summary_score'] = 0


def _check_overlay(result, score, feedback_parts, subscores):
    """Helper to check overlay file (called in gate-fail path)."""
    overlay_exists = result.get('overlay_exists', False)
    overlay_modified = result.get('overlay_modified_after_start', False)
    overlay_size = int(result.get('overlay_size_bytes', 0))
    if overlay_exists and overlay_modified and overlay_size > 5000:
        subscores['_overlay_score'] = 10
    elif overlay_exists and overlay_modified:
        subscores['_overlay_score'] = 5
    else:
        subscores['_overlay_score'] = 0
