#!/usr/bin/env python3
"""
Verifier for states_of_matter_model task.

Scoring (100 points total, pass at 70):
1. File exists & valid (20 pts)
2. Page count == 3 (15 pts)
3. Text labels correct (Solid, Liquid, Gas) (15 pts)
4. Shape count: Rectangles >= 3 (10 pts)
5. Shape count: Circles >= 23 (9+9+5) (20 pts)
6. VLM Visual Verification (Color & Layout) (20 pts)
   - Checks if particles are inside containers
   - Checks for Red/Blue color usage
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_particle_model_prompt():
    return """Examine this screenshot of an ActivInspire flipchart.
Task: Verify a particle model diagram for States of Matter (Solid, Liquid, Gas).

Check for these visual indicators:
1. CONTAINERS: Are there rectangular boxes acting as containers?
2. PARTICLES: Are there multiple small circles inside these containers?
3. COLORS: 
   - Do you see BLUE circles (likely for Solid/Liquid)?
   - Do you see RED circles (likely for Gas)?
4. LABELS: Do you see text labels like "Solid", "Liquid", or "Gas"?

Respond in JSON format:
{
    "containers_visible": true/false,
    "particles_visible": true/false,
    "blue_particles_seen": true/false,
    "red_particles_seen": true/false,
    "text_labels_seen": true/false,
    "particles_inside_containers": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""

def verify_states_of_matter_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load Programmatic Results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # Criterion 1: File Existence (20 pts)
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 20
        feedback.append("Valid flipchart created.")
    else:
        feedback.append("File not found or invalid.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Page Count (15 pts)
    page_count = result.get('page_count', 0)
    if page_count == 3:
        score += 15
        feedback.append("Correct page count (3).")
    elif page_count > 0:
        score += 5
        feedback.append(f"Incorrect page count ({page_count}).")

    # Criterion 3: Text Labels (15 pts)
    text_hits = 0
    if result.get('has_solid'): text_hits += 1
    if result.get('has_liquid'): text_hits += 1
    if result.get('has_gas'): text_hits += 1
    
    if text_hits == 3:
        score += 15
        feedback.append("All text labels found.")
    elif text_hits > 0:
        score += (text_hits * 5)
        feedback.append(f"Found {text_hits}/3 text labels.")

    # Criterion 4: Container Rectangles (10 pts)
    rects = result.get('rect_count', 0)
    if rects >= 3:
        score += 10
        feedback.append(f"Found {rects} container rectangles.")
    else:
        feedback.append(f"Missing container rectangles (found {rects}).")

    # Criterion 5: Particle Circles (20 pts)
    circles = result.get('circle_count', 0)
    # 9 + 9 + 5 = 23 expected
    if circles >= 23:
        score += 20
        feedback.append(f"Found {circles} particle circles (Good).")
    elif circles >= 10:
        score += 10
        feedback.append(f"Found partial particle set ({circles}).")
    else:
        feedback.append(f"Too few particles found ({circles}).")

    # Criterion 6: Visual/Color Verification (20 pts)
    # We use VLM for this as programmatic color extraction is heuristic/flaky
    vlm_score = 0
    
    # Try VLM if available
    from gym_anything.vlm import get_final_screenshot
    screenshot = get_final_screenshot(traj)
    
    if query_vlm and screenshot:
        vlm_resp = query_vlm(prompt=build_particle_model_prompt(), image=screenshot)
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            # Check layout
            if parsed.get('particles_inside_containers'):
                vlm_score += 10
                feedback.append("VLM: Particles appear inside containers.")
            
            # Check colors
            colors_ok = False
            # Check VLM seeing colors OR programmatic heuristic finding colors
            if parsed.get('blue_particles_seen') or result.get('has_blue_color'):
                if parsed.get('red_particles_seen') or result.get('has_red_color'):
                    colors_ok = True
            
            if colors_ok:
                vlm_score += 10
                feedback.append("Colors (Red/Blue) verified.")
            else:
                feedback.append("Colors could not be fully verified.")
        else:
            feedback.append("VLM analysis failed.")
    else:
        # Fallback if VLM not available: trust programmatic color hints partially
        if result.get('has_red_color') and result.get('has_blue_color'):
            vlm_score += 10
            feedback.append("Programmatic check found color attributes.")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }