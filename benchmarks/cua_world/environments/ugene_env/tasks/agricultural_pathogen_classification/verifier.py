#!/usr/bin/env python3
"""Verifier for agricultural_pathogen_classification task.

Scoring breakdown (100 points total):
  PHYLIP alignment file:         15
  ClustalW alignment file:       10
  Newick tree file:              15
  All 11 sequences in alignment: 15
  Tree contains all taxa:        15
  Diagnostic report exists:      15
  Correct pathogen identified:   15
                          TOTAL = 100
"""

import json
import os
import tempfile


def verify_agricultural_pathogen_classification(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        env_info["copy_from_env"](
            "/tmp/agricultural_pathogen_classification_result.json", tmp.name
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

    # --- Criterion 1: PHYLIP alignment file (15 pts) ---
    c1 = 0
    if result.get("phy_exists", False):
        c1 += 8
        feedback_parts.append("PHYLIP file exists (+8)")
        if result.get("phy_valid", False):
            c1 += 7
            feedback_parts.append("Valid PHYLIP format (+7)")
        else:
            feedback_parts.append("Invalid PHYLIP format (0)")
    else:
        feedback_parts.append("PHYLIP alignment file MISSING (0)")
    score += c1
    subscores["phylip_file"] = c1

    # --- Criterion 2: ClustalW alignment file (10 pts) ---
    c2 = 0
    if result.get("aln_exists", False):
        c2 += 5
        feedback_parts.append("ClustalW file exists (+5)")
        if result.get("aln_valid", False):
            c2 += 5
            feedback_parts.append("Valid ClustalW format (+5)")
        else:
            feedback_parts.append("Invalid ClustalW format (0)")
    else:
        feedback_parts.append("ClustalW alignment file MISSING (0)")
    score += c2
    subscores["clustalw_file"] = c2

    # --- Criterion 3: Newick tree file (15 pts) ---
    c3 = 0
    if result.get("nwk_exists", False):
        c3 += 8
        feedback_parts.append("Newick tree file exists (+8)")
        if result.get("nwk_valid", False):
            c3 += 7
            feedback_parts.append("Valid Newick syntax (+7)")
        else:
            feedback_parts.append("Invalid Newick syntax (0)")
    else:
        feedback_parts.append("Newick tree file MISSING (0)")
    score += c3
    subscores["newick_file"] = c3

    # Early exit if nothing produced
    if c1 == 0 and c2 == 0 and c3 == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files produced. " + "; ".join(feedback_parts),
            "subscores": subscores,
        }

    # --- Criterion 4: All 11 sequences in alignment (15 pts) ---
    c4 = 0
    phy_count = result.get("phy_seq_count", 0)
    aln_count = result.get("aln_seq_count", 0)
    best_count = max(phy_count, aln_count)
    if best_count >= 11:
        c4 = 15
        feedback_parts.append(f"All 11 sequences present in alignment (+15)")
    elif best_count >= 8:
        c4 = 10
        feedback_parts.append(f"{best_count}/11 sequences in alignment (+10)")
    elif best_count >= 5:
        c4 = 5
        feedback_parts.append(f"Only {best_count}/11 sequences in alignment (+5)")
    elif best_count >= 1:
        c4 = 2
        feedback_parts.append(f"Only {best_count}/11 sequences in alignment (+2)")
    else:
        feedback_parts.append("No sequences found in alignment (0)")
    score += c4
    subscores["sequence_count"] = c4

    # --- Criterion 5: Tree contains all taxa (15 pts) ---
    c5 = 0
    leaf_count = result.get("nwk_leaf_count", 0)
    has_unknown = result.get("nwk_has_unknown", False)
    has_fusarium = result.get("nwk_has_fusarium", False)

    if leaf_count >= 11:
        c5 = 12
        feedback_parts.append(f"Tree has {leaf_count} leaves (expected 11) (+12)")
    elif leaf_count >= 8:
        c5 = 8
        feedback_parts.append(f"Tree has {leaf_count}/11 leaves (+8)")
    elif leaf_count >= 3:
        c5 = 4
        feedback_parts.append(f"Tree has only {leaf_count}/11 leaves (+4)")
    else:
        feedback_parts.append(f"Tree has {leaf_count} leaves (0)")

    if has_unknown and has_fusarium:
        c5 += 3
        feedback_parts.append("Tree contains both unknown and Fusarium taxa (+3)")
    elif has_unknown or has_fusarium:
        c5 += 1
    c5 = min(c5, 15)
    score += c5
    subscores["tree_taxa"] = c5

    # --- Criterion 6: Diagnostic report exists (15 pts) ---
    c6 = 0
    if result.get("report_exists", False):
        c6 += 5
        feedback_parts.append("Diagnostic report exists (+5)")
        if result.get("report_has_unknown", False):
            c6 += 5
            feedback_parts.append("Report discusses unknown sample (+5)")
        if result.get("report_has_management", False):
            c6 += 5
            feedback_parts.append("Report includes management recommendations (+5)")
    else:
        feedback_parts.append("Diagnostic report MISSING (0)")
    c6 = min(c6, 15)
    score += c6
    subscores["diagnostic_report"] = c6

    # --- Criterion 7: Correct pathogen identified (15 pts) ---
    c7 = 0
    if result.get("report_has_fusarium", False):
        c7 += 8
        feedback_parts.append("Report identifies Fusarium (+8)")
        if result.get("report_has_graminearum", False):
            c7 += 7
            feedback_parts.append("Report identifies F. graminearum specifically (+7)")
        else:
            feedback_parts.append("Report does not specify graminearum species (0)")
    else:
        feedback_parts.append("Report does not identify Fusarium (0)")
    score += c7
    subscores["pathogen_id"] = c7

    score = min(score, 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "subscores": subscores,
    }
