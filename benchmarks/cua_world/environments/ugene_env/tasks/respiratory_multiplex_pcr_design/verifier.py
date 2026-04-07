#!/usr/bin/env python3
"""
Verifier for respiratory_multiplex_pcr_design task.

This script parses the output CSV, calculates thermodynamic properties of the
agent's primers, validates biological mappings back to the reference sequences,
and verifies amplicon size restrictions.
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Real sequences used in setup_task.sh to map against
REFERENCE_SEQUENCES = {
    "FluA": "AGCAAAAGCAGGTAGATATTGAAAGATGAGTCTTCTAACCGAGGTCGAAACGTACGTTCTCTCTATCATCCCGTCAGGCCCCCTCAAAGCCGAGATCGCGCAGAGACTGGAAAGTGTCTTTGCAGGAAAGAACACAGATCTTGAGGCTCTCATGGAATGGCTAAAGACAAGACCAATCCTGTCACCTCTGACTAAGGGGATTTTAGGATTTGTGTTCACGCTCACCGTGCCCAGTGAGCGAGGACTGCAGCGTAGACGCTTTGTCCAAAATGCCCTTAATGGGAACGGGGATCCAAATAACATGGACAAAGCAGTTAAACTGTATAGGAAGCTCAAGAGGGAGATAACATTCCATGGGGCCAAAGAAATCTCACTCAGTTATTCTGCTGGTGCACTTGCCAGTTGTATGGGCCTCATATACAACAGGATGGGGGCTGTGACCACTGAAGTGGCATTTGGCCTGGTATGTGCAACCTGTGAACAGATTGCTGACTCCCAGCATCGGTCTCATAGGCAAATGGTGACAACAACCAATCCACTAATCAGACATGAGAACAGAATGGTTTTAGCCAGCACTACAGCTAAGGCTATGGAGCAAATGGCTGGATCGAGTGAGCAAGCAGCAGAGGCCATGGAGGTTGCTAGTCAGGCTAGACAAATGGTGCAAGCGATGAGAACCATTGGGACTCATCCTAGCTCCAGTGCTGGTCTGAAAAATGATCTTCTTGAAAATTTGCAGGCCTATCAGAAACGAATGGGGGTGCAGATGCAACGATTCAAGTGATCCTCTCGTTATTGCAGCAAGTATCATTGGGATCTTGCACTTGATATTGTGGATTCTTGATCGTCTTTTTTTCAAATGCATTTACCGTCGCTTTAAATACGGACTGAAAGGAGGGCCTTCTACGGAAGGAGTGCCAAAGTCTATGAGGGAAGAATATCGAAAGGAACAGCAGAGTGCTGTGGATGCTGACGATGGTCATTTTGTCAGCATAGAGCTGGAGTAAAAAACTACCTTGTTTCTACT",
    "FluB": "AGCAGAAGCAGAGGATTTGTTTAGTCACTGGCAAACGGAAAAAAATGGCCACAACCATGGACACAACCAAAGGAGAATTTCTAGGGAGGACAATGATTCTAACAACACCACAGACAACAGATAAGAACTTTACTCCTAATGAGAGTAGAATAGCCAGAATAATGATAATGGGCAAACAAACAATCAAAATCAACGAGCAAGCAATTCAAGAGCACTACAATTTCAAAAACGCAACAAAACTAAATTGTATTTCAGAATTGGTCAATAAGCTCTACCTCAAAATGGACGATAACATAATTGAGTCAAACAAGATAACACTGAATATTTACTCCAAGGTAACAAGCTCTGTCGCTCCTCCGGATGCTGGAAGTACTAGAAAACTACTGGAGTATCTTGACATTACAACTGAACCTTTGAATGTCCCAGAGCCAAAGATCACAGGGAACCACAAAAAACTCAAGAAGATAACAAAAAACAACAAGAACAAATGCACCCTGCACTAATTCAAAAATGCTGTGTGAAATAAACCCAAGTACAATGCTAAAACAACCAGAACCAAAGGGAATGAGGTGCGGAAACGAACAAGTTAAACCGCCGGGGGTCAAAAGGACAATGGAGAACATGTAGAAACATGGAATAATGCACCAAGAACAGTTAAAATAAGATTTTAATACAACAAACTCATCTAAAACACTTGTGGTTAGTGTAATTGGCATGACACTCAAAACACAACAACAACAGTTAACAAAACTAACAATTGAGATAACACTTCCAACATACAAACACCAAGAACCAGCAATAACAACCAAACACACAAACAACAACAAAACTACAATTGCAACAACAATAAAATACAAACATCAAAACCACCACCACCAACAAAAAAACACAAACACACACACAACACAAAACTACAACAACACAAAAA",
    "RSV": "ATGGCTCTTAGCAAAGTCAAGTTGAATGATACACTCAACAAAGATCAACTTCTGTCATCCAGCAAATACACCATCCAACGGAGCACAGGAGATAGTATTGATACTCCTAATTATGATGTGCAGAAACACATCAATAAGTTATGTGGCATGTTATTAATCACAGAAGATGCTAATCATAAATTCACTGGGTTAATAGGTATGTTATATGCGATGTCTAGGTTAGGAAGAGAAGACACCATAAAAATACTCAGAGATGCGGGATATCATGTAAAAGCAAATGGAGTAGATGTAACAACACATCGTCAAGACATTAATGGAAAAGAAATGAAATTTGAAGTGTTAACATTGGCAAGCTTAACAACTGAAATTCAAATCAACATTGAGATAGAATCTAGAAAATCCTACAAAAAAATGCTAAAAGAAATGGGAGAGGTAGCTCCAGAATACAGGCATGACTCTCCTGATTGTGGGATGATAATATTATGTATAGCAGCATTAGTAATAACTAAATTAGCAGCAGGGGATAGATCTGGTCTTACAGCCGTGATTAGGAGAGCTAATAATGTCCTAAAAAATGAAATGAAACGTTACAAAGGCTTACTACCCAAGGACATAGCCAACAGCTTCTATGAAGTGTTTGAAAAACATCCTCACCTTATAGATGTTTTTGTGCACTTTGGCATAGCACAATCATCCACCAGAGGTGGCAGTAGAGTTGAAGGGATTTTTGCAGGATTGTTTATGAATGCCTATGGTGCAGGGCAAGTGATGTTACGGTGGGGAGTCTTAGCAAAATCAGTTAAAAATATTATGTTAGGACATGCTAGTGTGCAAGCAGAAATGGAACAAGTTGTTGAGGTTTATGAATATGCCCAAAAATTGGGTGGTGAAGCAGGATTCTACCATATATTGAACAACCCAAAAGCATCATTATTATCTTTGACTCAATTTCCTCACTTCTCCAGTGTAGTATTAGGCAATGCTGCTGGCCTAGGCATAATGGGAGAGTACAGAGGTACACCGAGGAATCAAGATCTATATGATGCAGCAAAGGCATATGCTGAACAACTCAAAGAAAATGGTGTGATTAACTACAGTGTACTAGACTTGACAGCAGAAGAACTAGAGGCTATCAAACATCAGCTTAATCCAAAAGATAATGATGTAGAGCTTTGAGTTAATAAAAAATGGGGCAAATAA"
}

def reverse_complement(seq):
    comp = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C'}
    return ''.join(comp.get(base, base) for base in reversed(seq.upper()))

def calculate_tm(seq):
    """
    Standard Wallace rule / nearest neighbor approximation for Tm.
    """
    seq = seq.upper()
    gc = seq.count('G') + seq.count('C')
    at = seq.count('A') + seq.count('T')
    length = len(seq)
    
    if length == 0:
        return 0.0
    
    if length < 14:
        return 2 * at + 4 * gc
    else:
        return 64.9 + 41 * (gc - 16.4) / length

def query_vlm_for_trajectory(traj, env_info):
    """Check via VLM if Primer3 dialogs or similar UGENE interactions occurred."""
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return False
        
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            return False
            
        prompt = (
            "You are verifying a bioinformatics workflow in UGENE. Look at these frames. "
            "Did the user use a primer design tool (like 'Primer3' dialog) or interact with sequences "
            "meaningfully? Reply strictly with JSON: {\"used_primer_tool\": true/false}"
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get('success'):
            return vlm_res.get('parsed', {}).get('used_primer_tool', False)
    except Exception as e:
        logger.error(f"VLM trajectory check failed: {e}")
        
    return False

def verify_respiratory_multiplex_pcr_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback = []
    
    # 1. Get overall JSON execution result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pcr_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Early check for basic file generation
    gb_exists = [
        result.get('gb_flua_exists', False),
        result.get('gb_flub_exists', False),
        result.get('gb_rsv_exists', False)
    ]
    if sum(gb_exists) == 3:
        score += 10
        feedback.append("All 3 GenBank annotated files exist (+10)")
    else:
        feedback.append(f"Missing some GenBank files (Found {sum(gb_exists)}/3) (0)")

    if result.get('csv_exists', False):
        score += 10
        feedback.append("CSV report file exists (+10)")
    else:
        feedback.append("Missing CSV report file (0)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Parse the CSV file
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/multiplex_panel.csv", temp_csv.name)
        primers = {"FluA": {}, "FluB": {}, "RSV": {}}
        
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames or []
            required_headers = ['Virus', 'Primer_Type', 'Sequence', 'Expected_Amplicon_Size']
            
            # Allow loose matching for headers
            if all(any(req.lower() in h.lower() for h in headers) for req in required_headers):
                for row in reader:
                    # Clean dictionary keys
                    clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                    
                    virus = None
                    if "flua" in str(list(clean_row.values())).lower(): virus = "FluA"
                    if "flub" in str(list(clean_row.values())).lower(): virus = "FluB"
                    if "rsv" in str(list(clean_row.values())).lower(): virus = "RSV"
                    
                    ptype = None
                    if "forward" in str(list(clean_row.values())).lower() or "fwd" in str(list(clean_row.values())).lower(): ptype = "Forward"
                    if "reverse" in str(list(clean_row.values())).lower() or "rev" in str(list(clean_row.values())).lower(): ptype = "Reverse"
                    
                    seq_val = None
                    for v in clean_row.values():
                        if all(c in 'ACGTacgt' for c in v) and len(v) >= 15:
                            seq_val = v.upper()
                            
                    if virus and ptype and seq_val:
                        primers[virus][ptype] = seq_val
            else:
                feedback.append(f"CSV headers incorrect. Found: {headers}")
                return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
                
    except Exception as e:
        feedback.append(f"Error parsing CSV: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Verify Biologic Validity, Amplicon Size, and Tm
    sizes = {"FluA": (180, 220), "FluB": (380, 420), "RSV": (580, 620)}
    points_per_virus = 15
    tm_list = []
    
    true_amplicons = []

    for virus, target_size_range in sizes.items():
        v_primers = primers.get(virus, {})
        fwd = v_primers.get("Forward")
        rev = v_primers.get("Reverse")
        
        if not fwd or not rev:
            feedback.append(f"Missing {virus} primers in CSV.")
            continue
            
        ref_seq = REFERENCE_SEQUENCES[virus]
        
        # Exact substring search for biological validation
        fwd_idx = ref_seq.find(fwd)
        rev_comp = reverse_complement(rev)
        rev_idx = ref_seq.find(rev_comp)
        
        if fwd_idx != -1 and rev_idx != -1 and rev_idx > fwd_idx:
            actual_size = (rev_idx + len(rev)) - fwd_idx
            true_amplicons.append(actual_size)
            
            # Check size constraint
            if target_size_range[0] <= actual_size <= target_size_range[1]:
                score += points_per_virus
                feedback.append(f"{virus} valid: Found {actual_size}bp (+{points_per_virus})")
            else:
                feedback.append(f"{virus} mapped, but size {actual_size}bp not in {target_size_range}")
                
            tm_list.append(calculate_tm(fwd))
            tm_list.append(calculate_tm(rev))
        else:
            feedback.append(f"{virus} primers do not correctly map to the reference genome.")

    # 4. Verify Multiplex Size Delta (>150bp separation)
    if len(true_amplicons) == 3:
        true_amplicons.sort()
        delta1 = true_amplicons[1] - true_amplicons[0]
        delta2 = true_amplicons[2] - true_amplicons[1]
        if delta1 >= 150 and delta2 >= 150:
            score += 15
            feedback.append("Amplicons sufficiently separated for multiplexing (+15)")
        else:
            feedback.append(f"Amplicons not separated by >150bp (Sizes: {true_amplicons})")

    # 5. Verify Tm Consistency
    if len(tm_list) == 6:
        # All 6 primers should be within the 58.0 to 62.0 C operational window
        if all(57.0 <= tm <= 63.0 for tm in tm_list):
            score += 20
            feedback.append("All primers have consistent Tm (57-63°C) (+20)")
        else:
            tms = [f"{t:.1f}" for t in tm_list]
            feedback.append(f"Tms are not all within operational window. Calc Tms: {tms}")

    # Optional VLM Anti-gaming Check
    if score >= 70:
        used_ui = query_vlm_for_trajectory(traj, env_info)
        if used_ui:
            feedback.append("VLM confirms Primer UI usage")
        else:
            feedback.append("VLM did not detect strong UI usage, but biological constraints met.")

    passed = score >= 70 and len(true_amplicons) == 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }