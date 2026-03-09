#!/usr/bin/env python3
"""
Verifier for add_items_by_identifier task.

Scoring breakdown (100 pts total):
- 25 pts per paper (x3 papers = 75 pts):
    - 15 pts: Correct title keywords match
    - 5 pts: Correct DOI field match
    - 5 pts: Correct Author match
- 10 pts: Correct item count delta (exactly 3 items added)
- 10 pts: Items added strictly AFTER task start time (anti-gaming)
- 5 pts: Items are valid bibliographic types (not notes/attachments)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_items_by_identifier(traj, env_info, task_info):
    # 1. Load result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Get Targets
    targets = task_info.get('metadata', {}).get('targets', [])
    new_items = result.get('new_items', [])
    
    score = 0
    feedback_parts = []
    
    # 3. Evaluate each target paper
    matched_item_ids = set()
    
    for target in targets:
        target_found = False
        paper_score = 0
        details = []
        
        # Look for this target in new_items
        for item in new_items:
            if item['itemID'] in matched_item_ids:
                continue
                
            # Check Title Match (Case-insensitive keyword search)
            title = item.get('title', '').lower()
            keywords = [k.lower() for k in target['title_keywords']]
            title_match = all(k in title for k in keywords)
            
            # Check DOI Match (Clean string comparison)
            doi_val = item.get('doi', '').lower().strip()
            target_doi = target['doi'].lower().strip()
            doi_match = (doi_val == target_doi)
            
            if title_match or doi_match:
                matched_item_ids.add(item['itemID'])
                target_found = True
                
                # Scoring
                if title_match:
                    paper_score += 15
                    details.append("Title ✓")
                else:
                    details.append("Title ✗")
                    
                if doi_match:
                    paper_score += 5
                    details.append("DOI ✓")
                else:
                    # Partial credit if DOI is missing but title matches (lookup might have varied)
                    details.append(f"DOI ✗ (found: {doi_val})")
                
                # Check Author
                item_author = item.get('author', '').lower()
                target_authors = [a.lower() for a in target['authors']]
                if any(a in item_author for a in target_authors):
                    paper_score += 5
                    details.append("Author ✓")
                else:
                    details.append("Author ✗")
                
                break # Stop checking items for this target
        
        score += paper_score
        if target_found:
            feedback_parts.append(f"Paper '{target['key']}' found ({paper_score}/25 pts): {', '.join(details)}")
        else:
            feedback_parts.append(f"Paper '{target['key']}' NOT found")

    # 4. Anti-gaming / Structural Checks
    
    # Count Delta
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    delta = final_count - initial_count
    
    if delta == 3:
        score += 10
        feedback_parts.append("Item count delta correct (+3)")
    elif delta > 0:
        score += 5
        feedback_parts.append(f"Item count delta partial (+{delta}, expected +3)")
    else:
        feedback_parts.append(f"Item count delta wrong (+{delta})")

    # Timestamp Check (Verified in export script, but confirming here)
    # If the item exists in 'new_items', it passed the timestamp check in export_result.sh
    # We award points if we found ANY valid items
    if len(new_items) > 0:
        score += 10
        feedback_parts.append("Timestamp check passed")
    
    # Valid types check (not notes)
    # The export SQL filtered out notes (itemTypeID IN (1,14,28)), so anything in new_items is valid
    if len(new_items) > 0:
        score += 5
        feedback_parts.append("Item types valid")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }