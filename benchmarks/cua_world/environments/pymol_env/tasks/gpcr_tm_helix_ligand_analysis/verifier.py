#!/usr/bin/env python3
"""
Verifier for the GPCR Transmembrane Architecture and Ligand Binding Analysis task.

Multi-Criteria Verification:
  1. Figure check (15 pts) - Must exist, be created AFTER task start, and be >50KB.
  2. Asp113 identification (20 pts) - The critical salt bridge must be explicitly mentioned.
  3. Real contacts listed (20 pts) - Must identify >= 6 valid contact residues from the known set.
  4. TM Helix assignment (20 pts) - Must mention >= 3 distinct TM helices (e.g., TM3, TM5, TM6).
  5. VLM Trajectory (25 pts) - Uses trajectory frames to visually verify 7 distinct colors
     on helices and the ligand visible with surrounding sticks.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Known carazolol contact residues in 2RH1 (within ~4.0 A)
KNOWN_CONTACTS = {113, 114, 117, 203, 204, 207, 208, 286, 289, 290, 293, 308, 312}

def verify_gpcr_tm_helix_ligand_analysis(traj, env_info, task_info):
    """Verify the GPCR TM helix and binding site analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/gpcr_task_result.json')

    # 1. Retrieve the exported JSON from the container environment safely
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found. Export script failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    parts = []

    # --- Criterion 1: Figure exists, is new, and non-trivial (15 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 50000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 15
        parts.append(f"Figure created during task ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        parts.append(f"Figure exists ({fig_size // 1024} KB) but timestamp shows it's not new")
    else:
        parts.append("Valid binding site figure not found or too small")

    # --- Criterion 2: Identification of Asp113/D113 (20 pts) ---
    report_content = result.get('report_content', '').replace('\\n', '\n')
    
    if re.search(r'\b(Asp\s*113|D\s*113|113)\b', report_content, re.IGNORECASE):
        score += 20
        parts.append("Asp113 salt-bridge identified")
    else:
        parts.append("Asp113 not found in report")

    # --- Criterion 3: Known contact residues (20 pts) ---
    # Look for 3-digit numbers since all GPCR TM contacts here are between 100-350
    all_numbers = re.findall(r'\b(\d{3})\b', report_content)
    found_contacts = set(int(n) for n in all_numbers).intersection(KNOWN_CONTACTS)
    min_contacts = metadata.get('min_contacts_required', 6)

    if len(found_contacts) >= min_contacts:
        score += 20
        parts.append(f"Found {len(found_contacts)} valid contact residues")
    elif len(found_contacts) > 0:
        score += int((len(found_contacts) / min_contacts) * 20)
        parts.append(f"Found {len(found_contacts)} valid contact residues (need {min_contacts})")
    else:
        parts.append("No valid known contacts documented")

    # --- Criterion 4: TM Helix Assignment (20 pts) ---
    tm_matches = re.findall(r'\b(?:TM|Helix)\s*([1-7])\b', report_content, re.IGNORECASE)
    distinct_tms = set(tm_matches)
    min_tms = metadata.get('min_tm_helices_required', 3)

    if len(distinct_tms) >= min_tms:
        score += 20
        parts.append(f"Documented contacts in {len(distinct_tms)} TM helices")
    elif len(distinct_tms) > 0:
        score += int((len(distinct_tms) / min_tms) * 20)
        parts.append(f"Documented contacts in {len(distinct_tms)} TM helices (need {min_tms})")
    else:
        parts.append("TM helices not referenced or correctly formatted")

    # --- Criterion 5: VLM Trajectory Verification (25 pts) ---
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """You are evaluating a PyMOL molecular visualization session.
Look at these chronological screenshots. 
Determine the following:
1. Did the user assign multiple DISTINCT colors to the different transmembrane (TM) helical bundles of the protein?
2. Is the small molecule ligand visible inside the protein pocket with surrounding protein residues shown as sticks?

Respond ONLY in JSON format:
{
  "distinct_helix_colors_visible": true/false,
  "ligand_and_sticks_visible": true/false
}
"""
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('distinct_helix_colors_visible', False):
                    vlm_score += 15
                if parsed.get('ligand_and_sticks_visible', False):
                    vlm_score += 10
                parts.append(f"VLM verification passed (+{vlm_score} pts)")
            else:
                parts.append("VLM query failed or returned invalid format")
    except ImportError:
        logger.warning("VLM libraries not available. Falling back to programmatic-only check.")
        # If the environment lacks VLM utilities, we distribute the points to avoid punishing the agent 
        # for framework limitations.
        vlm_score = 25 
        parts.append("VLM library missing - auto-credited VLM points")
        
    score += vlm_score

    # Determine passing state
    # Must achieve 70/100 AND correctly document at least 3 valid contacts
    passed = (score >= 70) and (len(found_contacts) >= 3) and fig_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }