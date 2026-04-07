#!/usr/bin/env python3
"""
Verifier for Create Bibliography System task.

Uses `copy_from_env` to load the exported JSON result.
Verifies the presence and correctness of 5 reference tiddlers (custom fields + tags)
and 1 Bibliography tiddler (list widget + filters).
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bibliography_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/bibliography_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    tiddlers = result.get("tiddlers", {})
    metrics = result.get("metrics", {})
    
    # ---------------------------------------------------------
    # Anti-Gaming Checks
    # ---------------------------------------------------------
    initial_count = metrics.get("initial_count", 0)
    current_count = metrics.get("current_count", 0)
    gui_saves = metrics.get("gui_saves", 0)
    
    if current_count <= initial_count:
        return {"passed": False, "score": 0, "feedback": "No new tiddlers were created."}
    
    if gui_saves < 3:
        feedback_parts.append(f"Warning: Low GUI saves detected ({gui_saves}).")

    # Load Expected Metadata
    metadata = task_info.get("metadata", {})
    expected_refs = metadata.get("expected_references", [])
    
    refs_created = 0
    total_fields_correct = 0

    # ---------------------------------------------------------
    # Criterion 1 & 2 & 3: References exist, have fields, have tags
    # Total possible for refs: 5 * (4 [exists] + 8 [fields] + 2 [tags]) = 70 points
    # ---------------------------------------------------------
    for expected in expected_refs:
        title = expected["title"]
        expected_fields = {
            "author": expected["author"],
            "year": expected["year"],
            "journal": expected["journal"],
            "doi": expected["doi"]
        }
        expected_tag = expected["tag"]
        
        # Check if tiddler exists (case insensitive match on title keys just in case)
        actual_tid = None
        for k, v in tiddlers.items():
            if k.strip().lower() == title.strip().lower():
                actual_tid = v
                break
                
        if actual_tid:
            refs_created += 1
            score += 4 # Exists
            
            # Verify fields (2 pts per field, max 8)
            fields_ok = 0
            for field, exp_val in expected_fields.items():
                actual_val = actual_tid.get(field, "").strip()
                # Use loose substring matching or exact matching depending on field
                if exp_val.lower() in actual_val.lower():
                    fields_ok += 1
                    total_fields_correct += 1
                elif actual_val:
                    # Partial credit if they created the field but typo'd the content heavily
                    fields_ok += 0.5
            
            score += int(fields_ok * 2)
            
            # Verify tags (2 pts)
            tags_str = actual_tid.get("tags", "")
            has_ref = "Reference" in tags_str or "reference" in tags_str.lower()
            has_spec = expected_tag.lower() in tags_str.lower()
            if has_ref and has_spec:
                score += 2
            elif has_ref or has_spec:
                score += 1

    feedback_parts.append(f"References created: {refs_created}/5")
    feedback_parts.append(f"Correct custom fields: {total_fields_correct}/20")

    # ---------------------------------------------------------
    # Criterion 4: Bibliography Tiddler (Exists = 10, Filter = 10, List Widget = 10)
    # Total possible: 30 points
    # ---------------------------------------------------------
    bib_tid = None
    for k, v in tiddlers.items():
        if k.strip().lower() == "bibliography":
            bib_tid = v
            break
            
    if bib_tid:
        score += 10 # Exists
        feedback_parts.append("Bibliography tiddler found")
        
        text = bib_tid.get("text", "")
        
        # Check for reference tag filter (10 pts)
        if "tag[Reference]" in text or "tag[reference]" in text.lower() or "tag[Reference]sort[year]" in text.replace(" ", ""):
            score += 10
            feedback_parts.append("Bibliography has correct Reference tag filter")
        else:
            feedback_parts.append("Bibliography missing tag[Reference] filter")
            
        # Check for list widget (10 pts)
        if "<$list" in text or "<<list-links" in text or "<<list" in text:
            score += 10
            feedback_parts.append("Bibliography uses a list widget")
        else:
            feedback_parts.append("Bibliography missing <$list> widget")
    else:
        feedback_parts.append("Bibliography tiddler NOT found")

    # ---------------------------------------------------------
    # VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_query_func = env_info.get('query_vlm')
    if vlm_query_func:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=3)
            if frames:
                vlm_prompt = """You are assessing if a user successfully interacted with TiddlyWiki.
                Look at these screenshots spanning the task.
                Did the user open the tiddler editor and interact with the 'Add a new field' interface?
                Answer 'yes' if you see the tiddler edit screen with custom fields being added.
                Respond in JSON: {"used_field_editor": true/false}"""
                
                vlm_resp = vlm_query_func(prompt=vlm_prompt, images=frames)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("used_field_editor"):
                        feedback_parts.append("VLM verified field editor usage")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine Pass/Fail (Must get at least 60 points, which means at least 3 refs + some biblio)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }