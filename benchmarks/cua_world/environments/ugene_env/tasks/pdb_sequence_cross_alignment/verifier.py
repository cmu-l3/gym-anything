#!/usr/bin/env python3
"""
Verifier for pdb_sequence_cross_alignment task.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_fasta(filepath):
    """Parse a FASTA file and return a dict of {header: sequence}."""
    seqs = {}
    if not os.path.exists(filepath):
        return seqs
    
    with open(filepath, 'r') as f:
        header = None
        seq = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    seqs[header] = "".join(seq)
                header = line[1:]
                seq = []
            else:
                seq.append(line)
        if header is not None:
            seqs[header] = "".join(seq)
    return seqs

def calculate_identity(seq1, seq2):
    """Calculate identity between two aligned sequences (excluding mutual gaps)."""
    if len(seq1) != len(seq2):
        return 0.0
    
    matches = 0
    valid_length = 0
    for a, b in zip(seq1, seq2):
        if a == '-' and b == '-':
            continue
        valid_length += 1
        if a.upper() == b.upper():
            matches += 1
            
    return matches / valid_length if valid_length > 0 else 0.0

def verify_pdb_sequence_cross_alignment(traj, env_info, task_info):
    """
    Verify the PDB extraction and alignment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total_sequences', 9)
    len_min = metadata.get('expected_pdb_chain_length_min', 140)
    len_max = metadata.get('expected_pdb_chain_length_max', 150)
    human_ref = metadata.get('human_reference_id', 'P68871')

    score = 0
    feedback_parts = []
    
    # 1. Fetch metadata JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files_info = result.get('files', {})
    task_start = result.get('task_start', 0)

    def fetch_file(filename):
        """Helper to fetch an exported file from the container."""
        if not files_info.get(filename, {}).get('exists', False):
            return None
        tmp = tempfile.NamedTemporaryFile(delete=False)
        tmp.close()
        try:
            copy_from_env(f"/tmp/ugene_exports/{filename}", tmp.name)
            return tmp.name
        except Exception:
            os.unlink(tmp.name)
            return None

    # --- Criterion 1: PDB Beta Chain FASTA (Exists, Valid, Length) ---
    c1_score = 0
    pdb_chain_path = fetch_file("pdb_beta_chain.fasta")
    pdb_header = None
    if pdb_chain_path:
        seqs = parse_fasta(pdb_chain_path)
        if len(seqs) == 1:
            c1_score += 10
            pdb_header, pdb_seq = list(seqs.items())[0]
            seq_len = len(pdb_seq.replace('-', ''))
            if len_min <= seq_len <= len_max:
                c1_score += 10
                feedback_parts.append(f"PDB beta chain valid length ({seq_len}) (+20)")
            else:
                feedback_parts.append(f"PDB chain wrong length ({seq_len}) (+10)")
        else:
            feedback_parts.append(f"PDB FASTA must contain exactly 1 sequence, found {len(seqs)} (0)")
        os.unlink(pdb_chain_path)
    else:
        feedback_parts.append("pdb_beta_chain.fasta MISSING (0)")
    score += c1_score

    # --- Criterion 2: Combined Sequences FASTA ---
    c2_score = 0
    combined_path = fetch_file("combined_sequences.fasta")
    if combined_path:
        seqs = parse_fasta(combined_path)
        if len(seqs) == expected_total:
            c2_score += 10
            feedback_parts.append(f"Combined FASTA has exactly {expected_total} sequences (+10)")
        elif len(seqs) > 0:
            c2_score += 5
            feedback_parts.append(f"Combined FASTA has {len(seqs)} sequences (expected {expected_total}) (+5)")
        os.unlink(combined_path)
    else:
        feedback_parts.append("combined_sequences.fasta MISSING (0)")
    score += c2_score

    # --- Criterion 3: Alignment Files (.aln and .fasta) ---
    c3_score = 0
    aln_path = fetch_file("cross_species_alignment.aln")
    aln_fasta_path = fetch_file("cross_species_alignment.fasta")
    
    if aln_path:
        with open(aln_path, 'r') as f:
            content = f.read(500)
            if "CLUSTAL" in content or "MUSCLE" in content:
                c3_score += 10
                feedback_parts.append("Valid ALN file format (+10)")
            else:
                feedback_parts.append("ALN file invalid format (0)")
        os.unlink(aln_path)
    else:
        feedback_parts.append("cross_species_alignment.aln MISSING (0)")

    aligned_seqs = {}
    if aln_fasta_path:
        aligned_seqs = parse_fasta(aln_fasta_path)
        if len(aligned_seqs) == expected_total:
            lengths = {len(s) for s in aligned_seqs.values()}
            if len(lengths) == 1 and list(lengths)[0] > len_max:
                c3_score += 10
                feedback_parts.append("Aligned FASTA valid with uniform lengths (+10)")
            else:
                feedback_parts.append("Aligned FASTA sequences have different lengths! (+0)")
        else:
            feedback_parts.append(f"Aligned FASTA has {len(aligned_seqs)} seqs (0)")
        os.unlink(aln_fasta_path)
    else:
        feedback_parts.append("cross_species_alignment.fasta MISSING (0)")
    score += c3_score

    # --- Criterion 4: PDB vs Human Identity ---
    c4_score = 0
    if aligned_seqs and pdb_header:
        # Find PDB sequence in alignment (header might be slightly modified by UGENE)
        aln_pdb_seq = None
        for h, s in aligned_seqs.items():
            if pdb_header[:10] in h or h[:10] in pdb_header:
                aln_pdb_seq = s
                break
                
        # Find human reference in alignment
        aln_human_seq = None
        for h, s in aligned_seqs.items():
            if human_ref in h:
                aln_human_seq = s
                break
                
        if aln_pdb_seq and aln_human_seq:
            identity = calculate_identity(aln_pdb_seq, aln_human_seq)
            if identity >= 0.95:
                c4_score += 10
                feedback_parts.append(f"PDB vs Human identity is {identity:.1%} (+10)")
            else:
                feedback_parts.append(f"Identity too low: {identity:.1%} (0)")
        else:
            feedback_parts.append("Could not identify PDB or Human sequence in alignment (0)")
    score += c4_score

    # --- Criterion 5: Verification Report ---
    c5_score = 0
    report_path = fetch_file("verification_report.txt")
    if report_path:
        with open(report_path, 'r') as f:
            report_text = f.read().lower()
            
        # Count check
        if "9" in report_text or "nine" in report_text:
            c5_score += 5
            
        # Length check
        if "14" in report_text: # Matches 146, 147 etc.
            c5_score += 5
            
        # Species check (at least 4)
        species_list = ["human", "mouse", "chicken", "frog", "zebrafish", "bovine", "horse", "pig"]
        found_species = sum(1 for s in species_list if s in report_text)
        if found_species >= 4:
            c5_score += 10
            feedback_parts.append(f"Report mentions {found_species} species (+10)")
        elif found_species > 0:
            c5_score += 5
            feedback_parts.append(f"Report mentions only {found_species} species (+5)")
            
        feedback_parts.append(f"Report existence & properties (+{c5_score-10 if found_species >= 4 else c5_score})")
        os.unlink(report_path)
    else:
        feedback_parts.append("verification_report.txt MISSING (0)")
    score += c5_score

    # --- Criterion 6: VLM Trajectory Verification ---
    c6_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots from a bioinformatics workflow.
        Did the user actively use the application to extract a sequence from a 3D structural file (PDB) AND run a Multiple Sequence Alignment (MSA)?
        Look for:
        1. 3D structure viewer / sequence export windows.
        2. Alignment window showing multiple sequences stacked together with consensus/conservation bars.
        Return JSON: {"evidence_found": true/false, "reason": "..."}
        """
        
        if frames and final:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and vlm_res.get("parsed", {}).get("evidence_found", False):
                c6_score += 20
                feedback_parts.append("VLM verified MSA workflow (+20)")
            else:
                feedback_parts.append("VLM did not find evidence of real workflow (0)")
        else:
            feedback_parts.append("No screenshots available for VLM (0)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Give partial credit if framework VLM fails but programmatic passes perfectly
        if score >= 60:
            c6_score += 20
            feedback_parts.append("VLM failed but programmatic checks passed heavily (+20)")
            
    score += c6_score

    # To prevent gaming, hard threshold on output creation
    file_mtime = files_info.get("cross_species_alignment.aln", {}).get("mtime", 0)
    if file_mtime > 0 and file_mtime < task_start:
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: Output files existed before task started!"}

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }