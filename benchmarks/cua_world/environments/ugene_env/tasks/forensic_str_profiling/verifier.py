#!/usr/bin/env python3
"""Verifier for forensic_str_profiling task.

Scoring breakdown (100 points total):
  Annotated GB files exist:      3 loci × 5 pts  =  15
  GenBank format valid:          3 loci × 3.3 pts ≈ 10
  STR_core_repeat annotations:   3 loci × 6.7 pts ≈ 20
  forensic_markers group:        3 loci × 3.3 pts ≈ 10
  Annotation coordinates valid:  3 loci × 5 pts  =  15
  Report file exists w/ content: 15
  Report contains repeat motifs: 15
                          TOTAL = 100
"""

import json
import os
import tempfile
import re


def verify_forensic_str_profiling(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    # Read the exported result JSON
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        env_info["copy_from_env"](
            "/tmp/forensic_str_profiling_result.json", tmp.name
        )
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}. Agent likely did not complete the task.",
        }

    # Read ground truth
    gt = {}
    try:
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_gt.close()
        env_info["copy_from_env"](
            "/tmp/forensic_str_profiling_gt.json", tmp_gt.name
        )
        with open(tmp_gt.name) as f:
            gt = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception:
        pass  # proceed without GT — use hardcoded fallback ranges

    # --- Criterion 1: Annotated GenBank files exist (15 pts) ---
    files_score = 0
    for locus, key in [("D13S317", "d13"), ("vWA", "vwa"), ("TH01", "th01")]:
        if result.get(f"{key}_exists", False):
            files_score += 5
            feedback_parts.append(f"{locus}_annotated.gb exists (+5)")
        else:
            feedback_parts.append(f"{locus}_annotated.gb MISSING (0)")
    score += files_score
    subscores["annotated_files_exist"] = files_score

    # Early exit if no files at all
    if files_score == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No annotated GenBank files found in results directory. "
            + "; ".join(feedback_parts),
            "subscores": subscores,
        }

    # --- Criterion 2: GenBank format valid (10 pts) ---
    format_score = 0
    for locus, key in [("D13S317", "d13"), ("vWA", "vwa"), ("TH01", "th01")]:
        if result.get(f"{key}_valid_gb", False):
            format_score += 3
            feedback_parts.append(f"{locus} valid GenBank format (+3)")
        else:
            feedback_parts.append(f"{locus} invalid GenBank format (0)")
    # Round up the remaining point
    if format_score == 9:
        format_score = 10
    score += format_score
    subscores["genbank_format_valid"] = format_score

    # --- Criterion 3: STR_core_repeat annotations present (20 pts) ---
    annotation_score = 0
    for locus, key in [("D13S317", "d13"), ("vWA", "vwa"), ("TH01", "th01")]:
        if result.get(f"{key}_has_str_annotation", False):
            annotation_score += 7
            feedback_parts.append(f"{locus} has STR_core_repeat annotation (+7)")
        else:
            feedback_parts.append(f"{locus} MISSING STR_core_repeat annotation (0)")
    # Cap at 20
    annotation_score = min(annotation_score, 20)
    score += annotation_score
    subscores["str_annotations"] = annotation_score

    # --- Criterion 4: forensic_markers group (10 pts) ---
    group_score = 0
    for locus, key in [("D13S317", "d13"), ("vWA", "vwa"), ("TH01", "th01")]:
        if result.get(f"{key}_has_forensic_group", False):
            group_score += 3
            feedback_parts.append(f"{locus} has forensic_markers group (+3)")
        else:
            feedback_parts.append(f"{locus} missing forensic_markers group (0)")
    if group_score == 9:
        group_score = 10
    score += group_score
    subscores["forensic_group"] = group_score

    # --- Criterion 5: Annotation coordinates in valid range (15 pts) ---
    coord_score = 0
    for locus, key in [("D13S317", "d13"), ("vWA", "vwa"), ("TH01", "th01")]:
        coords_str = result.get(f"{key}_annotation_coords", "")
        if coords_str:
            # Parse coordinate pairs (e.g., "121..195")
            coord_pairs = re.findall(r"(\d+)\.\.(\d+)", coords_str)
            if coord_pairs:
                # Check if any coordinate pair falls in expected range
                locus_gt = gt.get(locus, {})
                start_min = locus_gt.get("expected_repeat_region_start_min", 50)
                start_max = locus_gt.get("expected_repeat_region_start_max", 250)
                end_min = locus_gt.get("expected_repeat_region_end_min", 100)
                end_max = locus_gt.get("expected_repeat_region_end_max", 350)

                for s, e in coord_pairs:
                    s, e = int(s), int(e)
                    if start_min <= s <= start_max and end_min <= e <= end_max:
                        coord_score += 5
                        feedback_parts.append(
                            f"{locus} annotation coords {s}..{e} in valid range (+5)"
                        )
                        break
                else:
                    feedback_parts.append(
                        f"{locus} annotation coords outside expected range (0)"
                    )
            else:
                feedback_parts.append(f"{locus} no parseable coordinates (0)")
        else:
            feedback_parts.append(f"{locus} no annotation coordinates found (0)")
    score += coord_score
    subscores["annotation_coordinates"] = coord_score

    # --- Criterion 6: Report file exists with all loci (15 pts) ---
    report_score = 0
    if result.get("report_exists", False):
        report_score += 3
        feedback_parts.append("Report file exists (+3)")
        loci_count = 0
        if result.get("report_has_d13", False):
            loci_count += 1
        if result.get("report_has_vwa", False):
            loci_count += 1
        if result.get("report_has_th01", False):
            loci_count += 1

        if loci_count == 3:
            report_score += 12
            feedback_parts.append("Report mentions all 3 loci (+12)")
        elif loci_count >= 1:
            report_score += 4 * loci_count
            feedback_parts.append(
                f"Report mentions {loci_count}/3 loci (+{4 * loci_count})"
            )
    else:
        feedback_parts.append("Report file MISSING (0)")
    score += report_score
    subscores["report_content"] = report_score

    # --- Criterion 7: Report contains correct repeat motifs (15 pts) ---
    motif_score = 0
    motif_count = 0
    # D13S317 uses TATC/AGAT (complementary strands)
    if result.get("report_has_tatc_or_agat", False):
        motif_count += 1
    # vWA uses TCTA
    if result.get("report_has_tcta", False):
        motif_count += 1
    # TH01 uses AATG (or TCAT on the opposite strand)
    if result.get("report_has_aatg", False) or result.get("report_has_tcat", False):
        motif_count += 1

    if motif_count == 3:
        motif_score = 15
        feedback_parts.append("Report contains all 3 correct repeat motifs (+15)")
    elif motif_count >= 1:
        motif_score = 5 * motif_count
        feedback_parts.append(
            f"Report contains {motif_count}/3 repeat motifs (+{motif_score})"
        )
    else:
        feedback_parts.append("Report missing repeat motif information (0)")
    score += motif_score
    subscores["repeat_motifs"] = motif_score

    # Final score
    score = min(score, 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "subscores": subscores,
    }
