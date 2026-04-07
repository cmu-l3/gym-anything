#!/usr/bin/env python3
"""
Verifier for 16S rRNA Sanger Read Contig Assembly task.

Multi-Criteria Verification:
1. Output files exist and were created during the task (Anti-gaming)
2. Assembled consensus FASTA length is biologically valid (~1541 bp)
3. Assembly accuracy verified by checking specific overlapping k-mers.
4. Report file mentions required assembly metrics (3 reads, length, reversed read).
5. VLM trajectory verification ensures UGENE's UI tools were used.
"""

import os
import json
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_16s_sanger_contig_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # Paths in container
    fasta_path = metadata.get('expected_consensus_path', '/home/ga/UGENE_Data/16s_assembly/results/16s_consensus.fasta')
    report_path = metadata.get('expected_report_path', '/home/ga/UGENE_Data/16s_assembly/results/assembly_report.txt')

    # Copy metadata JSON
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # 1. Existence and Timestamps (15 points)
    if not result_meta.get('consensus_exists'):
        return {"passed": False, "score": 0, "feedback": "Consensus FASTA was not created."}
        
    if result_meta.get('consensus_created_during_task'):
        score += 10
    else:
        feedback_parts.append("Warning: FASTA not created during task window (Anti-gaming check).")
        
    if result_meta.get('report_exists'):
        score += 5

    # 2 & 3. Evaluate FASTA (Length: 25 pts, K-mers: 25 pts)
    temp_fasta = tempfile.NamedTemporaryFile(delete=False, suffix='.fasta')
    fasta_seq = ""
    try:
        copy_from_env(fasta_path, temp_fasta.name)
        with open(temp_fasta.name, 'r') as f:
            lines = f.readlines()
            fasta_seq = "".join([l.strip().upper() for l in lines if not l.startswith(">")])
    except Exception as e:
        feedback_parts.append(f"Could not read FASTA file: {e}")
    finally:
        if os.path.exists(temp_fasta.name):
            os.unlink(temp_fasta.name)

    fasta_length = len(fasta_seq)
    len_min = metadata.get('expected_length_min', 1500)
    len_max = metadata.get('expected_length_max', 1560)

    if fasta_length == 0:
        feedback_parts.append("FASTA file is empty.")
    else:
        # Check Length
        if len_min <= fasta_length <= len_max:
            score += 25
            feedback_parts.append(f"Correct assembly length ({fasta_length} bp).")
        else:
            feedback_parts.append(f"Invalid assembly length ({fasta_length} bp, expected ~1541 bp).")
            
        # Check K-mers to prove true overlapping assembly
        # Kmer 1: Spans Read 1 and Read 2 junction (~bp 730-770)
        kmer1 = "TTAATCGGAATTACTGGGCGTAAAGCGCACGCAGGCGGTT"
        # Kmer 2: Spans Read 2 and Read 3 junction (~bp 1280-1320)
        kmer2 = "AGCGACCTCGCGAGAGCAAGCGGACCTCATAAAGTGCGTC"
        
        # Depending on the aligner used, the consensus might have slight variations (Ns or gaps)
        # We allow a very basic substring check or high match rate
        if kmer1 in fasta_seq and kmer2 in fasta_seq:
            score += 25
            feedback_parts.append("Accurate sequence merging verified (Junction k-mers found).")
        elif kmer1 in fasta_seq or kmer2 in fasta_seq:
            score += 10
            feedback_parts.append("Partial assembly detected (Only 1 junction k-mer found).")
        else:
            feedback_parts.append("Junction k-mers missing. Reads may be concatenated instead of assembled.")

    # 4. Evaluate Report (20 points)
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_content = ""
    if result_meta.get('report_exists'):
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read().lower()
        except Exception:
            pass
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

        r_score = 0
        if "3" in report_content or "three" in report_content:
            r_score += 5
        if str(fasta_length) in report_content:
            r_score += 5
        if "read_2" in report_content or "reverse" in report_content:
            r_score += 10
        score += r_score
        feedback_parts.append(f"Report evaluation: {r_score}/20 points.")

    # 5. VLM Trajectory Evaluation (15 points)
    # Check if UGENE's tools were actually used vs scripting bypassing the GUI
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and len(traj) > 0:
        # Extract frames manually as robust fallback
        frames = []
        step = max(1, len(traj) // 5)
        for i in range(0, len(traj), step):
            if 'observation' in traj[i] and 'image' in traj[i]['observation']:
                frames.append(traj[i]['observation']['image'])
        frames = frames[:5]
        
        prompt = """Examine these trajectory screenshots from a bioinformatics agent task.
Task: Assemble overlapping DNA sequencing reads into a contig.
Check if the agent used UGENE's graphical UI for this task. 
Do you see UGENE's Assembly Editor, Contig Editor, or read alignment windows being used?
Respond in JSON format:
{
    "used_ui_assembly": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief reason"
}
"""
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get('success') and vlm_resp.get('parsed', {}).get('used_ui_assembly'):
                vlm_score = 15
                feedback_parts.append("VLM verified UGENE Assembly UI usage (+15).")
            else:
                feedback_parts.append("VLM did not verify Assembly UI usage.")
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")
    else:
        feedback_parts.append("VLM verification skipped/unavailable.")
        
    score += vlm_score

    # Final determination
    # Key criteria: Length must be correct AND junction k-mers found to prove true assembly
    key_criteria_met = (len_min <= fasta_length <= len_max) and (kmer1 in fasta_seq or kmer2 in fasta_seq)
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }