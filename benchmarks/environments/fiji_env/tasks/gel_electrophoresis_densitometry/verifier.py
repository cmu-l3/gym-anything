#!/usr/bin/env python3
"""
Verifier for gel_electrophoresis_densitometry task.

Scoring (100 points total, pass >= 60):
  Criterion 1: CSV file created after task start                      — 15 pts
  Criterion 2: CSV has required columns (lane_id, raw_intensity,      — 15 pts
               normalized_intensity)
  Criterion 3: >=3 lanes quantified (10 pts partial if >=2 lanes)     — 20 pts
  Criterion 4: All raw intensities > 0                                — 15 pts
  Criterion 5: Normalized intensities show variation (not all same)   — 15 pts
  Criterion 6: Lane profiles image created (PNG, >5KB, after start)   — 10 pts
  Criterion 7: Densitometry report created with required keywords      — 10 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_gel_electrophoresis_densitometry(traj, env_info, task_info):
    """
    Verify gel electrophoresis densitometry analysis task.

    Reads /tmp/gel_result.json exported by export_result.sh and applies
    a 7-criterion scoring rubric totaling 100 points.

    Args:
        traj: Trajectory object (list of steps taken by the agent)
        env_info: Dict containing environment helpers including copy_from_env
        task_info: Dict with task metadata

    Returns:
        Dict with keys: passed (bool), score (int), feedback (str), subscores (dict)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        logger.error("No copy_from_env function available in env_info")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verifier error: copy_from_env not available in env_info",
            "subscores": {}
        }

    # Retrieve the exported result JSON from the environment
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/gel_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        logger.warning(f"Could not read gel_result.json: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result JSON: {e}. "
                        "The post_task export script may not have run correctly.",
            "subscores": {}
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # -------------------------------------------------------------------------
    # Criterion 1: CSV file created after task start (15 pts)
    # -------------------------------------------------------------------------
    try:
        csv_exists = result.get('csv_exists', False)
        csv_modified_after_start = result.get('csv_modified_after_start', False)

        if csv_exists and csv_modified_after_start:
            score += 15
            feedback_parts.append("CSV created after task start (15/15)")
            subscores['csv_timing'] = True
        elif csv_exists and not csv_modified_after_start:
            # File exists but predates task start — pre-existing file
            feedback_parts.append("CSV exists but predates task start — not created during this task (0/15)")
            subscores['csv_timing'] = False
        else:
            feedback_parts.append("CSV not created during this task (0/15)")
            subscores['csv_timing'] = False
    except Exception as e:
        logger.warning(f"Criterion 1 check failed: {e}")
        feedback_parts.append("CSV timing check error (0/15)")
        subscores['csv_timing'] = False

    # -------------------------------------------------------------------------
    # Criterion 2: CSV has required columns (15 pts)
    # -------------------------------------------------------------------------
    try:
        has_required_columns = result.get('has_required_columns', False)

        if has_required_columns:
            score += 15
            feedback_parts.append(
                "Has required columns: lane_id, raw_intensity, normalized_intensity (15/15)"
            )
            subscores['csv_columns'] = True
        else:
            feedback_parts.append(
                "Missing required columns — expected: lane_id (or 'lane'), "
                "raw_intensity (or 'intensity'/'area'), normalized_intensity "
                "(or 'normalized'/'ratio') (0/15)"
            )
            subscores['csv_columns'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")
        feedback_parts.append("CSV column check error (0/15)")
        subscores['csv_columns'] = False

    # -------------------------------------------------------------------------
    # Criterion 3: >=3 lanes quantified — 20 pts (10 pts partial if >=2 lanes)
    # -------------------------------------------------------------------------
    try:
        n_lanes = int(result.get('n_lanes', 0))

        if n_lanes >= 3:
            score += 20
            feedback_parts.append(f">=3 lanes quantified: {n_lanes} lanes (20/20)")
            subscores['lane_count'] = True
        elif n_lanes == 2:
            score += 10
            feedback_parts.append(f"Only 2 lanes quantified (partial credit: 10/20)")
            subscores['lane_count'] = False
        elif n_lanes == 1:
            score += 5
            feedback_parts.append(f"Only 1 lane quantified — too few for normalization (5/20)")
            subscores['lane_count'] = False
        else:
            feedback_parts.append("No lanes quantified in CSV (0/20)")
            subscores['lane_count'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")
        feedback_parts.append("Lane count check error (0/20)")
        subscores['lane_count'] = False

    # -------------------------------------------------------------------------
    # Criterion 4: All raw intensities > 0 (15 pts)
    # -------------------------------------------------------------------------
    try:
        raw_intensities_positive = result.get('raw_intensities_positive', False)
        raw_intensities = result.get('raw_intensities', [])
        n_lanes_check = result.get('n_lanes', 0)

        if n_lanes_check == 0:
            # No data — skip this criterion (not penalized twice)
            feedback_parts.append("No raw intensity data to validate (0/15)")
            subscores['raw_positive'] = False
        elif raw_intensities_positive:
            score += 15
            feedback_parts.append(
                f"All raw intensities positive (15/15)"
            )
            subscores['raw_positive'] = True
        else:
            # Provide detail on which values are zero/negative
            bad_vals = [v for v in raw_intensities if v <= 0]
            feedback_parts.append(
                f"Some zero or negative raw intensities found: {bad_vals[:3]} (0/15)"
            )
            subscores['raw_positive'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")
        feedback_parts.append("Raw intensity validation error (0/15)")
        subscores['raw_positive'] = False

    # -------------------------------------------------------------------------
    # Criterion 5: Normalized intensities show variation (15 pts)
    # Checks that max(normalized) - min(normalized) > 0.05
    # (some real variation expected; otherwise all samples identical or not normalized)
    # -------------------------------------------------------------------------
    try:
        normalized_has_variation = result.get('normalized_has_variation', False)
        normalized_intensities = result.get('normalized_intensities', [])
        n_lanes_check = result.get('n_lanes', 0)

        if n_lanes_check < 2:
            # Can't assess variation with <2 lanes
            feedback_parts.append("Insufficient lanes to assess normalization variation (0/15)")
            subscores['norm_variation'] = False
        elif normalized_has_variation:
            norm_min = min(normalized_intensities) if normalized_intensities else 0
            norm_max = max(normalized_intensities) if normalized_intensities else 0
            spread = norm_max - norm_min
            score += 15
            feedback_parts.append(
                f"Normalized intensities vary across lanes "
                f"(spread={spread:.3f}, range=[{norm_min:.3f},{norm_max:.3f}]) (15/15)"
            )
            subscores['norm_variation'] = True
        else:
            if normalized_intensities:
                spread = max(normalized_intensities) - min(normalized_intensities)
                feedback_parts.append(
                    f"Insufficient variation in normalized values "
                    f"(spread={spread:.4f} <= 0.05 threshold) — "
                    "check normalization formula (0/15)"
                )
            else:
                feedback_parts.append(
                    "No normalized intensity data found (0/15)"
                )
            subscores['norm_variation'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")
        feedback_parts.append("Normalization variation check error (0/15)")
        subscores['norm_variation'] = False

    # -------------------------------------------------------------------------
    # Criterion 6: Lane profiles image created (10 pts)
    # PNG must exist, be modified after task start, and be >5000 bytes
    # -------------------------------------------------------------------------
    try:
        profiles_exists = result.get('profiles_exists', False)
        profiles_modified_after_start = result.get('profiles_modified_after_start', False)
        profiles_size = int(result.get('profiles_size_bytes', 0))

        if profiles_exists and profiles_modified_after_start and profiles_size > 5000:
            score += 10
            feedback_parts.append(
                f"Lane profiles image created ({profiles_size} bytes) (10/10)"
            )
            subscores['profiles_image'] = True
        elif profiles_exists and profiles_modified_after_start and profiles_size <= 5000:
            score += 5
            feedback_parts.append(
                f"Lane profiles image exists but very small ({profiles_size} bytes) — "
                "may be empty or corrupt (5/10)"
            )
            subscores['profiles_image'] = False
        elif profiles_exists and not profiles_modified_after_start:
            feedback_parts.append(
                "Lane profiles image exists but predates task start — "
                "not created during this task (0/10)"
            )
            subscores['profiles_image'] = False
        else:
            feedback_parts.append(
                "Lane profiles image not found at "
                "~/Fiji_Data/results/gel/lane_profiles.png (0/10)"
            )
            subscores['profiles_image'] = False
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")
        feedback_parts.append("Profiles image check error (0/10)")
        subscores['profiles_image'] = False

    # -------------------------------------------------------------------------
    # Criterion 7: Densitometry report created with required keywords (10 pts)
    # Report must exist, be created after task start, contain 'lane' keyword
    # and at least one of 'intensity'/'expression', and mention 'highest'/'lowest'
    # -------------------------------------------------------------------------
    try:
        report_exists = result.get('report_exists', False)
        report_modified_after_start = result.get('report_modified_after_start', False)
        report_size = int(result.get('report_size_bytes', 0))
        report_has_lane = result.get('report_has_lane_keyword', False)
        report_has_intensity = result.get('report_has_intensity_keyword', False)

        if (report_exists and report_modified_after_start
                and report_size > 0 and report_has_lane and report_has_intensity):
            score += 10
            feedback_parts.append(
                f"Densitometry report created with required content "
                f"({report_size} bytes) (10/10)"
            )
            subscores['report'] = True
        elif report_exists and report_modified_after_start and report_size > 0:
            # Exists but missing some keywords — partial
            missing_kw = []
            if not report_has_lane:
                missing_kw.append("'lane'")
            if not report_has_intensity:
                missing_kw.append("'intensity'/'expression'")
            score += 5
            feedback_parts.append(
                f"Report created but missing keywords: {', '.join(missing_kw)} (5/10)"
            )
            subscores['report'] = False
        elif report_exists and not report_modified_after_start:
            feedback_parts.append(
                "Report file exists but predates task start (0/10)"
            )
            subscores['report'] = False
        elif report_exists and report_size == 0:
            feedback_parts.append("Report file is empty (0/10)")
            subscores['report'] = False
        else:
            feedback_parts.append(
                "Densitometry report not found at "
                "~/Fiji_Data/results/gel/densitometry_report.txt (0/10)"
            )
            subscores['report'] = False
    except Exception as e:
        logger.warning(f"Criterion 7 check failed: {e}")
        feedback_parts.append("Report check error (0/10)")
        subscores['report'] = False

    # -------------------------------------------------------------------------
    # Final scoring
    # -------------------------------------------------------------------------
    passed = score >= 60
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated"

    logger.info(
        f"gel_electrophoresis_densitometry: score={score}/100, passed={passed}, "
        f"n_lanes={result.get('n_lanes', 0)}"
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "n_lanes_quantified": result.get('n_lanes', 0),
            "csv_exists": result.get('csv_exists', False),
            "csv_modified_after_start": result.get('csv_modified_after_start', False),
            "has_required_columns": result.get('has_required_columns', False),
            "raw_intensities_positive": result.get('raw_intensities_positive', False),
            "normalized_has_variation": result.get('normalized_has_variation', False),
            "lane1_normalized_near_one": result.get('lane1_normalized_near_one', False),
            "profiles_exists": result.get('profiles_exists', False),
            "profiles_size_bytes": result.get('profiles_size_bytes', 0),
            "report_exists": result.get('report_exists', False),
            "report_size_bytes": result.get('report_size_bytes', 0),
        }
    }
