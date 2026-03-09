#!/usr/bin/env python3
"""
Verifier for create_chronological_collections task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_chronological_collections(traj, env_info, task_info):
    """
    Verify that 3 specific collections exist and papers are sorted correctly by year.
    """
    # 1. Setup and load result
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

    # 2. Extract metadata (Expected Truth)
    metadata = task_info.get('metadata', {})
    expected_colls = metadata.get('collections', {})
    expected_papers = metadata.get('papers', {})
    
    target_names = {
        "pre": expected_colls.get("pre_1950", "Pre-1950 Foundations"),
        "mid": expected_colls.get("classical", "1950-1999 Classical"),
        "mod": expected_colls.get("modern", "2000s and Beyond")
    }

    # Normalize paper lists for matching (lowercase, strip)
    def normalize(titles):
        return set(t.lower().strip() for t in titles)

    truth_sets = {
        "pre": normalize(expected_papers.get("pre_1950", [])),
        "mid": normalize(expected_papers.get("classical", [])),
        "mod": normalize(expected_papers.get("modern", []))
    }

    # 3. Analyze Agent Output
    agent_collections = result.get("collections", [])
    
    # Map agent collection names to their item lists (normalized)
    agent_data = {}
    for col in agent_collections:
        name = col.get("name", "").strip()
        items = normalize(col.get("items", []))
        agent_data[name] = items

    score = 0
    feedback = []

    # Helper to score a specific era
    def score_era(era_key, points_exist, points_per_item):
        era_name = target_names[era_key]
        expected_items = truth_sets[era_key]
        era_score = 0
        era_feedback = []

        if era_name in agent_data:
            era_score += points_exist
            era_feedback.append(f"Collection '{era_name}' created.")
            
            # Check items
            found_items = agent_data[era_name]
            # Intersection of found and expected
            correct_placements = len(found_items.intersection(expected_items))
            # Calculate item score
            item_score = correct_placements * points_per_item
            era_score += item_score
            
            # Check for incorrect items (papers from other eras)
            # We don't deduct heavily, but worth noting
            all_other_items = set()
            for k, v in truth_sets.items():
                if k != era_key:
                    all_other_items.update(v)
            
            wrong_items = len(found_items.intersection(all_other_items))
            if wrong_items > 0:
                era_feedback.append(f"{correct_placements}/{len(expected_items)} correct items, but {wrong_items} wrong items included.")
            else:
                era_feedback.append(f"{correct_placements}/{len(expected_items)} items placed correctly.")
        else:
            era_feedback.append(f"Missing collection '{era_name}'.")

        return era_score, era_feedback

    # Scoring Logic
    # Total points: 100
    # Existence: 4 + 3 + 3 = 10 pts
    # Items: 
    #   Pre-1950 (5 items): 5 * 5pts = 25 pts
    #   1950-1999 (5 items): 5 * 5pts = 25 pts
    #   2000+ (8 items): 8 * 5pts = 40 pts
    # Total = 100

    s_pre, f_pre = score_era("pre", 4, 5)
    s_mid, f_mid = score_era("mid", 3, 5)
    s_mod, f_mod = score_era("mod", 3, 5)

    score = s_pre + s_mid + s_mod
    feedback.extend(f_pre)
    feedback.extend(f_mid)
    feedback.extend(f_mod)

    # Threshold Check
    # Need all collections (10pts) + at least ~half items correct (45pts) => 55-60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }