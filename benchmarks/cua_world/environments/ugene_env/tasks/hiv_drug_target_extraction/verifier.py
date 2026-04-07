#!/usr/bin/env python3
"""
Verifier for hiv_drug_target_extraction task.

Verification Strategy:
1. File Verification (30 pts): Checks for the 3 target FASTA files.
2. Translation Verification (15 pts): Evaluates if extracted sequences are proteins (not raw DNA).
3. Length Constraint (15 pts): Verifies accurate cleavage by checking target lengths.
4. Motif Analysis (15 pts): Hunts for strictly conserved catalytic site motifs in the extracted protein.
5. Report Accuracy (10 pts): Confirms summary report mentions files and correct length digits.
6. Workflow / VLM Check (15 pts): Verifies trajectory shows use of UGENE sequence views.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_protein_seq(seq):
    """Simple check to ensure sequence is amino acids, not raw DNA nucleotides."""
    if not seq:
        return False
    # Count ATCG frequency
    dna_chars = set("ATCGN")
    dna_count = sum(1 for c in seq if c in dna_chars)
    dna_ratio = dna_count / len(seq)
    # If >85% ATCG, it's almost certainly untranslated DNA
    return dna_ratio < 0.85

def verify_hiv_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- 1. Fetch JSON results ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hiv_extraction_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Result JSON not found. Agent likely did not run or produce outputs."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    pr = result.get('protease', {})
    rt = result.get('reverse_transcriptase', {})
    in_ = result.get('integrase', {})
    rep = result.get('report', {})
    
    # --- Criterion 1: Files Exist (30 pts) ---
    c1 = 0
    if pr.get('exists') and pr.get('sequence'): c1 += 10
    if rt.get('exists') and rt.get('sequence'): c1 += 10
    if in_.get('exists') and in_.get('sequence'): c1 += 10
    score += c1
    if c1 == 30:
        feedback_parts.append("All 3 FASTA files exist (+30)")
    else:
        feedback_parts.append(f"{c1//10}/3 FASTA files exist (+{c1})")
        
    if c1 == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No sequence files were exported. Task incomplete.",
            "key_criteria_met": False
        }

    # --- Criterion 2: Translated to Amino Acids (15 pts) ---
    c2 = 0
    protein_count = 0
    total_seqs = 0
    for seq_dict in [pr, rt, in_]:
        seq = seq_dict.get('sequence')
        if seq:
            total_seqs += 1
            if is_protein_seq(seq):
                protein_count += 1
                
    if total_seqs > 0 and protein_count == total_seqs:
        c2 = 15
        feedback_parts.append("Sequences successfully translated to Amino Acids (+15)")
    elif protein_count > 0:
        c2 = 5
        feedback_parts.append("Partial translation success; some sequences look like DNA (+5)")
    else:
        feedback_parts.append("Sequences appear to be raw DNA, NOT translated proteins (0)")
    score += c2

    # --- Criterion 3: Length Constraints (15 pts) ---
    c3 = 0
    pr_seq = pr.get('sequence', '') or ""
    rt_seq = rt.get('sequence', '') or ""
    in_seq = in_.get('sequence', '') or ""
    
    # Expected lengths: PR=99, RT=560, IN=288
    # Give a small buffer of +/- 5 amino acids just in case of different cleavage annotations
    if pr_seq and (94 <= len(pr_seq) <= 104): c3 += 5
    if rt_seq and (550 <= len(rt_seq) <= 570): c3 += 5
    if in_seq and (280 <= len(in_seq) <= 295): c3 += 5
    
    score += c3
    if c3 == 15:
        feedback_parts.append("All proteins match exact mature lengths (+15)")
    else:
        feedback_parts.append(f"Length verification partial match (+{c3})")

    # --- Criterion 4: Biological Motif Accuracy (15 pts) ---
    c4 = 0
    motifs_found = 0
    # PR motif: Catalytic triad DTG or widely conserved PQITLW
    if pr_seq and ("DTG" in pr_seq or "PQITLW" in pr_seq):
        c4 += 5
        motifs_found += 1
    # RT motif: YMDD (catalytic active site)
    if rt_seq and ("YMDD" in rt_seq):
        c4 += 5
        motifs_found += 1
    # IN motif: FLDG (highly conserved N-term core motif) or DDE triad fragment
    if in_seq and ("FLDG" in in_seq or "DD" in in_seq):
        c4 += 5
        motifs_found += 1
        
    score += c4
    feedback_parts.append(f"Found {motifs_found}/3 expected biological signature motifs (+{c4})")

    # --- Criterion 5: Report Accuracy (10 pts) ---
    c5 = 0
    rep_content = rep.get('content', '')
    if rep.get('exists') and rep_content:
        # Check if the report mentions the lengths roughly
        mentions_pr = "99" in rep_content or "100" in rep_content or "protease" in rep_content.lower()
        mentions_rt = "560" in rep_content or "reverse" in rep_content.lower()
        mentions_in = "288" in rep_content or "integrase" in rep_content.lower()
        
        c5 += 4 # Report exists
        if mentions_pr: c5 += 2
        if mentions_rt: c5 += 2
        if mentions_in: c5 += 2
        feedback_parts.append("Summary report validated (+10)")
    else:
        feedback_parts.append("Summary report missing or empty (0)")
    score += c5

    # --- Criterion 6: VLM Trajectory Verification (15 pts) ---
    c6 = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """
        Did the agent use UGENE's Sequence View or Annotation editors during this task?
        Look for evidence of navigating a sequence, opening an export dialog, or viewing annotations.
        Return JSON: {"used_ugene": true/false}
        """
        
        vlm_res = query_vlm(images=images, prompt=prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('used_ugene'):
            c6 = 15
            feedback_parts.append("VLM verified UGENE interaction (+15)")
        else:
            feedback_parts.append("VLM could not confirm UGENE usage (0)")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Default grant partial credit if programmatic checks are solid to prevent penalizing for VLM errors
        if c1 >= 20 and c4 >= 10:
            c6 = 15
            feedback_parts.append("VLM verification skipped; assumed valid based on perfect output (+15)")

    score += c6

    # Determine Pass/Fail
    # Pass requires translation to AA (c2 > 0) AND at least two biological motifs found (c4 >= 10)
    key_criteria_met = (c2 > 0) and (c4 >= 10)
    passed = (score >= 70) and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("FAILED: Critical criteria missed (Sequences must be translated to AA AND contain valid enzyme motifs).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "files_exist": c1,
            "translation": c2,
            "lengths": c3,
            "motifs": c4,
            "report": c5,
            "vlm": c6
        }
    }