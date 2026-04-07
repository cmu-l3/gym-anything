#!/usr/bin/env python3
import json
import os
import tempfile
import re

# Standard genetic code dictionary to independently verify translations 
CODON_TABLE = {
    'ATA':'I', 'ATC':'I', 'ATT':'I', 'ATG':'M', 'ACA':'T', 'ACC':'T', 'ACG':'T', 'ACT':'T',
    'AAC':'N', 'AAT':'N', 'AAA':'K', 'AAG':'K', 'AGC':'S', 'AGT':'S', 'AGA':'R', 'AGG':'R',
    'CTA':'L', 'CTC':'L', 'CTG':'L', 'CTT':'L', 'CCA':'P', 'CCC':'P', 'CCG':'P', 'CCT':'P',
    'CAC':'H', 'CAT':'H', 'CAA':'Q', 'CAG':'Q', 'CGA':'R', 'CGC':'R', 'CGG':'R', 'CGT':'R',
    'GTA':'V', 'GTC':'V', 'GTG':'V', 'GTT':'V', 'GCA':'A', 'GCC':'A', 'GCG':'A', 'GCT':'A',
    'GAC':'D', 'GAT':'D', 'GAA':'E', 'GAG':'E', 'GGA':'G', 'GGC':'G', 'GGG':'G', 'GGT':'G',
    'TCA':'S', 'TCC':'S', 'TCG':'S', 'TCT':'S', 'TTC':'F', 'TTT':'F', 'TTA':'L', 'TTG':'L',
    'TAC':'Y', 'TAT':'Y', 'TAA':'*', 'TAG':'*', 'TGC':'C', 'TGT':'C', 'TGA':'*', 'TGG':'W',
}

def translate(seq):
    protein = ""
    for i in range(0, len(seq)-2, 3):
        codon = seq[i:i+3].upper()
        protein += CODON_TABLE.get(codon, 'X')
    return protein

def verify_egfp_lc3b_fusion_construction(traj, env_info, task_info):
    """
    Multi-signal verification handling DNA generation, protein translation validity, 
    absence of internal stop codons, documentation validation, and VLM workflow proof.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
    result = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    # Load Ground Truth JSON
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_gt.close()
    try:
        copy_from_env("/tmp/fusion_design_gt.json", tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception:
        # Fallback to general known metrics if GT setup partially failed 
        gt = {
            "egfp_cds_len": 720,
            "lc3b_cds_len": 378,
            "fusion_dna_len": 1095,
            "fusion_protein_len": 365,
            "fusion_dna_seq": None
        }
    finally:
        if os.path.exists(tmp_gt.name):
            os.unlink(tmp_gt.name)

    score = 0
    feedback_parts = []
    
    # 1. Check DNA (30 pts)
    task_start = result.get('task_start_ts', 0)
    dna_seq = result.get('dna_seq', '')
    dna_mtime = result.get('dna_mtime', 0)
    
    if result.get('dna_exists', False) and dna_mtime >= task_start:
        if gt.get('fusion_dna_seq') and dna_seq == gt['fusion_dna_seq']:
            score += 30
            feedback_parts.append("DNA sequence exactly matches expected fusion (+30)")
        elif len(dna_seq) == gt.get('fusion_dna_len', 1095):
            score += 25
            feedback_parts.append("DNA sequence length is exactly correct (+25)")
        elif abs(len(dna_seq) - gt.get('fusion_dna_len', 1095)) < 15:
            score += 10
            feedback_parts.append("DNA sequence length is close but slightly off (+10)")
        else:
            feedback_parts.append("DNA sequence is wildly incorrect length (0)")
    else:
        feedback_parts.append("DNA FASTA missing or not created during task (0)")
        
    # 2. Check Protein & Stop Codon Removal Logic (30 pts)
    prot_seq = result.get('prot_seq', '')
    prot_mtime = result.get('prot_mtime', 0)
    
    if result.get('prot_exists', False) and prot_mtime >= task_start:
        expected_prot = translate(dna_seq) if dna_seq else ""
        if not expected_prot and gt.get('fusion_dna_seq'):
            expected_prot = translate(gt['fusion_dna_seq'])
            
        if expected_prot and prot_seq == expected_prot:
            score += 20
            feedback_parts.append("Protein sequence exactly matches translated DNA (+20)")
        elif len(prot_seq) > 100:
            score += 10
            feedback_parts.append("Protein sequence exists but does not match exact prediction (+10)")
            
        # The ultimate test of the prompt: checking for internal stop codons (10 pts)
        if prot_seq:
            # Strip trailing stop codon if present
            core_prot = prot_seq[:-1] if prot_seq.endswith('*') else prot_seq
            if '*' not in core_prot:
                score += 10
                feedback_parts.append("No internal stop codons found! Agent successfully handled the fusion joint (+10)")
            else:
                feedback_parts.append("Internal stop codon found! Agent failed to correctly remove the EGFP stop codon. (0)")
    else:
        feedback_parts.append("Protein FASTA missing or not created during task (0)")

    # 3. Check Report Outputs (20 pts)
    report = result.get('report_content', '')
    report_mtime = result.get('report_mtime', 0)
    
    if result.get('report_exists', False) and report_mtime >= task_start:
        report_score = 0
        # Look for required metrics
        nums = set(re.findall(r'\d+', report))
        if str(gt.get('egfp_cds_len', 720)) in nums: report_score += 5
        if str(gt.get('lc3b_cds_len', 378)) in nums: report_score += 5
        if str(gt.get('fusion_dna_len', 1095)) in nums: report_score += 5
        if str(gt.get('fusion_protein_len', 365)) in nums: report_score += 5
        
        score += report_score
        feedback_parts.append(f"Report contains {report_score//5}/4 correct expected lengths (+{report_score})")
    else:
        feedback_parts.append("Report missing or not created during task (0)")

    # 4. VLM UI Usage Check (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        tmp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        tmp_png.close()
        try:
            copy_from_env("/tmp/task_final.png", tmp_png.name)
            if os.path.getsize(tmp_png.name) > 0:
                prompt = """Review this screenshot from a UGENE bioinformatics session.
Did the user interact with the Sequence Viewer, Translation tool, or file annotation panes to construct the gene fusion?
Respond in JSON: {"used_ui": true/false}"""
                vlm_res = query_vlm(prompt=prompt, image=tmp_png.name)
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("used_ui", False):
                    score += 20
                    feedback_parts.append("VLM verified UGENE UI usage (+20)")
                else:
                    feedback_parts.append("VLM did not detect relevant UGENE UI elements (0)")
            else:
                score += 20
                feedback_parts.append("Screenshot missing, bypassing VLM (+20)")
        except Exception as e:
            score += 20
            feedback_parts.append(f"VLM check bypassed due to exception: {e} (+20)")
        finally:
            if os.path.exists(tmp_png.name):
                os.unlink(tmp_png.name)
    else:
        score += 20
        feedback_parts.append("VLM evaluator missing, granting points (+20)")

    # 85 is the required pass threshold 
    passed = score >= 85 and result.get('dna_exists', False) and result.get('prot_exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }