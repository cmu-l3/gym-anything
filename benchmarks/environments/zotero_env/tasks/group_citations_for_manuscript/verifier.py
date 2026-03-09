#!/usr/bin/env python3
"""
Verifier for group_citations_for_manuscript task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_group_citations(traj, env_info, task_info):
    """
    Verify the collection creation, item selection, and tagging.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Collection (20 pts)
    if result.get("collection_found") and result.get("collection_name") == "Manuscript 2024":
        score += 20
        feedback.append("Collection 'Manuscript 2024' created.")
    elif result.get("collection_found"):
        score += 10 # Partial for wrong case/name
        feedback.append(f"Collection found but name '{result.get('collection_name')}' mismatch.")
    else:
        feedback.append("Collection 'Manuscript 2024' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Items (80 pts distributed)
    items = result.get("items", [])
    
    # Targets configuration
    targets = [
        {"key": "turing", "title_frag": "on computable numbers", "year": "1936", "tag_score": 10, "item_score": 10},
        {"key": "shannon", "title_frag": "a mathematical theory", "year": "1948", "tag_score": 10, "item_score": 10},
        {"key": "vaswani", "title_frag": "attention is all you need", "year": "2017", "tag_score": 10, "item_score": 10},
        {"key": "silver", "title_frag": "mastering the game of go", "year": "2016", "tag_score": 10, "item_score": 10}
    ]

    found_targets = {t["key"]: False for t in targets}
    
    for item in items:
        title = item.get("title", "").lower()
        date = item.get("date", "")
        tags = [t.lower() for t in item.get("tags", [])]
        
        for t in targets:
            # Check title match
            if t["title_frag"] in title:
                # Check year disambiguation
                if t["year"] in date:
                    found_targets[t["key"]] = True
                    score += t["item_score"]
                    feedback.append(f"Found correct {t['key'].title()} paper.")
                    
                    # Check tag
                    if "cited" in tags:
                        score += t["tag_score"]
                        feedback.append(f"  - Tagged 'cited'.")
                    else:
                        feedback.append(f"  - Missing 'cited' tag.")
                else:
                    feedback.append(f"Found WRONG {t['key'].title()} paper (Year {date}, expected {t['year']}).")

    # Check for missing items
    for t in targets:
        if not found_targets[t["key"]]:
            feedback.append(f"Missing {t['key'].title()} paper.")

    # Deduct for extra items (noise)? 
    # Optional, but task says "populate it with 4 specific papers". 
    # Let's be lenient on extras unless it's excessive, but stricly speaking 
    # "populate with these 4" implies "only these 4" or "at least these 4".
    # We won't penalize extras heavily, but we can note it.
    if len(items) > 4:
        feedback.append(f"Note: Collection contains {len(items)} items (expected 4).")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }