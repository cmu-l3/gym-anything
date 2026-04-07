#!/usr/bin/env python3
"""
Verifier for bulk_csv_import_requirements task.

Criteria:
1. 8 work items imported (Titles match).
2. Types match (5 Stories, 3 Bugs).
3. Priority matches CSV.
4. Tags match CSV.
5. User Stories assigned to Sprint 2.
6. Bugs NOT assigned to Sprint 2.
"""

import json
import logging
import os
import tempfile
import Levenshtein  # python-Levenshtein usually available, else fallback to strict

logger = logging.getLogger(__name__)

def verify_bulk_csv_import_requirements(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('items', [])
    
    # 1. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_results\\bulk_csv_import_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    created_items = result.get('items_created_during_task', [])
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    score = 0
    feedback_parts = []
    
    # 2. Match Expected Items to Created Items
    # We try to find a match for each expected item in the created items list
    matches_found = 0
    types_correct = 0
    priorities_correct = 0
    tags_correct = 0
    iterations_correct = 0
    
    # Helper to clean strings
    def clean(s): return str(s).strip().lower() if s else ""
    
    used_indices = set()
    
    for expected in expected_items:
        exp_title = clean(expected['title'])
        best_match_idx = -1
        best_score = 0.85 # Threshold
        
        # Find item with matching title
        for idx, actual in enumerate(created_items):
            if idx in used_indices:
                continue
            
            act_title = clean(actual.get('title', ''))
            
            # Use Levenshtein ratio for slight title mismatches
            ratio = Levenshtein.ratio(exp_title, act_title)
            if ratio > best_score:
                best_score = ratio
                best_match_idx = idx
        
        if best_match_idx != -1:
            matches_found += 1
            used_indices.add(best_match_idx)
            matched_item = created_items[best_match_idx]
            
            # Check Type
            if clean(matched_item.get('type')) == clean(expected['type']):
                types_correct += 1
            else:
                feedback_parts.append(f"Wrong type for '{expected['title'][:20]}...': Expected {expected['type']}, got {matched_item.get('type')}")
                
            # Check Priority
            # Azure DevOps priority is integer
            if str(matched_item.get('priority')) == str(expected['priority']):
                priorities_correct += 1
            else:
                feedback_parts.append(f"Wrong priority for '{expected['title'][:20]}...': Expected {expected['priority']}, got {matched_item.get('priority')}")

            # Check Tags
            # Expected "tag1;tag2", Actual "tag1; tag2"
            exp_tags = set(t.strip() for t in expected['tags'].split(';'))
            act_tags_raw = matched_item.get('tags', '')
            if act_tags_raw:
                act_tags = set(t.strip() for t in act_tags_raw.split(';'))
            else:
                act_tags = set()
                
            if exp_tags.issubset(act_tags): # Allow extra tags, but required must be there
                tags_correct += 1
            else:
                feedback_parts.append(f"Missing tags for '{expected['title'][:20]}...': Expected {expected['tags']}, got {act_tags_raw}")
                
            # Check Iteration Path
            act_iteration = clean(matched_item.get('iteration', ''))
            is_story = clean(expected['type']) == "user story"
            
            if is_story:
                # Should be Sprint 2
                if "sprint 2" in act_iteration:
                    iterations_correct += 1
                else:
                    feedback_parts.append(f"Story '{expected['title'][:20]}...' not in Sprint 2 (was '{matched_item.get('iteration')}')")
            else:
                # Bugs should NOT be in Sprint 2
                if "sprint 2" not in act_iteration:
                    iterations_correct += 1
                else:
                    feedback_parts.append(f"Bug '{expected['title'][:20]}...' wrongly assigned to Sprint 2")
        else:
            feedback_parts.append(f"Missing item: {expected['title']}")
            
    # 3. Scoring Calculation
    # Max items: 8
    
    # Criterion 1: All items exist (25 pts)
    # 25 * (found / 8)
    score += 25 * (matches_found / 8)
    
    # Criterion 2: Types correct (15 pts)
    # 15 * (types_correct / 8)
    score += 15 * (types_correct / 8)
    
    # Criterion 3: Priorities correct (15 pts)
    # 15 * (priorities_correct / 8)
    score += 15 * (priorities_correct / 8)
    
    # Criterion 4: Tags preserved (10 pts)
    # 10 * (tags_correct / 8)
    score += 10 * (tags_correct / 8)
    
    # Criterion 5 & 6 combined in iterations_correct check
    # But let's split logic slightly for cleaner scoring mapping
    # 5 Stories to Sprint 2 (20 pts) -> 4 pts each
    # 3 Bugs !Sprint 2 (10 pts) -> 3.33 pts each
    
    # Re-eval iterations for scoring precision
    sprint_score = 0
    backlog_score = 0
    
    # We need to loop back or just use the iterations_correct count? 
    # iterations_correct currently mixes both. Let's rely on the ratio.
    # Total iteration checks = 8.
    # Weight is (20+10) = 30 pts.
    score += 30 * (iterations_correct / 8)
    
    # Criterion 7: Net Increase (5 pts)
    # Anti-gaming: Did we actually add ~8 items?
    net_increase = current_count - initial_count
    if 7 <= net_increase <= 9: # Tolerance +/- 1
        score += 5
    
    # Final Score
    score = min(100, round(score))
    passed = (score >= 60) and (matches_found >= 6)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Score: {score}/100. Found {matches_found}/8 items. " + " | ".join(feedback_parts[:5]) + ("..." if len(feedback_parts)>5 else "")
    }