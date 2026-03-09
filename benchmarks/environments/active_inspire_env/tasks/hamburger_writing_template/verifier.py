#!/usr/bin/env python3
"""
Verifier for Hamburger Writing Template task.

Scoring Breakdown (100 points total):
1. File Validation (10 pts): File exists, valid format, created during task.
2. Page Structure (10 pts): Exactly 3 pages.
3. Content - Page 1 (10 pts): Title "Hamburger Paragraph".
4. Content - Page 2 (45 pts):
   - "Topic Sentence" & "Conclusion" labels (10 pts)
   - "Detail 1/2/3" labels (10 pts)
   - At least 5 Shapes (buns + fillings) (15 pts)
   - VLM visual check for burger structure (10 pts)
5. Content - Page 3 (25 pts):
   - "My Paragraph" title (10 pts)
   - At least 3 Lines (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hamburger_writing_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load Programmatic Results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result load failed: {str(e)}"}

    score = 0
    feedback = []
    
    # --- Check 1: File Existence & Validity (10 pts) ---
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 10
        feedback.append("Valid flipchart file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found or invalid."}

    # --- Check 2: Page Count (10 pts) ---
    pc = result.get('page_count', 0)
    if pc == 3:
        score += 10
        feedback.append("Correct page count (3).")
    elif pc > 0:
        score += 5
        feedback.append(f"Incorrect page count ({pc}), expected 3.")
    else:
        feedback.append("Flipchart is empty.")

    # --- Check 3: Page 1 Title (10 pts) ---
    txt = result.get('text_content', {})
    if txt.get('has_title'):
        score += 10
        feedback.append("Title page correct.")
    else:
        feedback.append("Missing title 'Hamburger Paragraph'.")

    # --- Check 4: Page 2 Burger Diagram (35 pts programmatic + 10 pts VLM) ---
    # Labels
    labels_score = 0
    if txt.get('has_topic') and txt.get('has_conclusion'): labels_score += 10
    elif txt.get('has_topic') or txt.get('has_conclusion'): labels_score += 5
    
    if txt.get('has_detail1') and txt.get('has_detail2') and txt.get('has_detail3'): labels_score += 10
    elif txt.get('has_detail1') or txt.get('has_detail2') or txt.get('has_detail3'): labels_score += 5
    
    score += labels_score
    if labels_score == 20: feedback.append("All burger labels present.")
    elif labels_score > 0: feedback.append("Some burger labels missing.")

    # Shapes (Bun/Fillings)
    sc = result.get('shape_count', 0)
    if sc >= 5:
        score += 15
        feedback.append(f"Burger shapes detected ({sc}).")
    elif sc >= 3:
        score += 8
        feedback.append(f"Partial burger shapes detected ({sc}).")
    else:
        feedback.append(f"Insufficient shapes for burger ({sc}).")

    # --- Check 5: Page 3 Practice (25 pts) ---
    if txt.get('has_practice_title'):
        score += 10
        feedback.append("Practice page title present.")
    
    lc = result.get('line_count', 0)
    if lc >= 3:
        score += 15
        feedback.append(f"Writing lines detected ({lc}).")
    elif lc >= 1:
        score += 5
        feedback.append(f"Few writing lines detected ({lc}).")
    else:
        feedback.append("No writing lines found on Page 3.")

    # --- VLM Verification (Visual Check) ---
    # Only run if we have a decent score already, to verify the layout
    if score > 40 and query_vlm:
        from gym_anything.vlm import get_final_screenshot
        final_ss = get_final_screenshot(traj)
        
        if final_ss:
            prompt = """
            Analyze this screenshot of an educational software (ActivInspire).
            Does it show a 'Hamburger Paragraph' diagram or a writing practice page?
            
            Look for:
            1. A stack of shapes resembling a burger (buns and fillings).
            2. Text labels like 'Topic Sentence', 'Detail', 'Conclusion'.
            3. OR a page with horizontal lines for writing.
            
            Return JSON: {"is_hamburger_diagram": bool, "shapes_stacked": bool, "confidence": "high/med/low"}
            """
            vlm_res = query_vlm(prompt=prompt, image=final_ss)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_hamburger_diagram') or parsed.get('shapes_stacked'):
                    score += 10
                    feedback.append("VLM confirmed visual diagram structure.")
                else:
                    feedback.append("VLM could not visually confirm burger diagram.")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }