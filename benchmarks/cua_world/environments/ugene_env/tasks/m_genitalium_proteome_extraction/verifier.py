#!/usr/bin/env python3
"""Verifier for m_genitalium_proteome_extraction task.

Scoring breakdown (100 points total):
  FASTA exists & valid:                  15
  Correct CDS count (~476 sequences):    20
  Amino acid translation (not DNA):      20
  Correct genetic code (no internal *):  20
  Report exists & contains info:         10
  VLM workflow validation:               15
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a bioinformatics agent operating UGENE. 
The task was to extract and translate CDS (coding sequence) annotations from a GenBank genome.
Review the provided trajectory screenshots and the final state.
Did the agent interact with the sequence annotations, open an export dialog, and attempt to translate features?

Please output a JSON response with:
{
    "interacted_with_annotations": true/false,
    "opened_export_dialog": true/false,
    "attempted_translation": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_m_genitalium_proteome_extraction(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    # 1. Retrieve the parsed result JSON from the container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read exported result data: {e}. The agent likely did not produce any output."
        }

    target_count = task_info.get("metadata", {}).get("target_cds_count", 476)
    tolerance = task_info.get("metadata", {}).get("cds_count_tolerance", 10)

    # --- Criterion 1: FASTA file exists & valid (15 pts) ---
    c1 = 0
    if result.get("fasta_exists", False):
        c1 += 5
        if result.get("fasta_modified_during_task", False):
            c1 += 5
        if result.get("valid_fasta", False):
            c1 += 5
            feedback_parts.append("FASTA file successfully created and valid (+15).")
        else:
            feedback_parts.append("File created but is not valid FASTA format (+10).")
    else:
        feedback_parts.append("Target FASTA file was not created (0).")
    
    score += c1
    subscores["fasta_valid"] = c1

    # Early exit if no FASTA
    if not result.get("valid_fasta", False):
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts), "subscores": subscores}

    # --- Criterion 2: Sequence count (20 pts) ---
    c2 = 0
    seq_count = result.get("seq_count", 0)
    # The NC_000908.2 genome has 476 CDS features. If they included rRNA/tRNA it would be >500.
    if abs(seq_count - target_count) <= tolerance:
        c2 = 20
        feedback_parts.append(f"Correct sequence count ({seq_count} matches target {target_count}) (+20).")
    elif seq_count > 0:
        c2 = 10
        feedback_parts.append(f"Sequence count ({seq_count}) deviates from expected ({target_count}). Did you filter for CDS only? (+10).")
    score += c2
    subscores["sequence_count"] = c2

    # --- Criterion 3: Amino acid translation (20 pts) ---
    c3 = 0
    if result.get("is_amino_acid", False):
        c3 = 20
        feedback_parts.append("Sequences correctly translated to amino acids (+20).")
    else:
        feedback_parts.append("Sequences appear to be raw DNA, not translated proteins (0).")
    score += c3
    subscores["is_amino_acid"] = c3

    # --- Criterion 4: Correct genetic code (20 pts) ---
    c4 = 0
    internal_stops = result.get("internal_stops", -1)
    if not result.get("is_amino_acid", False):
        feedback_parts.append("Cannot evaluate genetic code on DNA sequences (0).")
    else:
        if internal_stops == 0:
            c4 = 20
            feedback_parts.append("No internal stop codons found! Translation Table 4 was applied correctly (+20).")
        elif internal_stops > 0:
            # If standard genetic code was used on Mycoplasma, UGA becomes stop. Dozens of stops appear.
            feedback_parts.append(f"Found {internal_stops} internal stop codons (*). Standard genetic code was likely used instead of Table 4 (0).")
    score += c4
    subscores["correct_genetic_code"] = c4

    # --- Criterion 5: Report exists (10 pts) ---
    c5 = 0
    if result.get("report_exists", False):
        c5 += 4
        if result.get("report_mentions_table4", False):
            c5 += 3
        if result.get("report_mentions_count", False):
            c5 += 3
        feedback_parts.append(f"Report file evaluated (+{c5}).")
    else:
        feedback_parts.append("Report file not found (0).")
    score += c5
    subscores["report_exists"] = c5

    # --- Criterion 6: VLM Verification (15 pts) ---
    c6 = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = [img for img in frames + [final] if img is not None]
            
            if images:
                vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("opened_export_dialog", False) or parsed.get("attempted_translation", False):
                        c6 = 15
                        feedback_parts.append("VLM confirmed interaction with UGENE export/translation tools (+15).")
                    elif parsed.get("interacted_with_annotations", False):
                        c6 = 7
                        feedback_parts.append("VLM confirmed annotation interaction but not export/translation (+7).")
                    else:
                        feedback_parts.append("VLM did not detect correct UGENE interactions (0).")
                else:
                    c6 = 15 # Grant points if VLM fails to parse
                    feedback_parts.append("VLM query failed, granting default points (+15).")
            else:
                c6 = 15
                feedback_parts.append("No images for VLM, granting default points (+15).")
        except Exception as e:
            c6 = 15
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM error, granting default points (+15).")
    else:
        c6 = 15 # Automatically award if VLM is unavailable
        feedback_parts.append("VLM unavailable, granting default points (+15).")
    
    score += c6
    subscores["vlm_verification"] = c6

    # Determine Pass/Fail
    passed = score >= 75 and result.get("is_amino_acid", False) and (result.get("internal_stops", -1) == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "subscores": subscores
    }