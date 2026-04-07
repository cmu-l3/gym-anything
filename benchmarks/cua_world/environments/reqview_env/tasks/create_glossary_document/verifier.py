#!/usr/bin/env python3
"""
Verifier for create_glossary_document task.

Criteria:
1. Document file 'documents/GLOSS.json' exists.
2. Document ID is 'GLOSS' and Name is 'Glossary'.
3. Document contains 5 items.
4. Items match the expected Terms (Heading) and Definitions (Text).
"""

import json
import os
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _strip_html(text):
    """Remove HTML tags from text."""
    if not text:
        return ""
    return re.sub(r'<[^>]+>', '', str(text)).strip()

def verify_create_glossary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_content = metadata.get('expected_content', [])
    
    # 1. Retrieve Task Result Metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result metadata"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not task_result.get("output_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "GLOSS document not found in project. Did you create it with ID 'GLOSS'?"
        }

    # 2. Retrieve the Actual GLOSS.json file
    remote_path = task_result["output_path"]
    temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_doc.name)
        with open(temp_doc.name, 'r') as f:
            doc_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse GLOSS.json: {e}"}
    finally:
        if os.path.exists(temp_doc.name):
            os.unlink(temp_doc.name)

    score = 0
    feedback = []

    # --- CRITERION 1: Document Metadata (20 pts) ---
    doc_id = doc_data.get("id", "")
    doc_name = doc_data.get("name", "")
    
    if doc_id == "GLOSS":
        score += 10
        feedback.append("Document ID correct")
    else:
        feedback.append(f"Document ID mismatch (expected 'GLOSS', got '{doc_id}')")

    if doc_name == "Glossary":
        score += 10
        feedback.append("Document Name correct")
    else:
        feedback.append(f"Document Name mismatch (expected 'Glossary', got '{doc_name}')")

    # --- CRITERION 2: Children Count (20 pts) ---
    children = doc_data.get("children", [])
    if len(children) == 5:
        score += 20
        feedback.append("Correct number of terms (5)")
    else:
        feedback.append(f"Incorrect term count (expected 5, got {len(children)})")

    # --- CRITERION 3: Content Verification (60 pts) ---
    # We allow slight fuzzy matching and order independence
    content_score = 0
    max_content_score = 60
    item_pts = max_content_score / 5
    
    matched_terms = []
    
    for expected in expected_content:
        exp_term = expected["term"].lower()
        exp_def_fragment = expected["definition"][:20].lower() # Match start of definition
        
        found = False
        for child in children:
            # Check Heading (Term)
            child_heading = _strip_html(child.get("heading", "")).lower()
            # Check Text (Definition)
            child_text = _strip_html(child.get("text", "")).lower()
            
            # Match if heading matches term AND text contains part of definition
            if exp_term in child_heading and exp_def_fragment in child_text:
                content_score += item_pts
                matched_terms.append(expected["term"])
                found = True
                break
            
            # Graceful fallback: maybe they put definition in heading or vice versa?
            # If swapped: Heading has definition, Text has term (Structure penalty applies later implicitly)
            if exp_term in child_text and exp_def_fragment in child_heading:
                content_score += (item_pts * 0.5) # Half points for swapped fields
                feedback.append(f"Fields swapped for '{expected['term']}'")
                found = True
                break
        
        if not found:
            feedback.append(f"Missing or incorrect term: {expected['term']}")

    score += int(content_score)
    feedback.append(f"Matched terms: {len(matched_terms)}/5")

    # --- VLM Verification (Anti-Gaming / Process Check) ---
    # Only if score is borderline or for additional confirmation
    if score >= 40:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Review these screenshots of a user using ReqView. "
            "1. Did the user open a 'Create Document' dialog? "
            "2. Is a document named 'Glossary' visible in the project tree (left panel)? "
            "3. Are there definitions like 'MQTT', 'Broker' visible in the main view? "
            "Answer with JSON: {'create_dialog_seen': bool, 'glossary_in_tree': bool, 'terms_visible': bool}"
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("glossary_in_tree") or parsed.get("terms_visible"):
                # Bonus or validation
                pass 
            else:
                feedback.append("VLM could not visually confirm Glossary in UI")
        except Exception:
            pass # VLM fail shouldn't fail task if programmatic check passed

    # Final Pass logic
    passed = score >= 70 and doc_id == "GLOSS"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }