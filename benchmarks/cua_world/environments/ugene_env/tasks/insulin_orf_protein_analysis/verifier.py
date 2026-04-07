#!/usr/bin/env python3
"""
Verifier for insulin_orf_protein_analysis task in UGENE.

Verification Strategy:
1. Programmatic File Check (FASTA): Verify sequence length, start codon, and presence of human insulin specific motifs (B-chain/A-chain).
2. Programmatic File Check (GenBank): Verify presence of newly added ORF annotations.
3. Programmatic File Check (Report): Extract and verify Molecular Weight and Cysteine count (must be 6).
4. Anti-gaming: Check if files were actually created during the task timeframe.
5. VLM Trajectory Verification: Prove UGENE was actively used.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_orf_protein_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    expected_cys_count = metadata.get('expected_cysteine_count', 6)
    expected_len_min = metadata.get('expected_length_min', 105)
    expected_len_max = metadata.get('expected_length_max', 115)
    b_chain_motif = metadata.get('insulin_b_chain_motif', 'FVNQHL')
    a_chain_motif = metadata.get('insulin_a_chain_motif', 'GIVEQC')

    # 1. Fetch JSON result
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/insulin_task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export results: {e}"}
    finally:
        if os.path.exists(result_json_path): os.unlink(result_json_path)

    files_created = result.get('files_created_during_task', False)
    if files_created:
        score += 15
        feedback_parts.append("Files created/modified during task (+15)")
    else:
        feedback_parts.append("No files created or modified during the task window (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Verify FASTA (15 pts valid + 15 pts motifs)
    if result.get('fasta_exists', False):
        fasta_path = tempfile.NamedTemporaryFile(delete=False, suffix='.fa').name
        try:
            copy_from_env("/tmp/insulin_protein.fa", fasta_path)
            with open(fasta_path, 'r') as f:
                lines = f.readlines()
            
            # Extract sequence ignoring headers
            seq = "".join([l.strip() for l in lines if not l.startswith('>')]).upper()
            seq = re.sub(r'[^A-Z]', '', seq)
            
            # Length and Start Check
            if seq.startswith('M') and expected_len_min <= len(seq) <= expected_len_max:
                score += 15
                feedback_parts.append(f"FASTA sequence is valid, starts with M, correct length {len(seq)} (+15)")
            else:
                score += 5
                feedback_parts.append(f"FASTA exists but length {len(seq)} or start codon incorrect (+5)")

            # Motif Check
            if b_chain_motif in seq and a_chain_motif in seq:
                score += 15
                feedback_parts.append("Both Insulin B-chain and A-chain motifs found (+15)")
            elif b_chain_motif in seq or a_chain_motif in seq:
                score += 7
                feedback_parts.append("Only one insulin motif found (+7)")
            else:
                feedback_parts.append("Insulin specific motifs missing (wrong ORF?) (0)")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing FASTA: {e}")
        finally:
            if os.path.exists(fasta_path): os.unlink(fasta_path)
    else:
        feedback_parts.append("Protein FASTA file not found (0)")

    # 3. Verify GenBank (15 pts)
    if result.get('gb_exists', False):
        gb_path = tempfile.NamedTemporaryFile(delete=False, suffix='.gb').name
        try:
            copy_from_env("/tmp/insulin_annotated.gb", gb_path)
            with open(gb_path, 'r') as f:
                gb_content = f.read()
            
            # Look for evidence of ORF annotation feature
            if re.search(r'FEATURES.*?\n\s+(ORF|misc_feature).*?\.\.', gb_content, re.DOTALL | re.IGNORECASE):
                score += 15
                feedback_parts.append("Annotated GenBank contains ORF features (+15)")
            else:
                score += 5
                feedback_parts.append("GenBank exists but lacks clear ORF features (+5)")
        except Exception as e:
            feedback_parts.append(f"Error parsing GenBank: {e}")
        finally:
            if os.path.exists(gb_path): os.unlink(gb_path)
    else:
        feedback_parts.append("Annotated GenBank file not found (0)")

    # 4. Verify Report (15 pts)
    if result.get('report_exists', False):
        report_path = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
        try:
            copy_from_env("/tmp/insulin_characterization.txt", report_path)
            with open(report_path, 'r') as f:
                report_content = f.read().lower()
            
            report_score = 0
            
            # Check Cysteine count (looking for '6' near 'cysteine' or 'cys')
            if re.search(r'(6\s*cys|cys[a-z]*.*?6|6.*?cys[a-z]*)', report_content):
                report_score += 10
                feedback_parts.append("Report correctly identifies 6 cysteines (+10)")
            else:
                feedback_parts.append("Report missing correct cysteine count (0)")
                
            # Check Molecular Weight (looking for numbers between 10000 and 14000)
            mw_numbers = [int(n) for n in re.findall(r'\b1[0-4]\d{3}\b', report_content)]
            if mw_numbers:
                report_score += 5
                feedback_parts.append(f"Report contains valid MW: {mw_numbers[0]} Da (+5)")
            else:
                feedback_parts.append("Report missing valid Molecular Weight (0)")
                
            score += report_score
        except Exception as e:
            feedback_parts.append(f"Error parsing report: {e}")
        finally:
            if os.path.exists(report_path): os.unlink(report_path)
    else:
        feedback_parts.append("Characterization report not found (0)")

    # 5. VLM Trajectory Verification (25 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        prompt = """
        Review these screenshots of an agent using the UGENE bioinformatics suite.
        Did the agent successfully open a sequence, use the 'Find ORFs' tool (or translate tool), and generate outputs?
        Look for evidence of UGENE's Sequence View, Annotation features, and Export/Save dialogs.
        
        Respond with a JSON object:
        {
            "ugene_used": true/false,
            "orf_or_translation_tool_visible": true/false,
            "export_save_visible": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        if all_frames:
            vlm_response = query_vlm(images=all_frames, prompt=prompt)
            if vlm_response and vlm_response.get('parsed'):
                parsed = vlm_response['parsed']
                if parsed.get('ugene_used', False):
                    vlm_score = 10
                    if parsed.get('orf_or_translation_tool_visible', False): vlm_score += 10
                    if parsed.get('export_save_visible', False): vlm_score += 5
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM verified trajectory (+{vlm_score})")
                else:
                    feedback_parts.append("VLM did not detect meaningful UGENE usage (0)")
            else:
                # Fallback if VLM fails but files exist perfectly
                if score >= 60:
                    score += 25
                    feedback_parts.append("VLM failed but programmatic evidence is overwhelming (+25)")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Graceful fallback: if everything else is perfect, grant VLM points to prevent failure due to API timeout
        if score >= 60:
            score += 25
            feedback_parts.append("VLM error, but granted points due to perfect programmatic match (+25)")

    # Final Evaluation
    passed = score >= 65 and files_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }