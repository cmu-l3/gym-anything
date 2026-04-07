#!/usr/bin/env python3
"""
Verifier for the SOD1 Electrostatic Funnel Visualization task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic Checks (70 points):
  10 pts - Publication figure exists at correct path, is new, and is >30KB.
  10 pts - Flexibility report exists and contains ≥8 lines of content.
  15 pts - Report identifies ≥3 specific positively charged residues (e.g., R143, K136)
  10 pts - Report identifies ≥2 specific negatively charged residues.
  15 pts - R143 is specifically identified (the key electrostatic guidance residue).
  10 pts - Report contains keywords indicating an understanding of electrostatic guidance.

VLM Checks (30 points):
  30 pts - Analyzes trajectory frames to visually verify the agent successfully
           generated an electrostatic surface representation (red/blue charge coloring)
           in the PyMOL viewport.

Pass threshold: 70/100
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)


# VLM Prompt for checking the PyMOL trajectory
VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing molecular visualization in PyMOL.

TASK: Generate an electrostatic surface potential visualization of SOD1 (Superoxide Dismutase) to show the charged funnel.

Analyze the progression of these screenshots and determine:
1. Did the agent successfully load a protein structure?
2. Did the agent generate a surface representation of the protein?
3. Is the surface colored by electrostatic potential (typically red for negative charge, blue for positive charge, white for neutral)?

Respond in JSON format:
{
    "protein_loaded": true/false,
    "surface_generated": true/false,
    "electrostatic_coloring_applied": true/false,
    "confidence": "low/medium/high",
    "observations": "Brief explanation of what is visible in the PyMOL viewer"
}
"""


def verify_sod1_electrostatic_funnel(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify the SOD1 electrostatic surface analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/sod1_electrostatic_result.json')

    # Read the JSON result exported from the environment
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run."
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

    # ====================================================================
    # Programmatic Checks (70 points)
    # ====================================================================
    
    # --- Criterion 1: Figure Verification (10 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 5
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} B)")
    else:
        parts.append("Figure not found at expected path")

    # --- Criterion 2: Report Verification (10 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_content_clean = report_content.replace('\\n', '\n').replace('\\t', '\t')
    report_lines = [l.strip() for l in report_content_clean.splitlines() if l.strip()]
    min_lines = metadata.get('min_report_lines', 8)

    if report_exists and len(report_lines) >= min_lines:
        score += 10
        parts.append(f"Report has sufficient length ({len(report_lines)} lines)")
    elif report_exists and len(report_lines) > 0:
        score += 5
        parts.append(f"Report exists but is too short ({len(report_lines)} lines)")
    else:
        parts.append("Report not found or is empty")

    # Extract all numbers from the text to check against known residues
    all_numbers = set(int(n) for n in re.findall(r'\b(\d{1,3})\b', report_content_clean))
    
    # --- Criterion 3: Positive Residues (15 pts) ---
    expected_pos = set(metadata.get('positive_residues', [143, 136, 9, 30, 122, 3, 115, 79]))
    found_pos = expected_pos.intersection(all_numbers)
    
    if len(found_pos) >= 3:
        score += 15
        parts.append(f"Found \u22653 positive residues (e.g., {list(found_pos)[:3]})")
    elif len(found_pos) > 0:
        score += 7
        parts.append(f"Found {len(found_pos)} positive residue(s)")
    else:
        parts.append("Did not identify correct positive residues")

    # --- Criterion 4: Negative Residues (10 pts) ---
    expected_neg = set(metadata.get('negative_residues', [132, 133, 124, 101, 100]))
    found_neg = expected_neg.intersection(all_numbers)
    
    if len(found_neg) >= 2:
        score += 10
        parts.append(f"Found \u22652 negative residues (e.g., {list(found_neg)[:2]})")
    elif len(found_neg) == 1:
        score += 5
        parts.append(f"Found 1 negative residue")
    else:
        parts.append("Did not identify correct negative residues")

    # --- Criterion 5: Key Residue R143 (15 pts) ---
    key_res = metadata.get('key_residue', 143)
    if key_res in all_numbers:
        score += 15
        parts.append(f"Successfully identified key guidance residue (R{key_res})")
    else:
        parts.append(f"Missed critical guidance residue (R{key_res})")

    # --- Criterion 6: Conceptual Keywords (10 pts) ---
    keywords = metadata.get('conceptual_keywords', ["funnel", "channel", "guidance", "electrostatic", "positive", "attract"])
    text_lower = report_content_clean.lower()
    found_keywords = [kw for kw in keywords if kw in text_lower]
    
    if len(found_keywords) >= 2:
        score += 10
        parts.append(f"Biological concept explained (keywords: {found_keywords[:2]})")
    else:
        parts.append("Lacked explanation of electrostatic guidance mechanism")

    # ====================================================================
    # VLM Trajectory Verification (30 points)
    # ====================================================================
    
    # Import VLM utilities from framework (assumes standard availability in runtime)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample trajectory to see the workflow progression
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame and final_frame not in frames:
            frames.append(final_frame)
            
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("protein_loaded"):
                    vlm_score += 5
                if parsed.get("surface_generated"):
                    vlm_score += 10
                if parsed.get("electrostatic_coloring_applied"):
                    vlm_score += 15
                    
                score += vlm_score
                parts.append(f"VLM verified electrostatic surface ({vlm_score}/30 pts)")
            else:
                parts.append("VLM analysis failed or was unavailable")
        else:
            parts.append("No trajectory frames available for VLM check")
            
    except ImportError:
        logger.warning("VLM utilities not available; skipping trajectory check.")
        parts.append("VLM tools missing")
    except Exception as e:
        logger.error(f"Error during VLM verification: {e}")
        parts.append("VLM check encountered an error")

    # ====================================================================
    # Final Evaluation
    # ====================================================================
    
    # Must achieve at least 70 points AND have successfully exported a figure
    key_criteria_met = fig_exists and fig_is_new
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }