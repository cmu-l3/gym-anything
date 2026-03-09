#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tech_radar_quarterly_review(traj, env_info, task_info):
    """
    Verifies the Technology Radar task.
    
    Scoring:
    - 5pts: File modified (anti-gaming)
    - 30pts: Content (Technology labels present)
    - 15pts: Styling (Colors applied)
    - 10pts: Legend created (text labels found)
    - 10pts: Shape count (sufficient shapes added)
    - 20pts: PNG Export (valid file)
    - 10pts: VLM Visual Confirmation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    metadata = task_info.get('metadata', {})
    expected_techs = set(t.lower() for t in metadata.get('tech_names', []))
    
    # Criterion 1: File Modification (5 pts)
    if result.get('file_modified'):
        score += 5
    else:
        feedback.append("Draw.io file was not saved/modified.")

    # Criterion 2: Content/Labels (30 pts)
    extracted_labels = [l.lower() for l in result.get('extracted_labels', [])]
    found_techs = 0
    missing_techs = []
    
    # We check for substring matches because user labels might be messy (e.g. "RAG" vs "Retrieval Augmented...")
    # But for robustness, let's look for key terms.
    for tech in expected_techs:
        # Check if any extracted label contains a significant part of the tech name
        # Heuristic: split tech into words, check if largest word exists in labels
        longest_word = max(tech.split(), key=len)
        if any(longest_word in label for label in extracted_labels):
            found_techs += 1
        else:
            missing_techs.append(tech)
            
    # Score logic: proportional
    tech_score = min(30, int((found_techs / 20) * 30))
    score += tech_score
    if len(missing_techs) > 5:
        feedback.append(f"Missing many technologies (Found {found_techs}/20). Examples: {', '.join(missing_techs[:3])}")

    # Criterion 3: Color Coding (15 pts)
    # We expect 4 specific colors, but we'll accept if at least 3 distinct non-white colors are used
    colors = result.get('extracted_colors', [])
    if len(colors) >= 3:
        score += 15
    elif len(colors) > 0:
        score += 5
        feedback.append("Insufficient color coding used.")
    else:
        feedback.append("No color coding detected.")

    # Criterion 4: Legend Creation (10 pts)
    # Check if legend labels exist in extracted text
    legend_terms = ["new", "moved in", "moved out", "no change"]
    found_legend_terms = sum(1 for term in legend_terms if any(term in label for label in extracted_labels))
    if found_legend_terms >= 3:
        score += 10
    else:
        feedback.append("Legend text labels missing.")

    # Criterion 5: Shape Count (10 pts)
    # Initial is ~16 (template). Expected ~44 (20 techs + 4 legend items + template).
    # We'll set a threshold of +20 shapes from initial.
    initial = result.get('initial_shape_count', 16)
    current = result.get('shape_count', 0)
    if current >= (initial + 20):
        score += 10
    else:
        feedback.append(f"Not enough shapes added (Delta: {current - initial}).")

    # Criterion 6: PNG Export (20 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 10000: # >10KB
        score += 20
    else:
        feedback.append("Valid PNG export not found.")

    # Criterion 7: VLM Visual Confirmation (10 pts)
    # Check trajectory to ensure they didn't just paste a screenshot
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    
    if final:
        vlm_images = frames + [final]
        prompt = """
        Review these screenshots of a user editing a diagram in draw.io.
        
        1. Do you see a 'Technology Radar' diagram (concentric circles/sectors)?
        2. Are there multiple small shapes (rectangles/ellipses) scattered across the radar?
        3. Do the shapes have different colors (green, blue, orange, gray)?
        4. Does it look like the user actively added these shapes (vs just opening a finished file)?
        
        Answer YES only if it looks like a legitimate attempt at creating the diagram.
        """
        try:
            vlm_res = query_vlm(images=vlm_images, prompt=prompt)
            if vlm_res and "yes" in vlm_res.lower():
                score += 10
            else:
                feedback.append("VLM did not confirm visual structure.")
        except Exception:
            # Fallback if VLM fails: grant points if shape count is high
            if current >= (initial + 24):
                score += 10
                feedback.append("(VLM unavailable, fell back to shape count)")

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " ".join(feedback)
    }