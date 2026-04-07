#!/usr/bin/env python3
"""
Verifier for the Cholera Toxin AB5 Architecture Analysis task (PDB:1XTC).

Scoring (100 points total):
  20 pts - Figure Generation: PNG file exists at correct path, is >40KB, and created after task start.
  20 pts - Chain Identification: The report correctly identifies the A-chain and B-chains.
  20 pts - Receptor Site Identification: The report mentions the 5 Trp88 residues.
  40 pts - Interface Contact Accuracy: Programmatically evaluates the agent's reported interface
           residues against the ground-truth contacts (extracted live from the environment). 
           Uses dual strict/loose parsing to be robust against LLM formatting habits (lists vs individual).

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_cholera_toxin_ab5_architecture(traj, env_info, task_info):
    """Verify the cholera toxin AB5 architecture task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/cholera_ab5_result.json')
    gt_path = metadata.get('gt_json', '/tmp/cholera_gt.json')

    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_gt.close()
    
    try:
        copy_from_env(result_path, tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
            
        copy_from_env(gt_path, tmp_gt.name)
        with open(tmp_gt.name, 'r') as f:
            gt_data = json.load(f)
            gt_contacts = set(gt_data.get('gt_contacts', []))
    except FileNotFoundError:
        return {
            "passed": False, "score": 0, 
            "feedback": "Result files not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        for tmp_name in [tmp_res.name, tmp_gt.name]:
            try:
                os.unlink(tmp_name)
            except Exception:
                pass

    # Safety fallback in case ground truth generation failed during export
    if not gt_contacts:
        gt_contacts = {'B:11', 'B:12', 'B:15', 'B:16', 'B:33', 'B:34', 'B:89', 'B:90'}
        logger.warning("Ground truth file missing valid contacts; using minimal fallback.")

    score = 0
    parts = []

    # --- Criterion 1: Figure Generation (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) — likely a placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/cholera_ab5.png")

    report_content = result.get('report_content', '').upper()
    
    # --- Criterion 2: Chain Identification (20 pts) ---
    chains_found = set(re.findall(r'\b[A-F]\b', report_content))
    expected_chains = {'A', 'B', 'C', 'D', 'E', 'F'}
    
    if expected_chains.issubset(chains_found):
        score += 20
        parts.append("Correctly identified chains A and B-F")
    elif 'A' in chains_found and len(chains_found.intersection({'B', 'C', 'D', 'E', 'F'})) > 0:
        score += 10
        parts.append("Partially identified chains in complex")
    else:
        parts.append("Did not correctly identify the A and B-F chains")

    # --- Criterion 3: Receptor Site Identification (Trp88 count) (20 pts) ---
    mentions_trp88 = bool(re.search(r'(TRP\s*88|W\s*88|TRYPTOPHAN\s*88)', report_content))
    mentions_5 = bool(re.search(r'\b(5|FIVE)\b', report_content))
    
    if mentions_trp88 and mentions_5:
        score += 20
        parts.append("Correctly identified 5 Trp88 residues")
    elif mentions_trp88:
        score += 10
        parts.append("Mentioned Trp88 but did not explicitly state there are 5")
    else:
        parts.append("Did not identify the Trp88 receptor sites")

    # --- Criterion 4: Interface Contact Accuracy (40 pts) ---
    agent_contacts = set()
    # Matches 'B:72', 'B-72', 'B 72', 'B resi 72'
    matches = re.findall(r'\b([B-F])\s*[:\-\s]?\s*(?:RESI(?:DUE)?\s*)?(\d{1,3})\b', report_content)
    for chain, resi in matches:
        agent_contacts.add(f"{chain}:{resi}")

    # Calculate Strict Overlap
    overlap_strict = len(agent_contacts.intersection(gt_contacts))
    gt_len = len(gt_contacts)
    recall_strict = overlap_strict / gt_len if gt_len > 0 else 0
    
    # Calculate Loose Overlap (handles "Chain B: 72, 75, 80" list formatting)
    matches_loose = re.findall(r'\b(\d{1,3})\b', report_content)
    gt_resis = {x.split(':')[1] for x in gt_contacts}
    agent_resis = {x for x in matches_loose if x in gt_resis}
    overlap_loose = len(agent_resis)
    recall_loose = overlap_loose / len(gt_resis) if len(gt_resis) > 0 else 0
    
    # Use whichever method gives higher score
    if recall_strict >= recall_loose:
        recall = recall_strict
        overlap = overlap_strict
        target_len = gt_len
    else:
        recall = recall_loose
        overlap = overlap_loose
        target_len = len(gt_resis)

    if gt_len > 0:
        if recall >= 0.8:
            score += 40
            parts.append(f"Highly accurate interface mapping ({overlap}/{target_len} contacts)")
        elif recall >= 0.5:
            score += 25
            parts.append(f"Good interface mapping ({overlap}/{target_len} contacts)")
        elif recall > 0:
            score += 10
            parts.append(f"Partial interface mapping ({overlap}/{target_len} contacts)")
        else:
            parts.append("No correct interface contacts documented")
    else:
        parts.append("Ground truth contact length is 0 (check setup)")

    passed = score >= 70 and overlap > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }