#!/usr/bin/env python3
"""Verifier for clinical_variant_annotation task.

Scoring breakdown (100 points total):
  Corrected GB file exists & valid:  10
  Gene qualifier fixed BRCA2→BRCA1:  15
  CDS boundaries corrected:          20
  Missense variant annotated:        15
  Frameshift deletion annotated:     15
  ORF annotations present:           10
  Clinical report complete:          15
                             TOTAL = 100
"""

import json
import os
import re
import tempfile


def verify_clinical_variant_annotation(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    # Read result JSON
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        env_info["copy_from_env"](
            "/tmp/clinical_variant_annotation_result.json", tmp.name
        )
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}",
        }

    # Read ground truth
    gt = {}
    try:
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_gt.close()
        env_info["copy_from_env"](
            "/tmp/clinical_variant_annotation_gt.json", tmp_gt.name
        )
        with open(tmp_gt.name) as f:
            gt = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception:
        gt = {
            "correct_cds_start": 16,
            "missense_variant_pos_min": 1195,
            "missense_variant_pos_max": 1220,
            "deletion_pos_min": 1845,
            "deletion_pos_max": 1875,
        }

    # --- Criterion 1: Corrected file exists and valid GenBank (10 pts) ---
    c1 = 0
    if result.get("file_exists", False):
        c1 += 5
        feedback_parts.append("Corrected GB file exists (+5)")
        if result.get("valid_gb", False):
            c1 += 5
            feedback_parts.append("Valid GenBank format (+5)")
        else:
            feedback_parts.append("Invalid GenBank format (0)")
    else:
        feedback_parts.append("Corrected GB file MISSING (0)")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback_parts),
            "subscores": {"file_exists": 0},
        }
    score += c1
    subscores["file_exists_valid"] = c1

    # --- Criterion 2: Gene qualifier fixed BRCA2 → BRCA1 (15 pts) ---
    c2 = 0
    has_brca1 = result.get("has_brca1_gene", False)
    has_brca2 = result.get("has_brca2_gene", False)
    if has_brca1 and not has_brca2:
        c2 = 15
        feedback_parts.append("Gene qualifier corrected to BRCA1 (+15)")
    elif has_brca1 and has_brca2:
        c2 = 8
        feedback_parts.append("BRCA1 present but BRCA2 not fully removed (+8)")
    elif not has_brca1 and not has_brca2:
        c2 = 0
        feedback_parts.append("Gene qualifier missing entirely (0)")
    else:
        c2 = 0
        feedback_parts.append("Gene qualifier still says BRCA2 (0)")
    score += c2
    subscores["gene_qualifier"] = c2

    # --- Criterion 3: CDS boundaries corrected (20 pts) ---
    c3 = 0
    cds_start_str = result.get("cds_start", "")
    if cds_start_str and result.get("has_cds", False):
        try:
            cds_start = int(cds_start_str)
            correct_start = gt.get("correct_cds_start", 16)
            wrong_start = gt.get("wrong_cds_start", 1)
            if abs(cds_start - correct_start) <= 3:
                c3 = 20
                feedback_parts.append(
                    f"CDS start corrected to ~{cds_start} (expected ~{correct_start}) (+20)"
                )
            elif cds_start != wrong_start:
                c3 = 10
                feedback_parts.append(
                    f"CDS start changed to {cds_start} (expected ~{correct_start}) (+10)"
                )
            else:
                feedback_parts.append("CDS start unchanged from wrong position (0)")
        except ValueError:
            feedback_parts.append("CDS start not parseable (0)")
    else:
        feedback_parts.append("No CDS annotation found (0)")
    score += c3
    subscores["cds_boundaries"] = c3

    # --- Criterion 4: Missense variant annotated (15 pts) ---
    c4 = 0
    if result.get("has_variation", False):
        var_positions = result.get("variation_positions", "")
        pos_min = gt.get("missense_variant_pos_min", 1195)
        pos_max = gt.get("missense_variant_pos_max", 1220)

        # Parse positions from the comma-separated string
        positions = re.findall(r"\d+", var_positions)
        found_missense = False
        for p in positions:
            p_int = int(p)
            if pos_min <= p_int <= pos_max:
                found_missense = True
                break

        if found_missense:
            c4 = 15
            feedback_parts.append("Missense variant annotated at correct position (+15)")
        else:
            # Give partial credit for having any variation annotation
            c4 = 5
            feedback_parts.append(
                "Variation annotations present but missense not at expected position (+5)"
            )
    else:
        feedback_parts.append("No variant annotations found (0)")
    score += c4
    subscores["missense_variant"] = c4

    # --- Criterion 5: Frameshift deletion annotated (15 pts) ---
    c5 = 0
    if result.get("has_variation", False):
        var_positions = result.get("variation_positions", "")
        del_min = gt.get("deletion_pos_min", 1845)
        del_max = gt.get("deletion_pos_max", 1875)

        positions = re.findall(r"\d+", var_positions)
        found_deletion = False
        for p in positions:
            p_int = int(p)
            if del_min <= p_int <= del_max:
                found_deletion = True
                break

        if found_deletion:
            c5 = 15
            feedback_parts.append(
                "Frameshift deletion annotated at correct position (+15)"
            )
        elif result.get("variation_count", 0) >= 2:
            c5 = 5
            feedback_parts.append(
                "Multiple variants annotated but deletion not at expected position (+5)"
            )
        else:
            feedback_parts.append("Deletion variant not found at expected position (0)")
    else:
        feedback_parts.append("No variant annotations for deletion (0)")
    score += c5
    subscores["frameshift_deletion"] = c5

    # --- Criterion 6: ORF annotations present (10 pts) ---
    c6 = 0
    if result.get("has_orf_annotations", False):
        orf_count = result.get("orf_count", 0)
        if orf_count >= 2:
            c6 = 10
            feedback_parts.append(f"ORF annotations found ({orf_count} ORFs) (+10)")
        else:
            c6 = 5
            feedback_parts.append(f"Only {orf_count} ORF annotation(s) (+5)")
    else:
        feedback_parts.append("No ORF annotations found (0)")
    score += c6
    subscores["orf_annotations"] = c6

    # --- Criterion 7: Clinical report complete (15 pts) ---
    c7 = 0
    if result.get("report_exists", False):
        c7 += 3
        report_items = 0
        if result.get("report_mentions_brca1", False):
            report_items += 1
        if result.get("report_mentions_cds", False):
            report_items += 1
        if result.get("report_mentions_variant", False):
            report_items += 1
        if result.get("report_mentions_deletion", False):
            report_items += 1
        if result.get("report_mentions_gene_fix", False):
            report_items += 1

        c7 += min(report_items * 2, 12)
        feedback_parts.append(
            f"Clinical report exists with {report_items}/5 key elements (+{c7})"
        )
    else:
        feedback_parts.append("Clinical report MISSING (0)")
    score += c7
    subscores["clinical_report"] = c7

    score = min(score, 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "subscores": subscores,
    }
