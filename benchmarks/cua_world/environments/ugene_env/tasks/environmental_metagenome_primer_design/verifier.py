#!/usr/bin/env python3
"""Verifier for environmental_metagenome_primer_design task.

Scoring breakdown (100 points total):
  Alignment FASTA file:          12
  All 14 sequences present:      10
  Primer design file exists:     15
  Primers have valid sequences:  13
  Primers have Tm values:        10
  Amplicon size specified:       10
  Specificity report exists:     15
  Report has PCR conditions:     15
                          TOTAL = 100
"""

import json
import os
import re
import tempfile


def verify_environmental_metagenome_primer_design(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        env_info["copy_from_env"](
            "/tmp/environmental_metagenome_primer_design_result.json", tmp.name
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
            "/tmp/environmental_metagenome_primer_design_gt.json", tmp_gt.name
        )
        with open(tmp_gt.name) as f:
            gt = json.load(f)
        os.unlink(tmp_gt.name)
    except Exception:
        gt = {
            "total_sequences": 14,
            "valid_primer_length_min": 18,
            "valid_primer_length_max": 25,
            "valid_tm_min": 50.0,
            "valid_tm_max": 70.0,
            "valid_amplicon_min": 100,
            "valid_amplicon_max": 600,
        }

    # --- Criterion 1: Alignment FASTA file (12 pts) ---
    c1 = 0
    if result.get("aln_exists", False):
        c1 += 6
        if result.get("aln_valid", False):
            c1 += 6
            feedback_parts.append("Alignment FASTA valid (+12)")
        else:
            feedback_parts.append("Alignment file exists but invalid format (+6)")
    else:
        feedback_parts.append("Alignment FASTA MISSING (0)")
    score += c1
    subscores["alignment_fasta"] = c1

    # --- Criterion 2: All 14 sequences present (10 pts) ---
    c2 = 0
    seq_count = result.get("aln_seq_count", 0)
    expected = gt.get("total_sequences", 14)
    if seq_count >= expected:
        c2 = 10
        feedback_parts.append(f"All {expected} sequences in alignment (+10)")
    elif seq_count >= 10:
        c2 = 7
        feedback_parts.append(f"{seq_count}/{expected} sequences (+7)")
    elif seq_count >= 5:
        c2 = 4
        feedback_parts.append(f"Only {seq_count}/{expected} sequences (+4)")
    else:
        feedback_parts.append(f"Too few sequences ({seq_count}/{expected}) (0)")
    score += c2
    subscores["sequence_count"] = c2

    # --- Criterion 3: Primer design file exists (15 pts) ---
    c3 = 0
    if result.get("primer_exists", False):
        c3 += 5
        if result.get("primer_has_forward", False):
            c3 += 5
            feedback_parts.append("Forward primer found (+5)")
        if result.get("primer_has_reverse", False):
            c3 += 5
            feedback_parts.append("Reverse primer found (+5)")
        if c3 == 5:
            feedback_parts.append("Primer file exists but missing primer sequences (+5)")
    else:
        feedback_parts.append("Primer design file MISSING (0)")
    score += c3
    subscores["primer_file"] = c3

    # --- Criterion 4: Primers have valid DNA sequences (13 pts) ---
    c4 = 0
    len_min = gt.get("valid_primer_length_min", 18)
    len_max = gt.get("valid_primer_length_max", 25)

    fwd_seq = result.get("forward_seq", "")
    rev_seq = result.get("reverse_seq", "")

    fwd_valid = False
    rev_valid = False

    if fwd_seq and re.match(r"^[ACGT]+$", fwd_seq):
        if len_min <= len(fwd_seq) <= len_max:
            fwd_valid = True
            c4 += 7
            feedback_parts.append(
                f"Forward primer valid DNA, {len(fwd_seq)}bp (+7)"
            )
        elif len(fwd_seq) >= 15:
            c4 += 4
            feedback_parts.append(
                f"Forward primer DNA but length {len(fwd_seq)} outside {len_min}-{len_max} (+4)"
            )
    elif fwd_seq:
        c4 += 2
        feedback_parts.append("Forward primer has non-DNA characters (+2)")

    if rev_seq and re.match(r"^[ACGT]+$", rev_seq):
        if len_min <= len(rev_seq) <= len_max:
            rev_valid = True
            c4 += 6
            feedback_parts.append(
                f"Reverse primer valid DNA, {len(rev_seq)}bp (+6)"
            )
        elif len(rev_seq) >= 15:
            c4 += 3
            feedback_parts.append(
                f"Reverse primer DNA but length {len(rev_seq)} outside range (+3)"
            )
    elif rev_seq:
        c4 += 1
        feedback_parts.append("Reverse primer has non-DNA characters (+1)")

    score += c4
    subscores["primer_sequences"] = c4

    # --- Criterion 5: Primers have Tm values (10 pts) ---
    c5 = 0
    tm_min = gt.get("valid_tm_min", 50.0)
    tm_max = gt.get("valid_tm_max", 70.0)

    fwd_tm_str = result.get("forward_tm", "")
    rev_tm_str = result.get("reverse_tm", "")

    for label, tm_str in [("Forward", fwd_tm_str), ("Reverse", rev_tm_str)]:
        if tm_str:
            try:
                tm_val = float(tm_str)
                if tm_min <= tm_val <= tm_max:
                    c5 += 5
                    feedback_parts.append(f"{label} Tm={tm_val}°C valid (+5)")
                else:
                    c5 += 2
                    feedback_parts.append(
                        f"{label} Tm={tm_val}°C outside {tm_min}-{tm_max} range (+2)"
                    )
            except ValueError:
                c5 += 1
                feedback_parts.append(f"{label} Tm present but not parseable (+1)")

    score += c5
    subscores["primer_tm"] = c5

    # --- Criterion 6: Amplicon size specified (10 pts) ---
    c6 = 0
    amp_str = result.get("amplicon_size", "")
    amp_min = gt.get("valid_amplicon_min", 100)
    amp_max = gt.get("valid_amplicon_max", 600)

    if amp_str:
        try:
            amp_val = int(amp_str)
            if amp_min <= amp_val <= amp_max:
                c6 = 10
                feedback_parts.append(f"Amplicon size {amp_val}bp valid (+10)")
            else:
                c6 = 5
                feedback_parts.append(
                    f"Amplicon {amp_val}bp outside {amp_min}-{amp_max} range (+5)"
                )
        except ValueError:
            c6 = 3
            feedback_parts.append("Amplicon size present but not parseable (+3)")
    else:
        feedback_parts.append("Amplicon size not specified (0)")
    score += c6
    subscores["amplicon_size"] = c6

    # --- Criterion 7: Specificity report exists (15 pts) ---
    c7 = 0
    if result.get("report_exists", False):
        c7 += 3
        if result.get("report_has_vregion", False):
            c7 += 4
            feedback_parts.append("Report discusses variable region (+4)")
        if result.get("report_has_srb", False):
            c7 += 4
            feedback_parts.append("Report mentions SRB/Desulfovibrio (+4)")
        if result.get("report_has_specificity", False):
            c7 += 4
            feedback_parts.append("Report discusses primer specificity (+4)")
        if c7 == 3:
            feedback_parts.append("Report exists but missing key content (+3)")
    else:
        feedback_parts.append("Specificity report MISSING (0)")
    c7 = min(c7, 15)
    score += c7
    subscores["specificity_report"] = c7

    # --- Criterion 8: Report has PCR conditions (15 pts) ---
    c8 = 0
    if result.get("report_has_pcr_conditions", False):
        c8 += 8
        feedback_parts.append("Report includes PCR conditions (+8)")
        if result.get("report_has_annealing_temp", False):
            c8 += 7
            feedback_parts.append("Report specifies annealing temperature (+7)")
    else:
        feedback_parts.append("Report missing PCR conditions (0)")
    score += c8
    subscores["pcr_conditions"] = c8

    score = min(score, 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "subscores": subscores,
    }
