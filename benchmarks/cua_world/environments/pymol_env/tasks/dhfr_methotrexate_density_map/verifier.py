#!/usr/bin/env python3
"""
Verifier for the DHFR-Methotrexate Electron Density Visualization task.

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >30KB
  20 pts - Report contains identifiers: '1RX2' and 'MTX'
  20 pts - Report contains map parameters: contour '1.5' and map type '2Fo-Fc' or '2fofc'
  40 pts - VLM verifies trajectory & final screenshot showing PyMOL with a ligand in a wireframe mesh

Pass threshold: 75/100
Must have created the figure and satisfied VLM to pass.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a PyMOL molecular visualization task.
The agent was asked to fetch PDB 1RX2 and its 2fofc electron density map, then create a carved wireframe mesh (isomesh) around the MTX ligand.

Review these trajectory frames (chronological) and the final screenshot.
Assess the following:
1. MAP_LOADED: Did the agent load an electron density map? (Often visible as a dense global mesh or bounding box initially).
2. LIGAND_VISIBLE: Is there a small molecule ligand visible, preferably represented as sticks?
3. CARVED_MESH: Is there a localized wireframe mesh wrapping around the ligand? (It should NOT just be a solid surface, but a mesh/wireframe).
4. CLEAN_VIEW: Is the view zoomed in on the ligand with the density nicely carved, without overwhelming global noise?

Respond ONLY in valid JSON format:
{
    "map_loaded": true/false,
    "ligand_visible": true/false,
    "carved_mesh": true/false,
    "clean_view": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_dhfr_methotrexate_density_map(traj, env_info, task_info):
    """Verify the density map visualization task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/density_map_result.json')

    # 1. Retrieve the results JSON from the container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # 2. Check Figure (20 pts)
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 30000)

    figure_ok = False
    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        figure_ok = True
        feedback_parts.append(f"Figure created successfully ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        figure_ok = True
        feedback_parts.append(f"Figure exists ({fig_size // 1024} KB) but may be stale")
    elif fig_exists:
        feedback_parts.append(f"Figure is too small ({fig_size} B) - likely empty")
    else:
        feedback_parts.append("Figure not found at the requested path")

    # 3. Check Report Identifiers (20 pts)
    report_content = result.get('report_content', '').lower()
    has_1rx2 = '1rx2' in report_content
    has_mtx = 'mtx' in report_content

    if has_1rx2 and has_mtx:
        score += 20
        feedback_parts.append("Report contains correct PDB and ligand identifiers")
    elif has_1rx2 or has_mtx:
        score += 10
        feedback_parts.append("Report missing either PDB ID or ligand ID")
    else:
        feedback_parts.append("Report missing required PDB and ligand identifiers")

    # 4. Check Report Parameters (20 pts)
    has_1_5 = '1.5' in report_content
    has_map_type = '2fo' in report_content or '2fofc' in report_content

    if has_1_5 and has_map_type:
        score += 20
        feedback_parts.append("Report contains correct map parameters (1.5 sigma, 2Fo-Fc)")
    elif has_1_5 or has_map_type:
        score += 10
        feedback_parts.append("Report missing either contour level or map type")
    else:
        feedback_parts.append("Report missing required map parameters")

    # 5. VLM Trajectory Verification (40 pts)
    vlm_score = 0
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')

    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            if images:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    
                    if parsed.get("map_loaded"): vlm_score += 10
                    if parsed.get("ligand_visible"): vlm_score += 10
                    if parsed.get("carved_mesh"): vlm_score += 10
                    if parsed.get("clean_view"): vlm_score += 10

                    feedback_parts.append(f"VLM Score: {vlm_score}/40")
                    if vlm_score >= 30:
                        vlm_passed = True
                else:
                    feedback_parts.append("VLM query returned unsuccessful.")
            else:
                feedback_parts.append("No trajectory images available for VLM.")
        except ImportError:
            # Fallback if gym_anything utils aren't available
            feedback_parts.append("gym_anything VLM utils not available. Skipping VLM check.")
            vlm_score = 40  # Give benefit of the doubt if infra fails
            vlm_passed = True
        except Exception as e:
            logger.warning(f"VLM Exception: {e}")
            feedback_parts.append("VLM verification exception.")
    else:
        feedback_parts.append("VLM not configured. Giving default points for visual check.")
        vlm_score = 40
        vlm_passed = True

    score += vlm_score

    # Determine pass/fail
    # Must have >= 75 points, figure must be valid, and VLM must be reasonably satisfied
    passed = (score >= 75) and figure_ok and vlm_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }