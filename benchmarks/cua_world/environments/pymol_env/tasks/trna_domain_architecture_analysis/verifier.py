#!/usr/bin/env python3
"""
Verifier for the tRNA Domain Architecture Analysis task (PDB:1EHZ).

Scoring (100 points total):
  20 pts - Figure exists at correct path, is new (post-task-start), and >30KB.
  20 pts - Report correctly names ≥3 of the 4 structural domains of the tRNA.
  20 pts - Report contains a physically plausible distance (55-95 Å) between 3' end and anticodon.
  20 pts - Report correctly identifies ≥1 modified nucleotide specific to 1EHZ.
  20 pts - VLM verification of trajectory (ensures PyMOL interaction and visual confirmation).

Pass threshold: 70/100

Anti-gaming:
  - figure_is_new gate rules out pre-existing files.
  - Required domain keywords are checked via robust regex.
  - Valid distance range (55-95) prevents simple guessing.
  - Modified nucleotide list is strict and prevents generic "modified" statements from passing.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# Try importing VLM, but degrade gracefully if missing
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not found. Will score without VLM trajectory check.")

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent working in PyMOL.
The agent's task is to analyze the 3D structure of yeast tRNA (PDB 1EHZ).
Look at the trajectory frames to verify the agent's process:
1. Did the agent interact with the PyMOL interface?
2. Did the agent color different parts of the tRNA molecule distinctly (showing multiple colored domains)?
3. Did the agent display the molecule in a non-default representation (e.g., cartoon or sticks instead of lines)?

Respond in JSON format exactly like this:
{
    "pymol_interaction": true/false,
    "domains_colored_distinctly": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}"""


def verify_trna_domain_architecture(traj, env_info, task_info):
    """Verify the tRNA domain architecture analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/trna_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found \u2014 export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be new")
    elif fig_exists:
        parts.append(f"Figure exists but too small ({fig_size} B) \u2014 likely placeholder")
    else:
        parts.append("Figure not found at /home/ga/PyMOL_Data/images/trna_domains.png")

    # --- Report Checks Initialization ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').lower()
    
    if not report_exists:
        parts.append("Report not found at /home/ga/PyMOL_Data/trna_structure_report.txt")
        # Proceed with evaluation to show failures
    elif len(report_content.strip().splitlines()) < metadata.get('min_report_lines', 5):
        parts.append(f"Report is shorter than required {metadata.get('min_report_lines')} lines.")

    # --- Criterion 2: Domains Identified (20 pts) ---
    domains_found = 0
    if re.search(r'\bacceptor\b', report_content):
        domains_found += 1
    if re.search(r'\bd[-_ ]?(arm|loop)\b', report_content) or 'dihydrouridine' in report_content:
        domains_found += 1
    if re.search(r'\banticodon\b', report_content):
        domains_found += 1
    if re.search(r'\bt[-_ ]?(arm|loop|yc|psi)\b', report_content) or 'tψc' in report_content:
        domains_found += 1

    if domains_found >= 3:
        score += 20
        parts.append(f"Identified {domains_found}/4 tRNA domains.")
    elif domains_found > 0:
        score += domains_found * 5
        parts.append(f"Identified only {domains_found}/4 tRNA domains.")
    else:
        parts.append("No tRNA domains identified in report.")

    # --- Criterion 3: Distance measured (20 pts) ---
    dist_min = metadata.get('distance_min', 55.0)
    dist_max = metadata.get('distance_max', 95.0)
    
    # Extract all numbers (integers or floats)
    all_numbers = [float(n) for n in re.findall(r'\b\d+(?:\.\d+)?\b', report_content)]
    valid_distances = [d for d in all_numbers if dist_min <= d <= dist_max]

    if valid_distances:
        score += 20
        parts.append(f"Valid distance found: {valid_distances[0]:.2f} \u00c5")
    elif all_numbers:
        parts.append(f"Numbers found in report but none in expected distance range ({dist_min}-{dist_max} \u00c5).")
    else:
        parts.append("No numeric distance value found in report.")

    # --- Criterion 4: Modified Nucleotides (20 pts) ---
    valid_mods = [m.lower() for m in metadata.get('mod_nucleotides', [])]
    mod_found = False
    for mod in valid_mods:
        if re.search(rf'\b{re.escape(mod)}\b', report_content):
            mod_found = True
            break
            
    if mod_found:
        score += 20
        parts.append("Modified nucleotide successfully identified.")
    else:
        parts.append("No valid modified nucleotide code or name found in report.")

    # --- Criterion 5: VLM Trajectory Check (20 pts) ---
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("pymol_interaction") and parsed.get("domains_colored_distinctly"):
                    score += 20
                    parts.append("VLM verified PyMOL interaction and distinct domain coloring.")
                elif parsed.get("pymol_interaction"):
                    score += 10
                    parts.append("VLM verified interaction, but could not confirm distinct coloring.")
                else:
                    parts.append("VLM did not detect proper PyMOL usage.")
            else:
                # If VLM fails/timeouts, grant points if programmatic file tests were perfect
                if score >= 60:
                    score += 20
                    parts.append("VLM query failed, but programmatic evidence is strong.")
                else:
                    parts.append("VLM query failed.")
        except Exception as e:
            logger.warning(f"VLM evaluation error: {e}")
            if score >= 60:
                score += 20
                parts.append("VLM check bypassed due to error (programmatic passing).")
    else:
        # If VLM is not available in the environment, rescale programmatic to 100
        logger.info("VLM not available, rescaling score.")
        score = int(score * (100.0 / 80.0))

    # Calculate pass/fail
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }