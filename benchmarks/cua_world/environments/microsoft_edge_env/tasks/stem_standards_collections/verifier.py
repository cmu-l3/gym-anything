#!/usr/bin/env python3
"""
Verifier for STEM Standards Collections task.
Verifies document content, browser history, collections usage, and VLM trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

def verify_stem_standards_collections(traj, env_info, task_info):
    """
    Verify the STEM Standards Research task.
    
    Scoring Breakdown (100 pts):
    - 10 pts: Document exists and modified after task start
    - 40 pts: Document content (10 pts per correct source mentioned)
    - 20 pts: Browser history (5 pts per correct domain visited)
    - 10 pts: Collections directory modified (programmatic check)
    - 20 pts: VLM Verification (Visual confirmation of Collections panel/sidebar usage)
    
    Pass Threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Document Existence (10 pts)
    doc = result.get("document", {})
    if doc.get("exists") and doc.get("modified_after_start"):
        score += 10
        feedback.append("Reference document created.")
    else:
        feedback.append("Reference document missing or not created during task.")

    # 2. Document Content (40 pts)
    content = doc.get("content_check", {})
    sources_found = 0
    for source, found in content.items():
        if found:
            score += 10
            sources_found += 1
            feedback.append(f"Document mentions {source}.")
        else:
            feedback.append(f"Document missing mention of {source}.")

    # 3. Browser History (20 pts)
    history = result.get("history", {})
    domains_visited = 0
    target_domains = ["nextgenscience.org", "corestandards.org", "iste.org", "nces.ed.gov"]
    
    for domain in target_domains:
        if history.get(domain, False):
            score += 5
            domains_visited += 1
    
    if domains_visited > 0:
        feedback.append(f"Visited {domains_visited}/4 target domains.")
    else:
        feedback.append("No target domains visited.")

    # 4. Collections Directory Check (10 pts)
    collections = result.get("collections", {})
    if collections.get("modified", False):
        score += 10
        feedback.append("Collections data modified.")
    else:
        feedback.append("No modification detected in Collections storage (Programmatic check failed).")

    # 5. VLM Verification (20 pts)
    # Check if the Collections sidebar/panel was actually opened and used.
    # We look at trajectory frames.
    
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Analyze these screenshots of a Microsoft Edge browser session.
        I am looking for evidence that the user interacted with the "Collections" feature.
        
        Look for:
        1. The Collections sidebar/panel open on the right side of the browser window.
        2. Buttons saying "Start new collection" or a collection named "STEM Standards Review".
        3. Items being added to a list in the sidebar.
        
        Does the user appear to be using the Collections feature in ANY of these frames?
        Answer with JSON: {"using_collections": boolean, "confidence": "high/medium/low", "reason": "string"}
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("using_collections", False):
            vlm_score = 20
            score += 20
            feedback.append("VLM confirmed usage of Collections sidebar.")
        else:
            feedback.append("VLM could not confirm visual usage of Collections sidebar.")
            
    except Exception as e:
        print(f"VLM check failed: {e}")
        # Fallback: if programmatic check passed, give partial credit for VLM
        if collections.get("modified", False):
            score += 10
            feedback.append("VLM failed but programmatic check passed (partial credit).")

    # Final Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }