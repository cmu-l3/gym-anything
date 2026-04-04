#!/usr/bin/env python3
"""
Verifier for 3d_brain_structure_volumetry task.

Scoring (100 points total, pass threshold = 60):

  Criterion 1: CSV created after task start                        — 15 pts
  Criterion 2: CSV has required volume columns                     — 15 pts
  Criterion 3: >= 2 structures measured                            — 15 pts
  Criterion 4: All volume_mm3 values > 0                           — 15 pts
  Criterion 5: Brain volume is plausible (>100, <1e7 mm3)          — 15 pts
  Criterion 6: Orthogonal views image created (size > 10 KB)       — 15 pts
  Criterion 7: Volumetry report with brain+ventricle keywords       — 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_3d_brain_structure_volumetry(traj, env_info, task_info):
    """
    Verify the 3D brain volumetry task output.

    Reads /tmp/volumetry_result.json written by export_result.sh via copy_from_env,
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
            copy_from_env('/tmp/volumetry_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read volumetry export result: {e}",
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
            feedback_parts.append("volume_measurements.csv created after task start (15/15)")
            subscores['csv_created'] = True
        elif csv_exists and not csv_modified:
            score += 5
            feedback_parts.append(
                "volume_measurements.csv exists but was not created during this task (5/15)"
            )
            subscores['csv_created'] = False
        else:
            feedback_parts.append("volume_measurements.csv not created (0/15)")
            subscores['csv_created'] = False
    except Exception as e:
        logger.warning(f"Criterion 1 check failed: {e}")
        subscores['csv_created'] = False

    # Criterion 2: Required volume columns (15 pts)
    try:
        has_required = result.get('has_required_columns', False)
        header_cols = result.get('header_cols', [])
        if has_required:
            score += 15
            feedback_parts.append(
                f"Required columns present (structure_name, volume): "
                f"{', '.join(header_cols[:6])} (15/15)"
            )
            subscores['required_columns'] = True
        elif result.get('csv_exists', False):
            feedback_parts.append(
                f"CSV exists but missing required columns. Found: "
                f"{', '.join(header_cols[:8])} (0/15)"
            )
            subscores['required_columns'] = False
        else:
            feedback_parts.append("CSV not found - cannot check columns (0/15)")
            subscores['required_columns'] = False
    except Exception as e:
        logger.warning(f"Criterion 2 check failed: {e}")
        subscores['required_columns'] = False

    # Criterion 3: >= 2 structures measured (15 pts)
    try:
        n_structures = int(result.get('n_structures', 0))
        volumes_mm3 = result.get('volumes_mm3', {})
        structure_names = list(volumes_mm3.keys())

        if n_structures >= 2:
            score += 15
            feedback_parts.append(
                f"{n_structures} structures measured: "
                f"{', '.join(structure_names[:4])} (15/15)"
            )
            subscores['n_structures'] = True
        elif n_structures == 1:
            score += 7
            feedback_parts.append(
                f"Only 1 structure measured: {', '.join(structure_names)}. "
                f"Need brain_tissue + ventricles (7/15)"
            )
            subscores['n_structures'] = 'partial'
        else:
            feedback_parts.append("No structures measured in CSV (0/15)")
            subscores['n_structures'] = False
    except Exception as e:
        logger.warning(f"Criterion 3 check failed: {e}")
        subscores['n_structures'] = False

    # Criterion 4: All volume_mm3 > 0 (15 pts)
    try:
        all_positive = result.get('all_volumes_positive', False)
        volumes_mm3 = result.get('volumes_mm3', {})
        if all_positive and len(volumes_mm3) > 0:
            score += 15
            vol_summary = ", ".join(
                f"{k}={v:.1f}" for k, v in list(volumes_mm3.items())[:4]
            )
            feedback_parts.append(
                f"All volumes positive: {vol_summary} mm3 (15/15)"
            )
            subscores['all_positive'] = True
        elif len(volumes_mm3) > 0:
            zero_structs = [k for k, v in volumes_mm3.items() if v <= 0]
            if zero_structs:
                feedback_parts.append(
                    f"Zero or negative volumes for: {', '.join(zero_structs)} (0/15)"
                )
            else:
                feedback_parts.append("Volume values not all positive (0/15)")
            subscores['all_positive'] = False
        else:
            feedback_parts.append("No volume data found (0/15)")
            subscores['all_positive'] = False
    except Exception as e:
        logger.warning(f"Criterion 4 check failed: {e}")
        subscores['all_positive'] = False

    # Criterion 5: Brain volume plausible (15 pts)
    # The ImageJ MRI stack is 186x226x27 = 1,133,532 voxels at 1.5 mm3/voxel = ~1.7M mm3 total
    # Brain tissue should be a meaningful fraction: > 100 mm3, < 10^7 mm3
    try:
        brain_vol = float(result.get('brain_volume_mm3', 0.0))
        ventricle_vol = float(result.get('ventricle_volume_mm3', 0.0))

        MIN_BRAIN_MM3 = 100.0         # Absolute minimum (any real segmentation)
        MAX_BRAIN_MM3 = 10_000_000.0  # Absolute maximum (clearly unphysical)

        if MIN_BRAIN_MM3 < brain_vol < MAX_BRAIN_MM3:
            score += 15
            feedback_parts.append(
                f"Brain volume plausible: {brain_vol:.1f} mm3 (15/15)"
            )
            subscores['brain_volume_plausible'] = True

            # Bonus consistency check: ventricle < brain (informational only)
            if ventricle_vol > 0 and ventricle_vol < brain_vol:
                vent_pct = (ventricle_vol / brain_vol) * 100
                feedback_parts.append(
                    f"Ventricle/brain ratio: {vent_pct:.1f}% "
                    f"({'NORMAL (<5%)' if vent_pct < 5 else 'elevated'})"
                )
                subscores['ventricle_ratio'] = vent_pct
            elif ventricle_vol >= brain_vol and ventricle_vol > 0:
                feedback_parts.append(
                    f"WARNING: Ventricle volume ({ventricle_vol:.1f}) >= "
                    f"brain volume ({brain_vol:.1f}) - check segmentation"
                )
        elif brain_vol <= 0:
            # Strict zero: no brain volume reported at all (do-nothing case)
            feedback_parts.append(
                f"Brain volume is zero - no brain tissue segmented (0/15)"
            )
            subscores['brain_volume_plausible'] = False
        elif brain_vol <= MIN_BRAIN_MM3:
            score += 3
            feedback_parts.append(
                f"Brain volume too small ({brain_vol:.1f} mm3 <= {MIN_BRAIN_MM3} mm3) "
                f"- likely segmentation error (3/15)"
            )
            subscores['brain_volume_plausible'] = False
        else:
            feedback_parts.append(
                f"Brain volume implausibly large ({brain_vol:.1f} mm3 > {MAX_BRAIN_MM3:.0f} mm3) "
                f"- likely entire image selected (0/15)"
            )
            subscores['brain_volume_plausible'] = False
    except Exception as e:
        logger.warning(f"Criterion 5 check failed: {e}")
        subscores['brain_volume_plausible'] = False

    # Criterion 6: Orthogonal views image created (15 pts)
    try:
        ortho_exists = result.get('ortho_exists', False)
        ortho_modified = result.get('ortho_modified_after_start', False)
        ortho_size = int(result.get('ortho_size_bytes', 0))
        MIN_ORTHO_BYTES = 10_000  # 10 KB minimum for a real TIFF

        if ortho_exists and ortho_modified and ortho_size > MIN_ORTHO_BYTES:
            score += 15
            feedback_parts.append(
                f"Orthogonal views TIFF created ({ortho_size:,} bytes) (15/15)"
            )
            subscores['ortho_views'] = True
        elif ortho_exists and ortho_modified and ortho_size > 0:
            score += 8
            feedback_parts.append(
                f"Orthogonal views file created but small "
                f"({ortho_size} bytes < {MIN_ORTHO_BYTES} bytes) (8/15)"
            )
            subscores['ortho_views'] = 'partial'
        elif ortho_exists and not ortho_modified:
            score += 3
            feedback_parts.append(
                "orthogonal_views.tif exists but not created during this task (3/15)"
            )
            subscores['ortho_views'] = False
        else:
            feedback_parts.append("orthogonal_views.tif not created (0/15)")
            subscores['ortho_views'] = False
    except Exception as e:
        logger.warning(f"Criterion 6 check failed: {e}")
        subscores['ortho_views'] = False

    # Criterion 7: Volumetry report with relevant keywords (10 pts)
    try:
        report_exists = result.get('report_exists', False)
        report_modified = result.get('report_modified_after_start', False)
        has_brain = result.get('report_has_brain_keyword', False)
        has_ventricle = result.get('report_has_ventricle_keyword', False)
        has_volume = result.get('report_has_volume_keyword', False)
        report_size = int(result.get('report_size_bytes', 0))
        report_lines = int(result.get('report_line_count', 0))

        if report_exists and report_modified and has_brain and has_ventricle:
            score += 10
            feedback_parts.append(
                f"Volumetry report with brain+ventricle content "
                f"({report_lines} lines) (10/10)"
            )
            subscores['report'] = True
        elif report_exists and report_modified and (has_brain or has_ventricle):
            score += 6
            missing = 'ventricle' if has_brain else 'brain'
            feedback_parts.append(
                f"Report missing '{missing}' keyword (6/10)"
            )
            subscores['report'] = 'partial'
        elif report_exists and report_modified:
            score += 3
            feedback_parts.append(
                f"Report created ({report_size} bytes) but missing required keywords (3/10)"
            )
            subscores['report'] = False
        elif report_exists and not report_modified:
            score += 1
            feedback_parts.append(
                "volumetry_report.txt exists but not created during this task (1/10)"
            )
            subscores['report'] = False
        else:
            feedback_parts.append("volumetry_report.txt not created (0/10)")
            subscores['report'] = False
    except Exception as e:
        logger.warning(f"Criterion 7 check failed: {e}")
        subscores['report'] = False

    passed = score >= 60
    feedback = " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "n_structures": result.get('n_structures', 0),
            "volumes_mm3": result.get('volumes_mm3', {}),
            "brain_volume_mm3": result.get('brain_volume_mm3', 0.0),
            "ventricle_volume_mm3": result.get('ventricle_volume_mm3', 0.0),
            "csv_exists": result.get('csv_exists', False),
            "csv_modified_after_start": result.get('csv_modified_after_start', False),
            "ortho_size_bytes": result.get('ortho_size_bytes', 0),
            "report_exists": result.get('report_exists', False),
            "report_has_brain_keyword": result.get('report_has_brain_keyword', False),
            "report_has_ventricle_keyword": result.get('report_has_ventricle_keyword', False),
        }
    }
