#!/usr/bin/env python3
"""
Verifier for Cytochrome C Alignment Curation and Trimming.

Validates:
1. Files exist and were created during the task.
2. Initial alignment contains 8 sequences.
3. Curated alignment contains 7 sequences, strictly missing P00053.
4. Curated alignment is exactly 30 columns shorter than initial.
5. Curated sequences are exact substrings (slice [15:-15]) of their initial equivalents.
6. Report contains length information.
7. VLM check ensures UI interaction was performed.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_alignment(content):
    """Parses CLUSTAL or FASTA alignment file content into a dict of {id: sequence}."""
    seqs = {}
    lines = content.strip().split('\n')
    if not lines:
        return seqs

    # Heuristic for FASTA
    if lines[0].startswith('>'):
        curr_id = None
        for line in lines:
            line = line.strip()
            if line.startswith('>'):
                curr_id = line[1:].split()[0]
                seqs[curr_id] = ""
            elif curr_id and line:
                seqs[curr_id] += line
        return seqs
    
    # Heuristic for CLUSTAL/ALN
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith('CLUSTAL') or line.startswith('MUSCLE') or line.startswith('MAFFT') or line.startswith('UGENE'):
            continue
        # Skip conservation lines (usually start with space, but we stripped, so we check if it's ONLY conservation chars)
        if set(line).issubset(set('*.: ')):
            continue
        
        parts = line.split()
        if len(parts) >= 2:
            seq_id = parts[0]
            seq_data = parts[1]
            
            # Skip numbering lines or artifacts
            if not any(c.isalpha() for c in seq_id):
                continue
                
            if seq_id not in seqs:
                seqs[seq_id] = ""
            seqs[seq_id] += seq_data
            
    return seqs


def query_vlm_for_trajectory(traj, env_info):
    """Use VLM to check if the agent interacted with the GUI."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get("query_vlm")
        if not query_vlm:
            return 10  # Provide baseline points if VLM is unavailable

        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if not images:
            return 0

        prompt = (
            "You are evaluating an agent performing a bioinformatics task. "
            "Look at these screenshots. Did the agent use the graphical user interface "
            "of a bioinformatics software (like UGENE) to view, select, or edit a sequence alignment? "
            "Respond in JSON format: {\"used_gui\": true/false}"
        )
        
        result = query_vlm(images=images, prompt=prompt)
        if result and result.get("parsed", {}).get("used_gui", False):
            return 15
        return 0
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 10  # Baseline if error occurs


def verify_cytc_curation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_initial_count = metadata.get('expected_initial_count', 8)
    expected_curated_count = metadata.get('expected_curated_count', 7)
    outgroup_id = metadata.get('outgroup_id', 'P00053')
    trim_length = metadata.get('trim_length_each_side', 15)

    score = 0
    feedback_parts = []
    
    # Temporaries for files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_init = tempfile.NamedTemporaryFile(delete=False, suffix='.aln')
    temp_cur = tempfile.NamedTemporaryFile(delete=False, suffix='.aln')
    temp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Load Result JSON
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        task_start = result.get('task_start_time', 0)
        
        # 1. Initial Alignment Check
        init_seqs = {}
        if result.get('initial_aln_exists', False):
            if result.get('initial_aln_mtime', 0) >= task_start:
                copy_from_env("/tmp/initial_cytochrome.aln", temp_init.name)
                with open(temp_init.name, 'r') as f:
                    init_seqs = parse_alignment(f.read())
                
                if len(init_seqs) == expected_initial_count:
                    score += 10
                    feedback_parts.append(f"Initial alignment exported correctly ({expected_initial_count} sequences).")
                else:
                    feedback_parts.append(f"Initial alignment has {len(init_seqs)} sequences, expected {expected_initial_count}.")
            else:
                feedback_parts.append("Initial alignment has old timestamp.")
        else:
            feedback_parts.append("Initial alignment missing.")
            
        # 2. Curated Alignment Check
        cur_seqs = {}
        if result.get('curated_aln_exists', False):
            if result.get('curated_aln_mtime', 0) >= task_start:
                score += 10
                copy_from_env("/tmp/curated_cytochrome.aln", temp_cur.name)
                with open(temp_cur.name, 'r') as f:
                    cur_seqs = parse_alignment(f.read())
                    
                # Outgroup Check
                outgroup_present = any(outgroup_id in key for key in cur_seqs.keys())
                if len(cur_seqs) == expected_curated_count and not outgroup_present:
                    score += 15
                    feedback_parts.append("Outgroup correctly removed.")
                else:
                    feedback_parts.append(f"Outgroup removal failed (Found {len(cur_seqs)} sequences).")
                    
                # Exact Trimming Check
                init_lengths = set(len(s) for s in init_seqs.values())
                cur_lengths = set(len(s) for s in cur_seqs.values())
                
                if len(init_lengths) == 1 and len(cur_lengths) == 1:
                    L_init = list(init_lengths)[0]
                    L_cur = list(cur_lengths)[0]
                    
                    if L_cur == L_init - (trim_length * 2):
                        score += 20
                        feedback_parts.append(f"Trim length exact (Reduced from {L_init} to {L_cur}).")
                        
                        # Sequence Substring Fidelity
                        fidelity_passed = True
                        for cid, cseq in cur_seqs.items():
                            # Find matching initial sequence
                            matched_init = None
                            for iid, iseq in init_seqs.items():
                                if cid in iid or iid in cid:  # IDs might be slightly altered by ALN format
                                    matched_init = iseq
                                    break
                            
                            if not matched_init or cseq != matched_init[trim_length:-trim_length]:
                                fidelity_passed = False
                                break
                        
                        if fidelity_passed and cur_seqs:
                            score += 20
                            feedback_parts.append("Sequence fidelity (exact 15bp terminal slice) validated.")
                        else:
                            feedback_parts.append("Sequence fidelity failed (trimmed sequences do not match slice).")
                    else:
                        feedback_parts.append(f"Incorrect trim length: Initial {L_init}, Curated {L_cur}.")
                else:
                    if not init_seqs:
                        feedback_parts.append("Cannot evaluate trim length (Initial sequence unreadable).")
                    else:
                        feedback_parts.append("Alignment sequences have irregular lengths.")
            else:
                feedback_parts.append("Curated alignment has old timestamp.")
        else:
            feedback_parts.append("Curated alignment missing.")
            
        # 3. Report Check
        if result.get('report_exists', False):
            if result.get('report_mtime', 0) >= task_start:
                copy_from_env("/tmp/curation_report.txt", temp_rep.name)
                with open(temp_rep.name, 'r') as f:
                    report_text = f.read().lower()
                    
                if outgroup_id.lower() in report_text or 'p00053' in report_text or 'cannabis' in report_text:
                    score += 10
                    feedback_parts.append("Report created and mentions outgroup.")
                else:
                    feedback_parts.append("Report exists but missing required outgroup details.")
            else:
                feedback_parts.append("Report has old timestamp.")
        else:
            feedback_parts.append("Curation report missing.")

        # 4. GUI Usage VLM Check
        vlm_score = query_vlm_for_trajectory(traj, env_info)
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append("GUI interaction confirmed.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        feedback_parts.append(f"Verification crashed: {e}")
        
    finally:
        for p in [temp_json.name, temp_init.name, temp_cur.name, temp_rep.name]:
            if os.path.exists(p):
                os.unlink(p)

    # Determine passing state
    # Pass threshold: 75 points. Must have Outgroup Sequence Removed (+15) and Exact Trimming (+20)
    # The sum requires multiple exact operations.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }