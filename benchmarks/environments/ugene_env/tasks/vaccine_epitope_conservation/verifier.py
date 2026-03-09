#!/usr/bin/env python3
"""Verifier for vaccine_epitope_conservation task.

Scoring breakdown (100 points total):
  Consensus FASTA file:             10
  Annotated alignment file:         15
  Stockholm format export:          10
  conserved_epitope annotations:    20
  Annotations have valid coords:    10
  Epitope report exists:            15
  Report ranks top 3 candidates:    10
  All 12 sequences in alignment:    10
                             TOTAL = 100
"""

import json
import os
import tempfile


def verify_vaccine_epitope_conservation(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        env_info["copy_from_env"](
            "/tmp/vaccine_epitope_conservation_result.json", tmp.name
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

    # --- Criterion 1: Consensus FASTA file (10 pts) ---
    c1 = 0
    if result.get("consensus_exists", False):
        c1 += 5
        if result.get("consensus_valid", False):
            c1 += 3
        cons_len = result.get("consensus_length", 0)
        if cons_len >= 100:
            c1 += 2
            feedback_parts.append(f"Consensus FASTA valid, {cons_len} residues (+{c1})")
        else:
            feedback_parts.append(f"Consensus FASTA exists but short ({cons_len} residues) (+{c1})")
    else:
        feedback_parts.append("Consensus FASTA MISSING (0)")
    score += c1
    subscores["consensus_fasta"] = c1

    # --- Criterion 2: Annotated alignment file (15 pts) ---
    c2 = 0
    if result.get("aln_exists", False):
        c2 += 8
        if result.get("aln_valid", False):
            c2 += 7
            feedback_parts.append("Annotated alignment ClustalW format valid (+15)")
        else:
            feedback_parts.append("Alignment exists but format invalid (+8)")
    else:
        feedback_parts.append("Annotated alignment MISSING (0)")
    score += c2
    subscores["annotated_alignment"] = c2

    # --- Criterion 3: Stockholm format export (10 pts) ---
    c3 = 0
    if result.get("sto_exists", False):
        c3 += 5
        if result.get("sto_valid", False):
            c3 += 5
            feedback_parts.append("Stockholm format valid (+10)")
        else:
            feedback_parts.append("Stockholm file exists but invalid format (+5)")
    else:
        feedback_parts.append("Stockholm format MISSING (0)")
    score += c3
    subscores["stockholm_export"] = c3

    # Early exit if nothing produced
    if c1 == 0 and c2 == 0 and c3 == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files produced. " + "; ".join(feedback_parts),
            "subscores": subscores,
        }

    # --- Criterion 4: conserved_epitope annotations (20 pts) ---
    c4 = 0
    has_epitope = result.get("aln_has_epitope_annotation", False)
    has_group = result.get("aln_has_vaccine_group", False)
    epitope_count = result.get("epitope_annotation_count", 0)

    if has_epitope:
        c4 += 10
        feedback_parts.append(f"conserved_epitope annotations found ({epitope_count}) (+10)")
        if has_group:
            c4 += 5
            feedback_parts.append("vaccine_targets group present (+5)")
        if epitope_count >= 3:
            c4 += 5
            feedback_parts.append(f"Multiple epitopes annotated ({epitope_count}) (+5)")
        elif epitope_count >= 1:
            c4 += 2
    else:
        feedback_parts.append("No conserved_epitope annotations found (0)")
    c4 = min(c4, 20)
    score += c4
    subscores["epitope_annotations"] = c4

    # --- Criterion 5: Annotations have valid coordinates (10 pts) ---
    c5 = 0
    valid_count = result.get("valid_epitope_count", 0)
    if valid_count >= 3:
        c5 = 10
        feedback_parts.append(f"{valid_count} epitopes span >=9 residues (+10)")
    elif valid_count >= 1:
        c5 = 5
        feedback_parts.append(f"Only {valid_count} epitope(s) span >=9 residues (+5)")
    else:
        feedback_parts.append("No epitope annotations with valid coordinates (0)")
    score += c5
    subscores["epitope_coordinates"] = c5

    # --- Criterion 6: Epitope report exists (15 pts) ---
    c6 = 0
    if result.get("report_exists", False):
        c6 += 5
        feedback_parts.append("Epitope report exists (+5)")
        if result.get("report_has_positions", False):
            c6 += 5
            feedback_parts.append("Report contains position ranges (+5)")
        if result.get("report_has_conservation_pct", False):
            c6 += 5
            feedback_parts.append("Report contains conservation percentages (+5)")
    else:
        feedback_parts.append("Epitope report MISSING (0)")
    c6 = min(c6, 15)
    score += c6
    subscores["epitope_report"] = c6

    # --- Criterion 7: Report ranks top 3 candidates (10 pts) ---
    c7 = 0
    if result.get("report_has_ranking", False):
        c7 += 5
        feedback_parts.append("Report ranks epitope candidates (+5)")
        if result.get("report_has_count", False):
            c7 += 5
            feedback_parts.append("Report includes total epitope count (+5)")
    else:
        if result.get("report_has_count", False):
            c7 += 3
            feedback_parts.append("Report has count but no ranking (+3)")
        else:
            feedback_parts.append("Report missing ranking and count (0)")
    score += c7
    subscores["report_ranking"] = c7

    # --- Criterion 8: All 12 sequences in alignment (10 pts) ---
    c8 = 0
    seq_count = result.get("aln_seq_count", 0)
    if seq_count >= 12:
        c8 = 10
        feedback_parts.append(f"All 12 sequences in alignment (+10)")
    elif seq_count >= 8:
        c8 = 6
        feedback_parts.append(f"{seq_count}/12 sequences in alignment (+6)")
    elif seq_count >= 4:
        c8 = 3
        feedback_parts.append(f"Only {seq_count}/12 sequences in alignment (+3)")
    else:
        feedback_parts.append(f"Too few sequences ({seq_count}/12) in alignment (0)")
    score += c8
    subscores["sequence_count"] = c8

    score = min(score, 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "subscores": subscores,
    }
