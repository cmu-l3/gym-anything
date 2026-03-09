#!/usr/bin/env python3
import json
import tempfile
import os

def verify_curate_conference_reading_list(traj, env_info, task_info):
    """
    Verify the curate_conference_reading_list task.
    
    Scoring Breakdown (100 pts total):
    1. Collection "NeurIPS Preparation" exists: 15 pts
    2. Correct papers in collection (4 papers): 32 pts (8 pts each)
    3. Precision (no incorrect papers): 8 pts
    4. Tags "neurips-reading" on correct papers: 20 pts (5 pts each)
    5. Standalone note exists in collection: 10 pts
    6. Note length >= 150 chars: 5 pts
    7. Note references >= 2 papers: 10 pts
    
    Pass Threshold: 60 pts
    """
    
    # 1. Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Collection Exists (15 pts)
    if result.get('collection_exists'):
        score += 15
        feedback.append("✓ Collection 'NeurIPS Preparation' created")
    else:
        return {"passed": False, "score": 0, "feedback": "✗ Collection 'NeurIPS Preparation' not found. (0/100)"}

    # Check 2: Correct Items (32 pts)
    correct_found = len(result.get('correct_items_found', []))
    score += (correct_found * 8)
    if correct_found == 4:
        feedback.append("✓ All 4 NeurIPS papers found")
    else:
        feedback.append(f"⚠ Found {correct_found}/4 NeurIPS papers")

    # Check 3: Precision (8 pts)
    incorrect_count = len(result.get('incorrect_items_found', []))
    if incorrect_count == 0:
        score += 8
        feedback.append("✓ No incorrect papers added")
    else:
        feedback.append(f"✗ {incorrect_count} non-NeurIPS papers found in collection (-8 pts)")

    # Check 4: Tags (20 pts)
    # We only care if the *correct* items are tagged
    correct_tags_count = 0
    # result['tags_correct'] is a dict {itemID: bool} for all items in collection
    # We need to count how many True values correspond to correct items
    # Since we don't have itemIDs mapped to titles in the top level of this script easily,
    # we rely on the fact that the export script populates 'tags_correct' for ALL items in collection.
    # We should iterate through 'items_in_collection' to correlate.
    
    items = result.get('items_in_collection', [])
    target_titles = [
        "Attention Is All You Need",
        "Language Models are Few-Shot Learners",
        "ImageNet Classification",
        "Generative Adversarial Nets"
    ]
    
    for item in items:
        title = item.get('title', '')
        # Check if this is a target paper
        if any(t.lower() in title.lower() for t in target_titles):
            if "neurips-reading" in item.get('tags', []):
                correct_tags_count += 1

    score += (correct_tags_count * 5)
    if correct_tags_count == 4:
        feedback.append("✓ All 4 papers tagged correctly")
    else:
        feedback.append(f"⚠ {correct_tags_count}/4 papers tagged 'neurips-reading'")

    # Check 5: Note Exists (10 pts)
    if result.get('standalone_note_exists'):
        score += 10
        feedback.append("✓ Standalone note created")
    else:
        feedback.append("✗ No standalone note found in collection")

    # Check 6: Note Length (5 pts)
    if result.get('note_content_valid'):
        score += 5
        feedback.append("✓ Note length sufficient")
    else:
        l = result.get('note_length', 0)
        if result.get('standalone_note_exists'):
            feedback.append(f"⚠ Note too short ({l} chars)")

    # Check 7: Note References (10 pts)
    refs = result.get('referenced_papers', [])
    if len(refs) >= 2:
        score += 10
        feedback.append(f"✓ Note references {len(refs)} papers")
    else:
        if result.get('standalone_note_exists'):
            feedback.append(f"✗ Note references only {len(refs)}/2 required papers")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }