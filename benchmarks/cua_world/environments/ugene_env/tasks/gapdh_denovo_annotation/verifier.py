#!/usr/bin/env python3
"""
Verifier for GAPDH De Novo Annotation task.
Evaluates the exported GenBank file, protein FASTA, and summary report.
Utilizes VLM trajectory verification as an additional signal to prevent gaming.
"""

import os
import re
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gapdh_denovo_annotation(traj, env_info, task_info):
    """
    Verify GAPDH de novo annotation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_prot_len = metadata.get('min_protein_length', 300)
    max_prot_len = metadata.get('max_protein_length', 370)

    # 1. Read exported result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    gb_info = result.get('genbank', {})
    prot_info = result.get('protein', {})
    rep_info = result.get('report', {})

    # =================================================================
    # Anti-gaming checks (files must be created during task)
    # =================================================================
    if gb_info.get('exists') and not gb_info.get('created_during_task'):
        feedback_parts.append("WARNING: GenBank file predates task start.")
    if prot_info.get('exists') and not prot_info.get('created_during_task'):
        feedback_parts.append("WARNING: Protein file predates task start.")

    # =================================================================
    # CRITERION 1: GenBank File (20 pts)
    # =================================================================
    if gb_info.get('exists') and gb_info.get('created_during_task'):
        content = gb_info.get('content', '')
        
        has_locus = bool(re.search(r'LOCUS\s+', content))
        has_origin = 'ORIGIN' in content or 'origin' in content.lower()
        has_features = 'FEATURES' in content or 'features' in content.lower()
        
        if has_locus and (has_origin or has_features):
            score += 10
            feedback_parts.append("GenBank file exists and is valid (+10)")
            
            # Check for annotations (ORF, CDS, etc.)
            orf_patterns = [r'\/label.*[Oo][Rr][Ff]', r'CDS\s+', r'ORF', r'misc_feature']
            has_annots = any(re.search(p, content) for p in orf_patterns)
            
            if has_annots:
                score += 10
                feedback_parts.append("GenBank contains ORF/feature annotations (+10)")
            else:
                feedback_parts.append("GenBank missing annotations")
        else:
            feedback_parts.append("GenBank file malformed")
    else:
        feedback_parts.append("GenBank file missing")

    # =================================================================
    # CRITERION 2: Protein FASTA (30 pts)
    # =================================================================
    prot_seq = ""
    if prot_info.get('exists') and prot_info.get('created_during_task'):
        content = prot_info.get('content', '').strip()
        if content.startswith('>'):
            score += 10
            feedback_parts.append("Protein FASTA exists (+10)")
            
            # Extract actual sequence
            lines = content.split('\n')
            prot_seq = "".join(l.strip() for l in lines if not l.startswith('>'))
            
            # Check for valid AA
            invalid_chars = set(prot_seq.upper()) - set("ACDEFGHIKLMNPQRSTVWY*")
            if not invalid_chars and prot_seq:
                score += 5
                feedback_parts.append("Protein sequence has valid characters (+5)")
                
                # Check length
                prot_len = len(prot_seq.replace('*', ''))
                if min_prot_len <= prot_len <= max_prot_len:
                    score += 10
                    feedback_parts.append(f"Protein length ({prot_len} aa) is correct (+10)")
                else:
                    feedback_parts.append(f"Protein length ({prot_len} aa) incorrect (expected {min_prot_len}-{max_prot_len})")
                    
                # Check starts with M
                if prot_seq.upper().startswith('M'):
                    score += 5
                    feedback_parts.append("Protein starts with Methionine (+5)")
                else:
                    feedback_parts.append("Protein does not start with Methionine")
            else:
                feedback_parts.append(f"Protein sequence invalid (chars: {invalid_chars})")
        else:
            feedback_parts.append("Protein file is not valid FASTA")
    else:
        feedback_parts.append("Protein FASTA missing")

    # =================================================================
    # CRITERION 3: Summary Report (30 pts)
    # =================================================================
    if rep_info.get('exists') and rep_info.get('created_during_task'):
        score += 5
        feedback_parts.append("Report file exists (+5)")
        content = rep_info.get('content', '')
        
        # Check ORF mention
        if re.search(r'[Oo][Rr][Ff]', content) and re.search(r'\d+', content):
            score += 5
            feedback_parts.append("Report discusses ORFs (+5)")
            
        # Check Kozak mention
        if re.search(r'[Kk]ozak|CCATG', content):
            score += 10
            feedback_parts.append("Report discusses Kozak motif (+10)")
            
        # Check Poly-A mention
        if re.search(r'AATAAA|[Pp]oly[- ]?[Aa]', content, re.IGNORECASE):
            score += 10
            feedback_parts.append("Report discusses poly-A signal (+10)")
    else:
        feedback_parts.append("Report file missing")

    # =================================================================
    # CRITERION 4: VLM Trajectory Verification (20 pts)
    # =================================================================
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        all_frames = frames + [final] if final else frames
        
        if all_frames:
            prompt = """Analyze these screenshots of a user interacting with UGENE bioinformatics software.
Did the user perform sequence analysis tasks such as:
1. Finding Open Reading Frames (ORFs)
2. Translating sequences
3. Searching for patterns/motifs
4. Using the UGENE Sequence View or ORF Marker plugin?

Respond in JSON format:
{
    "used_ugene_tools": true/false,
    "found_orfs": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
            
            vlm_res = query_vlm(images=all_frames, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_ugene_tools"):
                    vlm_score += 10
                if parsed.get("found_orfs"):
                    vlm_score += 10
                    
                if vlm_score > 0:
                    feedback_parts.append(f"VLM verified trajectory (+{vlm_score})")
                else:
                    feedback_parts.append("VLM did not detect expected sequence analysis workflow")
            else:
                # Fallback if VLM fails but programmatic passes
                vlm_score = 20 if score >= 40 else 0
                feedback_parts.append("VLM query failed, granted fallback VLM score based on programmatic success.")
        else:
            vlm_score = 20 if score >= 40 else 0
            feedback_parts.append("No screenshots for VLM, granted fallback VLM score based on programmatic success.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_score = 20 if score >= 40 else 0
        feedback_parts.append("VLM error, granted fallback VLM score based on programmatic success.")
        
    score += vlm_score

    # Evaluate pass condition
    # Requires minimum 60 score, AND GenBank + Protein files must exist and be valid
    essential_files = gb_info.get('exists') and prot_info.get('exists')
    passed = score >= 60 and essential_files

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }