#!/usr/bin/env python3
"""Verifier for cross_taxa_consensus_extraction task.

Verifies that the agent:
1. Generated a valid consensus FASTA file.
2. Applied a strict threshold (ambiguity characters present).
3. Generated a report.
4. Correctly calculated alignment length, conserved positions, 
   longest motif, and motif length based on the EXPORTED FASTA.
5. VLM trajectory verification ensures UGENE was used.
"""

import json
import os
import re
import tempfile
import logging
import sys

# Append path to import gym_anything VLM utilities if available
sys.path.insert(0, "/workspace/scripts")
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cross_taxa_consensus(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    # 1. Read the exported JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/cross_taxa_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}"
        }

    # 2. Extract Data
    task_start_ts = result.get("task_start_ts", 0)
    fasta_exists = result.get("fasta_exists", False)
    fasta_mtime = result.get("fasta_mtime", 0)
    fasta_seq = result.get("fasta_seq", "").upper()
    
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    
    # 3. Analyze Ground Truth dynamically from the agent's FASTA
    std_aa = set("ACDEFGHIKLMNPQRSTVWY")
    true_len = len(fasta_seq)
    
    # Ambiguity count (anything that is NOT a standard amino acid, e.g., '?', 'X', '-')
    ambiguity_count = sum(1 for c in fasta_seq if c not in std_aa)
    true_conserved = sum(1 for c in fasta_seq if c in std_aa)
    
    # Find longest motif (continuous block of standard amino acids)
    blocks = re.findall(r'[ACDEFGHIKLMNPQRSTVWY]+', fasta_seq)
    true_longest_motif = max(blocks, key=len) if blocks else ""
    true_longest_len = len(true_longest_motif)
    
    # 4. Scoring Logic
    
    # Criterion 1: FASTA file exists & is valid (15 pts)
    if fasta_exists and true_len > 50:
        score += 15
        feedback_parts.append("FASTA file valid (+15)")
    elif fasta_exists:
        score += 5
        feedback_parts.append("FASTA file exists but invalid/short (+5)")
    else:
        feedback_parts.append("FASTA file MISSING (0)")

    # Early exit if no FASTA or no Report
    if not fasta_exists and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Both required output files are missing."
        }

    # Criterion 2: Strict threshold applied (15 pts)
    # A strict 100% consensus of 8 diverse species MUST have ambiguities
    if fasta_exists and true_len > 50:
        if ambiguity_count > 0:
            score += 15
            feedback_parts.append(f"Strict threshold verified ({ambiguity_count} ambiguities) (+15)")
        else:
            feedback_parts.append("No ambiguities found; strict consensus threshold not applied (0)")

    # Criterion 3: Report exists (10 pts)
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists (+10)")
    else:
        feedback_parts.append("Report file MISSING (0)")
        
    # Criterion 4-7: Extracted metrics from report (40 pts)
    if report_exists and true_len > 50:
        # Check if the report contains the correct values based on the dynamic GT
        
        # A. Alignment length (10 pts)
        if re.search(r'\b' + str(true_len) + r'\b', report_content):
            score += 10
            feedback_parts.append(f"Correct alignment length ({true_len}) (+10)")
        else:
            feedback_parts.append(f"Incorrect/missing alignment length (expected {true_len}) (0)")
            
        # B. Conserved positions count (10 pts)
        if re.search(r'\b' + str(true_conserved) + r'\b', report_content):
            score += 10
            feedback_parts.append(f"Correct conserved count ({true_conserved}) (+10)")
        else:
            feedback_parts.append(f"Incorrect/missing conserved count (expected {true_conserved}) (0)")
            
        # C. Longest motif string (10 pts)
        if true_longest_motif and true_longest_motif in report_content.upper():
            score += 10
            feedback_parts.append(f"Correct longest motif found (+10)")
        else:
            feedback_parts.append(f"Longest motif string missing/incorrect (0)")
            
        # D. Motif length (10 pts)
        if true_longest_len > 0 and re.search(r'\b' + str(true_longest_len) + r'\b', report_content):
            score += 10
            feedback_parts.append(f"Correct motif length ({true_longest_len}) (+10)")
        else:
            feedback_parts.append(f"Motif length missing/incorrect (0)")

    # Criterion 8: VLM Verification of UGENE Trajectory (20 pts)
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Look at these screenshots from a computer agent's task.
            Did the agent use UGENE's UI to perform a multiple sequence alignment (e.g., MUSCLE) 
            AND adjust/export the consensus sequence?
            Look for the alignment editor window, sequence views, and export dialogs.
            
            Respond in JSON:
            {
                "used_ugene_alignment": true/false,
                "exported_consensus": true/false,
                "confidence": "high/medium/low"
            }
            """
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_ugene_alignment") and parsed.get("exported_consensus"):
                    score += 20
                    feedback_parts.append("VLM verified UGENE alignment & consensus workflow (+20)")
                elif parsed.get("used_ugene_alignment"):
                    score += 10
                    feedback_parts.append("VLM verified UGENE alignment but not consensus export (+10)")
                else:
                    feedback_parts.append("VLM did not detect UGENE alignment workflow (0)")
            else:
                feedback_parts.append("VLM query failed (0)")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM check encountered an error (0)")

    # Key criteria: Must have both files and applied strict threshold
    key_criteria_met = fasta_exists and report_exists and (ambiguity_count > 0)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }