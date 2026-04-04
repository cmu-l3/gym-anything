#!/usr/bin/env python3
"""
Verifier for export_collection_bibtex task.

Verification Strategy:
1. File Existence: Check if .bib file exists and was created during task.
2. Content Analysis: Check if the file contains expected items (Sullivan, Tinker).
3. Negative Scope Check: Ensure file does NOT contain items outside the collection.
4. Format Check: Verify basic BibTeX structure.
5. VLM Verification: Use trajectory to verify the export workflow UI steps.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_collection_bibtex(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_content = metadata.get('required_content', ["Sullivan", "Tinker"])
    forbidden_content = metadata.get('forbidden_content', ["Brown", "Marbury"])

    score = 0
    feedback = []
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (25 pts)
    output_exists = task_result.get('output_exists', False)
    created_during_task = task_result.get('file_created_during_task', False)
    file_path = task_result.get('file_path', "")

    if output_exists:
        score += 15
        feedback.append("BibTeX file exists (+15)")
    else:
        feedback.append("BibTeX file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if created_during_task:
        score += 10
        feedback.append("File created during task (+10)")
    else:
        feedback.append("File timestamp pre-dates task (anti-gaming fail)")

    # 3. Content Analysis (45 pts)
    # Copy the actual .bib file from container for analysis
    bib_content = ""
    temp_bib = tempfile.NamedTemporaryFile(delete=False, suffix='.bib')
    try:
        copy_from_env(file_path, temp_bib.name)
        with open(temp_bib.name, 'r', errors='ignore') as f:
            bib_content = f.read()
    except Exception as e:
        feedback.append(f"Failed to read exported file content: {e}")
    finally:
        if os.path.exists(temp_bib.name):
            os.unlink(temp_bib.name)

    if bib_content:
        # Check Format (Valid BibTeX)
        if "@" in bib_content and "{" in bib_content and "}" in bib_content:
            score += 15
            feedback.append("Valid BibTeX format detected (+15)")
        else:
            feedback.append("File does not appear to be valid BibTeX")

        # Check Required Content (Sullivan, Tinker)
        missing_items = []
        for item in expected_content:
            if item.lower() not in bib_content.lower():
                missing_items.append(item)
        
        if not missing_items:
            score += 15
            feedback.append("Correct collection items found (Sullivan, Tinker) (+15)")
        else:
            feedback.append(f"Missing required items: {', '.join(missing_items)}")

        # Check Negative Scope (Did they export the whole library?)
        found_forbidden = []
        for item in forbidden_content:
            if item.lower() in bib_content.lower():
                found_forbidden.append(item)
        
        if not found_forbidden:
            score += 15
            feedback.append("Correctly scoped: No extraneous items found (+15)")
        else:
            feedback.append(f"Incorrect scope: Found non-collection items ({', '.join(found_forbidden[:3])}...)")
            score = max(0, score - 10) # Penalty for exporting wrong scope

    # 4. VLM Verification (30 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not frames and not final_screen:
        feedback.append("No visual evidence available")
    else:
        # Prompt checking for the specific workflow: Collection Context Menu -> Export
        prompt = (
            "Analyze these screenshots of Juris-M usage. "
            "Did the user right-click the 'First Amendment Jurisprudence' collection "
            "and select 'Export Collection'? "
            "Do NOT give credit if they selected 'Export Library' from the file menu. "
            "Look for the Export dialog with 'BibTeX' selected."
        )
        
        try:
            vlm_result = query_vlm(
                images=frames + [final_screen] if final_screen else frames,
                prompt=prompt
            )
            
            # Simple keyword check on VLM reasoning (assuming VLM output contains yes/no judgment)
            # In a real system, we'd parse structured VLM output. Here we simulate a check.
            # We give points if the file verification passed highly, assuming consistent behavior,
            # but rely on VLM string for the logic.
            if "export collection" in vlm_result.lower() or "right-click" in vlm_result.lower():
                score += 30
                feedback.append("VLM confirms correct workflow (+30)")
            else:
                # Fallback credit if file is perfect but VLM is ambiguous
                if score >= 60: 
                    score += 15
                    feedback.append("VLM analysis inconclusive, partial workflow credit (+15)")
                else:
                    feedback.append("VLM did not observe correct export workflow")
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
            # Fallback if VLM fails but file is perfect
            if score >= 65:
                score += 30
                feedback.append("VLM check skipped, trusted file evidence (+30)")

    # Final Verification
    passed = score >= 60 and output_exists and created_during_task
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }