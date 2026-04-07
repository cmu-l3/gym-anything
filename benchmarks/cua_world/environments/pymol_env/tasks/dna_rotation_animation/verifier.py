#!/usr/bin/env python3
"""
Verifier for the DNA Double Helix Conformational Animation task (1BNA).

Scoring (100 points total):
  20 pts - Report contains the correct sequence (CGCGAATTCGCG) for Chain A.
  15 pts - Report correctly identifies 12 base pairs.
  30 pts - >= 60 valid, non-empty (>15KB) PNG frames generated post-task-start.
  15 pts - Frame variance check: The frames are not completely identical (proving animation).
  20 pts - VLM verification: Trajectory shows DNA colored by strand with cartoon/sticks.

Pass threshold: 70/100

Anti-gaming:
  - Timestamp checking ensures frames were generated during the task.
  - Size gate (>15KB) ensures frames aren't pure black/blank.
  - Variance check (comparing file sizes of frames) prevents saving 1 static image 120 times.
  - VLM evaluates trajectory frames, not just the final screenshot.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's trajectory for a PyMOL animation task.
The agent was asked to visualize a B-DNA double helix (PDB: 1BNA) with a cartoon and stick representation, and color the two complementary strands distinctly.

Look at the sequence of images provided from the agent's screen.
1. Is a DNA double helix clearly visible in the PyMOL viewport?
2. Are the two DNA strands colored with distinct colors (e.g., one blue, one red)?
3. Does the representation include both a backbone representation (like cartoon/ribbon) and base representation (like sticks/lines)?

Respond with JSON:
{
    "dna_visible": true/false,
    "distinct_strands_colored": true/false,
    "good_representation": true/false,
    "reasoning": "brief explanation"
}
"""


def verify_dna_rotation_animation(traj, env_info, task_info):
    """Verify the DNA rotation animation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/dna_animation_result.json')
    expected_seq = metadata.get('expected_sequence', 'CGCGAATTCGCG')
    min_frames = metadata.get('min_frames', 60)
    min_frame_size = metadata.get('min_frame_size_bytes', 15000)

    # 1. Retrieve the exported JSON result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1 & 2: Report Content (35 pts) ---
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').upper()
    # Remove all whitespace to make sequence matching robust
    clean_content = re.sub(r'\s+', '', report_content)

    if report_exists:
        # Sequence (20 pts)
        if expected_seq in clean_content or "DCDGDCDGDADADTDTDCDGDC" in clean_content:
            score += 20
            parts.append("Correct Chain A sequence found in report.")
        else:
            parts.append("Sequence missing or incorrect in report.")
            
        # BP Count (15 pts)
        if "12" in clean_content:
            score += 15
            parts.append("Correct base pair count (12) found.")
        else:
            parts.append("Base pair count missing or incorrect.")
    else:
        parts.append("Report file not found at /home/ga/PyMOL_Data/1bna_report.txt.")

    # --- Criterion 3: Frame Batch Generation (30 pts) ---
    frames = result.get('frames', [])
    valid_frames = [f for f in frames if f['size_bytes'] > min_frame_size]

    if len(valid_frames) >= min_frames:
        score += 30
        parts.append(f"Successfully generated {len(valid_frames)} valid PNG frames.")
    elif len(valid_frames) > 0:
        score += int(30 * (len(valid_frames) / min_frames))
        parts.append(f"Generated {len(valid_frames)} valid frames (expected \u2265{min_frames}).")
    else:
        parts.append(f"No valid frames >{min_frame_size//1024}KB found generated after task start.")

    # --- Criterion 4: Animation Variance (15 pts) ---
    # To prove it's an animation and not just the same static frame saved repeatedly,
    # we check if there are variations in the file sizes.
    if len(valid_frames) >= 10:
        sizes = set([f['size_bytes'] for f in valid_frames])
        if len(sizes) > 1:
            score += 15
            parts.append("Frame variance confirmed (rotation/animation observed).")
        else:
            parts.append("All frames are perfectly identical in size (static image, no rotation).")
    else:
        parts.append("Not enough frames to verify animation variance.")

    # --- Criterion 5: VLM Trajectory Verification (20 pts) ---
    # Check the visual representation and coloring
    import sys
    sys.path.insert(0, str(os.path.join(os.path.dirname(__file__), '../../..')))
    
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames_for_vlm = sample_trajectory_frames(traj, n=4)
        if frames_for_vlm:
            vlm_result = query_vlm(images=frames_for_vlm, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                vlm_score = 0
                if parsed.get('dna_visible', False):
                    vlm_score += 5
                if parsed.get('distinct_strands_colored', False):
                    vlm_score += 10
                if parsed.get('good_representation', False):
                    vlm_score += 5
                
                score += vlm_score
                parts.append(f"VLM Visual Check: {vlm_score}/20 pts.")
            else:
                parts.append("VLM query failed or returned no result.")
        else:
            parts.append("No trajectory frames available for VLM.")
    except ImportError:
        logger.warning("VLM utilities not available, skipping VLM check.")
        parts.append("VLM visual verification skipped (framework error).")
    except Exception as e:
        logger.error(f"Error during VLM verification: {e}")
        parts.append("VLM verification encountered an error.")

    # Determine pass/fail
    passed = score >= 70 and len(valid_frames) >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }