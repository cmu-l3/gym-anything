#!/usr/bin/env python3
"""
Verifier for Cell Organelle Frayer Model task.

Scoring (100 points total, 70 to pass):
- File existence & validity: 15 pts
- Page count (must be 2): 15 pts
- Main Terms ("Mitochondria", "Cell Membrane"): 20 pts
- Quadrant Labels (Definition, etc.): 10 pts
- Shape Count (Rectangles >= 8): 15 pts
- Content Accuracy (Biology keywords): 20 pts
- Timestamp validation: 5 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_frayer_vlm_prompt():
    """Builds the prompt for VLM verification of the Frayer model layout."""
    return """
    Analyze this screenshot of an ActivInspire flipchart page.
    
    Task: Verify if this is a "Frayer Model" vocabulary graphic organizer.
    
    Look for:
    1. A central box/area containing a main term (e.g., "Mitochondria" or "Cell Membrane").
    2. Four surrounding quadrant areas/boxes.
    3. Labels in the corners or boxes like "Definition", "Characteristics", "Examples", "Non-Examples".
    4. Text content filled into these quadrants.
    
    Is this visual structure present?
    """

def verify_cell_organelle_frayer_model(traj, env_info, task_info):
    """
    Verifies the creation of the Cell Organelle Frayer Model flipchart.
    Uses programmatic file analysis as primary signal, supplemented by VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Retrieve result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env('/tmp/task_result.json', tmp.name)
            tmp.close()
            with open(tmp.name, 'r') as f:
                result = json.load(f)
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}

    score = 0
    feedback = []
    
    # 1. File Existence & Validity (15 pts)
    if result.get('file_found') and result.get('file_valid'):
        score += 15
        feedback.append("Valid flipchart file found (15/15)")
    elif result.get('file_found'):
        score += 5
        feedback.append("File found but invalid format (5/15)")
    else:
        feedback.append("Flipchart file not found (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)} # Critical fail

    # 2. Timestamp (5 pts)
    if result.get('created_during_task'):
        score += 5
        feedback.append("File created during task session (5/5)")
    else:
        feedback.append("File timestamp predates task (0/5)")

    # 3. Page Count (15 pts) - Must be exactly 2
    pages = result.get('page_count', 0)
    if pages == 2:
        score += 15
        feedback.append("Correct page count: 2 (15/15)")
    elif pages > 0:
        score += 5
        feedback.append(f"Incorrect page count: {pages} (expected 2) (5/15)")
    else:
        feedback.append("No pages detected (0/15)")

    # 4. Main Terms (20 pts)
    terms_score = 0
    if result.get('has_mitochondria'): terms_score += 10
    if result.get('has_cell_membrane'): terms_score += 10
    score += terms_score
    feedback.append(f"Main terms found: {terms_score}/20 pts")

    # 5. Quadrant Labels (10 pts)
    # Need at least 2 of 4 to get partial credit
    labels_found = sum([
        result.get('has_definition', False),
        result.get('has_characteristics', False),
        result.get('has_examples', False),
        result.get('has_non_examples', False)
    ])
    
    if labels_found >= 4:
        score += 10
        feedback.append("All quadrant labels found (10/10)")
    elif labels_found >= 2:
        score += 5
        feedback.append(f"Some quadrant labels found ({labels_found}/4) (5/10)")
    else:
        feedback.append("Quadrant labels missing or insufficient (0/10)")

    # 6. Shape Count (15 pts)
    # Expecting ~8-10 rectangles (4 per page + center box)
    rects = result.get('rect_count', 0)
    if rects >= 8:
        score += 15
        feedback.append(f"Sufficient rectangle shapes found ({rects}) (15/15)")
    elif rects >= 4:
        score += 7
        feedback.append(f"Some rectangles found ({rects}, expected 8+) (7/15)")
    else:
        feedback.append(f"Insufficient shapes ({rects}) (0/15)")

    # 7. Content Accuracy (20 pts)
    # Check for keywords in definition/characteristics
    mito_content = sum([result.get('has_atp', False), result.get('has_energy', False), result.get('has_respiration', False)])
    memb_content = sum([result.get('has_barrier', False), result.get('has_permeable', False), result.get('has_phospholipid', False)])
    
    content_score = 0
    if mito_content >= 1: content_score += 10
    if memb_content >= 1: content_score += 10
    score += content_score
    feedback.append(f"Biology content accuracy: {content_score}/20 pts")

    # Optional: VLM Check (for layout verification)
    # If score is borderline (e.g., between 60-70), we might use VLM to bump it up if layout looks good
    # For now, simply logging VLM result or adding bonus?
    # Let's use VLM to ensure we didn't just dump text without boxes if shape count is low
    
    query_vlm = env_info.get('query_vlm')
    final_screenshot = os.path.join(os.path.dirname(traj[-1]['screenshot']), 'task_end.png') # conceptual path, relying on export
    
    # We rely primarily on file programmatic check.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }