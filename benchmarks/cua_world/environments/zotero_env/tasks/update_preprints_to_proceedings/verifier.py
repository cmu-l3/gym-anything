#!/usr/bin/env python3
import json
import tempfile
import os
import difflib

def verify_update_preprints(traj, env_info, task_info):
    """
    Verify that the 3 papers were updated to Conference Paper type
    and have correct proceedings titles.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata expectations
    expected_papers = task_info.get('metadata', {}).get('papers', [])
    
    # Check each paper
    result_papers = {p['title']: p for p in result.get('papers', [])}
    
    # Constants
    CONFERENCE_PAPER_TYPE_ID = 10
    
    total_papers = len(expected_papers)
    points_per_paper_type = 10
    points_per_paper_venue = 20
    # Total possible = 3 * (10 + 20) = 90. + 10 padding/base = 100?
    # Let's align with description scoring:
    # Type: 10 pts * 3 = 30
    # Venue: 20 pts * 3 = 60
    # No Data Loss (checked implicitly by finding title): 10 pts
    # Total: 100
    
    data_loss_penalty = False
    
    for expected in expected_papers:
        title = expected['title']
        target_venue = expected['expected_venue']
        
        actual = result_papers.get(title)
        
        if not actual or not actual['found']:
            feedback.append(f"❌ '{title}' not found in library.")
            data_loss_penalty = True
            continue
            
        # 1. Check Type
        if actual['itemTypeID'] == CONFERENCE_PAPER_TYPE_ID:
            score += 10
            feedback.append(f"✅ '{title}' type updated to Conference Paper.")
        else:
            feedback.append(f"❌ '{title}' type is {actual['itemTypeID']} (expected 10).")
            
        # 2. Check Venue (fuzzy match)
        # Check both fields as Zotero might use either depending on how user entered it
        venue_val = actual.get('proceedingsTitle') or actual.get('publicationTitle') or ""
        
        # Normalize for comparison
        def normalize(s): return s.lower().replace(':', '').replace('-', ' ').split()
        
        # Simple fuzzy check: Key words present
        # We use SequenceMatcher ratio for robustness
        ratio = difflib.SequenceMatcher(None, target_venue.lower(), venue_val.lower()).ratio()
        
        if ratio > 0.8 or target_venue.lower() in venue_val.lower():
            score += 20
            feedback.append(f"✅ '{title}' venue correct.")
        else:
            feedback.append(f"❌ '{title}' venue mismatch. Got: '{venue_val}', Expected: '{target_venue}'")

    # Anti-gaming: Check modification times?
    # The export script captures dateModified_ts. 
    # If the user just modified it, it should be > task_start.
    task_start = result.get('task_start', 0)
    modified_count = sum(1 for p in result.get('papers', []) if p.get('dateModified_ts', 0) > task_start)
    
    if modified_count < 3:
        feedback.append(f"⚠️ Warning: Only {modified_count}/3 papers show modification timestamps after task start.")
        # We don't deduct points strictly here because DB timestamps can sometimes be tricky with wal mode,
        # but it's a good flag. Ideally we enforce it.
    
    if not data_loss_penalty:
        score += 10
        feedback.append("✅ No papers lost.")
    else:
        feedback.append("❌ Penalty: Some papers were deleted or titles changed.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }