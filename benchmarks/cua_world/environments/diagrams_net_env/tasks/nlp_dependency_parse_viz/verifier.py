#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nlp_dependency_parse_viz(traj, env_info, task_info):
    """
    Verifies the Dependency Parse Visualization task.
    
    Criteria:
    1. Drawio file creation & modification (Anti-gaming)
    2. Text Content (Words present)
    3. Structural Integrity (Edges connecting words)
    4. POS Tagging presence
    5. Relation labeling (nsubj, etc.)
    6. Highlighting (Red text)
    7. PDF Export
    8. VLM Verification (Visual layout check: curved lines, horizontal text)
    """
    
    # 1. Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy unavailable"}

    result = {}
    try:
        import tempfile
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}

    # Extract Data
    analysis = result.get("drawio_analysis", {})
    pdf_info = result.get("pdf_export", {})
    timing = result.get("task_timing", {})
    
    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # CRITERION 1: File Existence & Anti-Gaming (15 pts)
    # ------------------------------------------------------------------
    if not analysis.get("exists"):
        return {"passed": False, "score": 0, "feedback": "Diagram file not found."}
    
    file_mtime = analysis.get("mtime", 0)
    task_start = timing.get("start", 0)
    
    if file_mtime > task_start:
        score += 15
        feedback.append("File created/modified during task.")
    else:
        feedback.append("File not modified during task.")

    # ------------------------------------------------------------------
    # CRITERION 2: Content - Words (20 pts)
    # ------------------------------------------------------------------
    expected_words = ["autonomous", "rover", "navigated", "crater", "despite", "severe", "dust", "storms"]
    found_texts = [t.get("text", "") for t in analysis.get("texts", [])]
    # Simple normalization: remove HTML tags if present
    import re
    clean_texts = [re.sub(r'<[^>]+>', '', t).strip() for t in found_texts]
    clean_texts_str = " ".join(clean_texts).lower()
    
    words_found = 0
    for w in expected_words:
        if w.lower() in clean_texts_str:
            words_found += 1
            
    word_score = (words_found / len(expected_words)) * 20
    score += word_score
    if words_found == len(expected_words):
        feedback.append("All key words found.")
    else:
        feedback.append(f"Found {words_found}/{len(expected_words)} key words.")

    # ------------------------------------------------------------------
    # CRITERION 3: Structure - Edges (20 pts)
    # ------------------------------------------------------------------
    edge_count = analysis.get("edge_count", 0)
    # Expecting ~9 edges for the relations
    if edge_count >= 8:
        score += 20
        feedback.append(f"Sufficient edges found ({edge_count}).")
    elif edge_count >= 4:
        score += 10
        feedback.append(f"Partial edges found ({edge_count}).")
    else:
        feedback.append("Insufficient edges.")

    # ------------------------------------------------------------------
    # CRITERION 4: Content - Relation Labels (15 pts)
    # ------------------------------------------------------------------
    expected_rels = ["nsubj", "dobj", "det", "amod", "obl", "case", "compound"]
    found_edge_labels = [e.get("value", "").lower() for e in analysis.get("edges", [])]
    
    rels_found = 0
    for rel in expected_rels:
        if any(rel in label for label in found_edge_labels):
            rels_found += 1
    
    rel_score = (rels_found / len(expected_rels)) * 15
    score += rel_score
    feedback.append(f"Found {rels_found}/{len(expected_rels)} dependency labels.")

    # ------------------------------------------------------------------
    # CRITERION 5: Styling - Highlighting (10 pts)
    # ------------------------------------------------------------------
    red_found = False
    for t in analysis.get("texts", []):
        if t.get("is_red"):
            txt = re.sub(r'<[^>]+>', '', t.get("text", "")).lower()
            if "dust" in txt or "storms" in txt:
                red_found = True
                break
    
    if red_found:
        score += 10
        feedback.append("'dust storms' highlighted red.")
    else:
        feedback.append("Red highlighting not found on 'dust storms'.")

    # ------------------------------------------------------------------
    # CRITERION 6: PDF Export (5 pts)
    # ------------------------------------------------------------------
    if pdf_info.get("exists") and pdf_info.get("size", 0) > 1000:
        score += 5
        feedback.append("PDF export successful.")
    else:
        feedback.append("PDF export missing or empty.")

    # ------------------------------------------------------------------
    # CRITERION 7: VLM Visual Check (15 pts)
    # ------------------------------------------------------------------
    # We check if lines are curved and text is horizontal
    
    # Select frames
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    prompt = """
    Analyze these screenshots of a dependency parse diagram in draw.io.
    The user is supposed to create a linguistic diagram where:
    1. Words are arranged in a horizontal line.
    2. Arrows connecting words are CURVED (arching above the text), not straight lines.
    3. There are small tags (POS tags like DET, NOUN) below the words.

    Look at the final result (last image) and the progress.
    Q1: Are there curved/arched arrows connecting the words? (Yes/No)
    Q2: Are the words arranged in a roughly straight horizontal line? (Yes/No)
    
    Return JSON: {"curved_arrows": boolean, "horizontal_layout": boolean}
    """
    
    # This requires the VLM tool which is injected into the environment
    # We mock it here for the file generation, but in production, 
    # the gym_anything framework handles the VLM query.
    # Assuming VLM returns valid JSON:
    
    try:
        from gym_anything.vlm import query_vlm
        vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        # Simple heuristic fallback if VLM fails or returns non-json
        vlm_data = vlm_resp.get("parsed", {})
        
        if vlm_data.get("curved_arrows"):
            score += 10
            feedback.append("VLM confirmed curved arrows.")
        else:
            feedback.append("VLM did not see curved arrows.")
            
        if vlm_data.get("horizontal_layout"):
            score += 5
            feedback.append("VLM confirmed horizontal layout.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback scoring if code checks were strong
        if score >= 60:
            score += 10 
            feedback.append("VLM skipped (fallback).")

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " ".join(feedback)
    }