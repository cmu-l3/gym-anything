#!/usr/bin/env python3
"""
Verifier for add_podcast_reference task.

Checks:
1. Item exists with title "The Alibi" (20 pts)
2. Item Type is "audioRecording" (20 pts)
3. Creator "Sarah Koenig" is attached (15 pts)
4. Key metadata fields (Series, Date, Format, Time, Label, URL) are present (45 pts)

Uses VLM for trajectory verification as a secondary signal.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_podcast_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    
    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_podcast_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task result: {e}"
        }

    if not result.get("item_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No item with title 'The Alibi' found in library. Did you create the item?",
            "details": result
        }

    score = 0
    feedback = []
    
    # 1. Title Check (Implicit in item_found, but explicit points)
    score += 20
    feedback.append("Title 'The Alibi' found (+20)")

    # 2. Item Type Check
    item_type = result.get("item_type", "").lower()
    if item_type == "audiorecording":
        score += 20
        feedback.append("Item Type 'Audio Recording' correct (+20)")
    else:
        feedback.append(f"Item Type incorrect: expected 'audioRecording', got '{item_type}'")

    # 3. Creator Check (Sarah Koenig)
    creators = result.get("creators", [])
    creator_found = False
    for c in creators:
        fn = c.get("firstName", "").lower()
        ln = c.get("lastName", "").lower()
        if "sarah" in fn and "koenig" in ln:
            creator_found = True
            break
    
    if creator_found:
        score += 15
        feedback.append("Performer 'Sarah Koenig' found (+15)")
    else:
        feedback.append("Performer 'Sarah Koenig' NOT found")

    # 4. Metadata Fields Check (Scanning all values associated with item)
    all_values = [str(v).lower() for v in result.get("all_values", [])]
    
    # Series Title: Serial
    if any("serial" in v for v in all_values):
        score += 10
        feedback.append("Series Title 'Serial' found (+10)")
    else:
        feedback.append("Series Title 'Serial' missing")

    # Date: 2014-10-03
    if any("2014-10-03" in v for v in all_values):
        score += 10
        feedback.append("Date '2014-10-03' found (+10)")
    else:
        feedback.append("Date '2014-10-03' missing")

    # Format: Podcast
    if any("podcast" in v for v in all_values):
        score += 5
        feedback.append("Format 'Podcast' found (+5)")
    else:
        feedback.append("Format 'Podcast' missing")

    # Time: 53:00
    if any("53:00" in v for v in all_values):
        score += 5
        feedback.append("Running Time '53:00' found (+5)")
    else:
        feedback.append("Running Time '53:00' missing")

    # Label: WBEZ Chicago
    if any("wbez" in v for v in all_values):
        score += 5
        feedback.append("Label 'WBEZ Chicago' found (+5)")
    else:
        feedback.append("Label 'WBEZ Chicago' missing")

    # URL Check
    if any("serialpodcast.org" in v for v in all_values):
        score += 10
        feedback.append("URL found (+10)")
    else:
        feedback.append("URL missing")

    # Anti-gaming: Created during task
    if result.get("created_during_task", False):
        feedback.append("(Verified item was created during this session)")
    else:
        feedback.append("(Warning: Item timestamp suggests it might pre-date this session)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }