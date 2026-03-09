#!/usr/bin/env python3
"""
Verifier for Earth's Layers Diagram task.

SCORING CRITERIA (100 points total):
1. File Existence & Validity (15 pts)
2. Page Count == 2 (10 pts)
3. Diagram Content (Page 1) (40 pts):
   - 4 concentric circles (Shapes >= 4) (10 pts)
   - Labels: Crust, Mantle, Outer Core, Inner Core (10 pts each, checked via XML text)
4. Table Content (Page 2) (15 pts):
   - Table structure (Rectangles >= 4) (5 pts)
   - Data keywords present (Thickness/State/Solid/Liquid) (10 pts)
5. VLM Verification (20 pts):
   - Visually confirms concentric circles and table layout.

PASS THRESHOLD: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine the screenshots of this ActivInspire session.
The user was asked to create a 2-page flipchart about Earth's Layers.
Page 1 should show a Cross-Section Diagram (concentric circles).
Page 2 should show a Properties Table.

Look at the images and answer:
1. Is there a diagram with concentric circles (circles inside circles) visible?
2. Are there distinct colors used for the layers?
3. Is there a table or grid structure visible (rows/columns)?
4. Is there text labeling 'Crust', 'Mantle', 'Core'?

Return JSON:
{
  "concentric_diagram_visible": true/false,
  "distinct_colors": true/false,
  "table_structure_visible": true/false,
  "labels_visible": true/false,
  "confidence": "high/medium/low"
}
"""

def verify_earths_layers_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load JSON Result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # Criterion 1: File Existence & Validity (15 pts)
    if result.get('file_found') and result.get('file_valid'):
        score += 15
        feedback.append("Valid flipchart file found (+15)")
    elif result.get('file_found'):
        score += 5
        feedback.append("File found but invalid format (+5)")
    else:
        return {"passed": False, "score": 0, "feedback": "No file saved"}

    # Criterion 2: Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 2:
        score += 10
        feedback.append("Correct page count (2) (+10)")
    else:
        feedback.append(f"Incorrect page count: {page_count} (expected 2)")

    # Criterion 3: Diagram Labels (30 pts)
    # Check for 4 key terms: Crust, Mantle, Outer Core, Inner Core
    # We allocated 10 pts for shapes + 30 pts for labels here in logic (adjusted from header comment)
    terms_found = 0
    if result.get('has_crust'): terms_found += 1
    if result.get('has_mantle'): terms_found += 1
    if result.get('has_outer_core'): terms_found += 1
    if result.get('has_inner_core'): terms_found += 1
    
    # 7.5 pts per term -> 30 pts total
    term_score = terms_found * 7.5
    score += term_score
    if terms_found > 0:
        feedback.append(f"Found {terms_found}/4 layer labels (+{term_score})")

    # Criterion 4: Diagram Shapes (10 pts)
    # Expecting concentric circles (at least 3-4)
    circles = result.get('circle_count', 0)
    if circles >= 4:
        score += 10
        feedback.append("Found 4+ circle shapes (+10)")
    elif circles >= 2:
        score += 5
        feedback.append("Found some circle shapes (+5)")
    else:
        feedback.append("Missing diagram shapes")

    # Criterion 5: Table Content (15 pts)
    # Rectangles for table grid + Data keywords
    rects = result.get('rect_count', 0)
    has_data = result.get('has_table_data')
    
    if rects >= 4: # minimal grid
        score += 5
        feedback.append("Table structure found (+5)")
    
    if has_data:
        score += 10
        feedback.append("Table data keywords found (+10)")

    # Criterion 6: VLM Verification (20 pts)
    vlm_score = 0
    if query_vlm:
        from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
        final_img = get_final_screenshot(traj)
        frames = sample_trajectory_frames(traj, 2)
        images = frames + [final_img] if final_img else frames
        
        if images:
            try:
                vlm_resp = query_vlm(prompt=build_vlm_prompt(), images=images)
                if vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    if parsed.get('concentric_diagram_visible'): vlm_score += 10
                    if parsed.get('table_structure_visible'): vlm_score += 5
                    if parsed.get('distinct_colors'): vlm_score += 5
                    feedback.append(f"Visual verification score: {vlm_score}/20")
            except Exception as e:
                feedback.append(f"VLM check failed: {e}")
    
    score += vlm_score

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback)
    }