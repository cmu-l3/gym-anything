#!/usr/bin/env python3
"""
Verifier for the MHC Class I Peptide Groove Analysis task.

Scoring (100 points total):
  10 pts - Programmatic: Figure exists, is new (> task start), and > 40KB
  15 pts - Programmatic: Report contains the expected peptide sequence (LLFGYPVYV)
  20 pts - Programmatic: Report lists >= 8 valid chain A groove contact residue numbers
  20 pts - Programmatic: Identifies anchor residues P2 (Leu) and P9 (Val)
  15 pts - Programmatic: Identifies >= 3 known key HLA groove residues (e.g., Y7, Y9, M45)
  20 pts - VLM: Trajectory frames confirm genuine interaction with PyMOL, showing structural
           manipulation (loading, coloring, or representing protein and peptide).

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate ensures file wasn't created before the task started.
  - VLM on trajectory confirms actual PyMOL usage, preventing agent from just writing a 
    text file with memorized answers and a fake random PNG.
  - Residue number counts must be within realistic MHC groove bounds (1-180).
"""

import json
import os
import re
import tempfile
import logging

# Import VLM utilities
import sys
sys.path.append('/workspace')
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
except ImportError:
    # Handle local testing where framework is not available
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(*args, **kwargs): return {"success": False}
    def get_final_screenshot(traj): return None

logger = logging.getLogger(__name__)

KNOWN_GROOVE_RESIDUES = {7, 9, 45, 63, 66, 77, 84, 146, 147, 159}

VLM_PROMPT = """You are verifying an agent's trajectory in a PyMOL structural biology task.

The agent was tasked with loading HLA-A2 structure (PDB: 1AKJ), selecting the bound peptide in the groove, and creating a visualization. 

Look at the provided trajectory frames (which show the chronological progression of the agent's screen):
1. Is PyMOL visibly open and actively used?
2. Did the agent load a 3D molecular structure?
3. Is there evidence of structural manipulation? (e.g., showing sticks, highlighting the peptide in a different color, focusing on a binding pocket)
4. Does the final image or late trajectory show a clear view of a peptide bound inside a protein groove?

Return a JSON with your analysis:
{
    "pymol_used": true/false,
    "structure_loaded": true/false,
    "manipulation_visible": true/false,
    "peptide_groove_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is seen in the frames"
}
"""

def verify_mhc_peptide_groove_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/mhc_peptide_result.json')

    # Read result from container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Figure exists and is substantial (10 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 10
        feedback_parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        feedback_parts.append(f"Figure exists ({fig_size // 1024} KB) but timestamp check failed")
    elif fig_exists:
        feedback_parts.append(f"Figure exists but too small ({fig_size} B) - possible placeholder")
    else:
        feedback_parts.append("Figure not found")

    # --- Criterion 2: Peptide Sequence (15 pts) ---
    report_content = result.get('report_content', '')
    expected_seq = metadata.get('peptide_sequence', 'LLFGYPVYV')

    if expected_seq.lower() in report_content.lower():
        score += 15
        feedback_parts.append(f"Peptide sequence '{expected_seq}' identified")
    elif 'tax' in report_content.lower() or 'htlv' in report_content.lower():
        score += 5
        feedback_parts.append("Tax peptide mentioned, but exact sequence missing")
    else:
        feedback_parts.append("Peptide sequence missing from report")

    # --- Criterion 3: Groove Contact Residue Count (20 pts) ---
    # Extract numbers in the range of HLA-A2 alpha-1 and alpha-2 domains (1-180)
    all_numbers = re.findall(r'\b([1-9][0-9]{0,2})\b', report_content)
    groove_candidates = set(int(n) for n in all_numbers if 1 <= int(n) <= 180)

    if len(groove_candidates) >= 8:
        score += 20
        feedback_parts.append(f"Found >= 8 plausible groove contact residues")
    elif len(groove_candidates) >= 4:
        score += 10
        feedback_parts.append(f"Found {len(groove_candidates)} plausible groove contact residues (expected >= 8)")
    else:
        feedback_parts.append(f"Insufficient groove contact residues documented ({len(groove_candidates)})")

    # --- Criterion 4: Anchor Residues (P2 and P9) (20 pts) ---
    p2_found = bool(re.search(r'(P2|position\s*2|anchor.*leu|leu.*anchor|LEU\s+2\b|Leu2|B[\s-]*pocket)', report_content, re.IGNORECASE))
    p9_found = bool(re.search(r'(P9|position\s*9|anchor.*val|val.*anchor|VAL\s+9\b|Val9|F[\s-]*pocket)', report_content, re.IGNORECASE))

    if p2_found and p9_found:
        score += 20
        feedback_parts.append("Both P2(Leu) and P9(Val) anchor residues identified")
    elif p2_found or p9_found:
        score += 10
        feedback_parts.append("Only one of the two anchor residues (P2/P9) clearly identified")
    else:
        feedback_parts.append("Anchor residues not clearly identified")

    # --- Criterion 5: Known Groove Residues (15 pts) ---
    known_found = [res for res in KNOWN_GROOVE_RESIDUES if re.search(rf'\b{res}\b', report_content)]
    
    if len(known_found) >= 3:
        score += 15
        feedback_parts.append(f"Validated {len(known_found)} known groove residues")
    elif len(known_found) >= 1:
        score += 5
        feedback_parts.append(f"Validated {len(known_found)} known groove residues (expected >= 3)")
    else:
        feedback_parts.append("No known literature groove residues identified")

    # --- Criterion 6: VLM Trajectory Verification (20 pts) ---
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    if final:
        frames.append(final)
        
    vlm_score = 0
    if frames:
        try:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("pymol_used", False): vlm_score += 5
                if parsed.get("structure_loaded", False): vlm_score += 5
                if parsed.get("manipulation_visible", False): vlm_score += 5
                if parsed.get("peptide_groove_visible", False): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM visual verification: {vlm_score}/20 pts")
            else:
                feedback_parts.append("VLM query failed or returned no parsable success")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped due to error")
    else:
        feedback_parts.append("No trajectory frames available for VLM verification")

    # --- Final Assessment ---
    # Need to pass threshold AND must have actually done work (identified the peptide, written something, created a figure)
    key_criteria_met = fig_exists and fig_is_new and len(groove_candidates) >= 4
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }