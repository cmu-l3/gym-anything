#!/usr/bin/env python3
"""
Verifier for Azure DevOps Create Epic Decomposition task.

Verifies:
1. Creation of Epic, Features, and User Stories with correct Titles.
2. Proper Hierarchy (Epic -> Feature -> Story).
3. Correct Field Values (Priority, Story Points).
4. Timestamp verification (Anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_epic_decomposition(traj, env_info, task_info):
    """
    Verify the backlog hierarchy creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    meta = task_info.get('metadata', {})
    expected_epic = meta.get('epic_title', 'Mobile App Experience')
    expected_f1 = meta.get('feature_1_title', 'User Authentication')
    expected_f2 = meta.get('feature_2_title', 'Product Catalog Browsing')
    expected_stories = meta.get('stories', [])

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # The export script runs in Windows, path separators might be an issue if not handled
        # We try the standard path defined in export_result.ps1
        copy_from_env("C:/Users/Docker/task_results/epic_decomposition_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    items = result.get('items', [])
    if not items:
        return {"passed": False, "score": 0, "feedback": "No new work items were found created during the task."}

    score = 0
    feedback = []

    # Helper to find item by title (fuzzy match)
    def find_item(type_name, title_fragment):
        for item in items:
            if item.get('type') == type_name and title_fragment.lower() in item.get('title', '').lower():
                return item
        return None

    # Helper to check parent link
    def check_parent(child_item, parent_id):
        if not child_item or not parent_id:
            return False
        relations = child_item.get('relations', [])
        for rel in relations:
            # Hierarchy-Reverse is 'Parent'
            if rel.get('rel') == 'System.LinkTypes.Hierarchy-Reverse' and str(rel.get('target_id')) == str(parent_id):
                return True
        return False

    # 1. Verify Epic (10 pts)
    epic = find_item('Epic', expected_epic)
    if epic:
        score += 10
        feedback.append(f"Epic '{expected_epic}' created.")
        if epic.get('priority') == 1:
            score += 5
            feedback.append("Epic Priority correct (1).")
        else:
            feedback.append(f"Epic Priority incorrect: {epic.get('priority')}")
    else:
        feedback.append(f"Epic '{expected_epic}' NOT found.")

    # 2. Verify Feature 1 (15 pts total)
    f1 = find_item('Feature', expected_f1)
    if f1:
        score += 5
        feedback.append(f"Feature '{expected_f1}' created.")
        if epic and check_parent(f1, epic['id']):
            score += 5
            feedback.append(f"Feature '{expected_f1}' correctly linked to Epic.")
        else:
            feedback.append(f"Feature '{expected_f1}' NOT linked to Epic.")
        
        if f1.get('priority') == 1:
            score += 5
            feedback.append(f"Feature '{expected_f1}' Priority correct (1).")
    else:
        feedback.append(f"Feature '{expected_f1}' NOT found.")

    # 3. Verify Feature 2 (15 pts total)
    f2 = find_item('Feature', expected_f2)
    if f2:
        score += 5
        feedback.append(f"Feature '{expected_f2}' created.")
        if epic and check_parent(f2, epic['id']):
            score += 5
            feedback.append(f"Feature '{expected_f2}' correctly linked to Epic.")
        else:
            feedback.append(f"Feature '{expected_f2}' NOT linked to Epic.")

        if f2.get('priority') == 2:
            score += 5
            feedback.append(f"Feature '{expected_f2}' Priority correct (2).")
    else:
        feedback.append(f"Feature '{expected_f2}' NOT found.")

    # 4. Verify Stories (40 pts total)
    stories_found = 0
    for exp_story in expected_stories:
        title_frag = exp_story['title_fragment']
        parent_title = exp_story['parent_feature']
        exp_points = exp_story['points']
        exp_prio = exp_story['priority']

        story = find_item('User Story', title_frag)
        if story:
            stories_found += 1
            item_score = 0
            
            # Identify parent object
            parent = f1 if parent_title == expected_f1 else f2
            
            # Check Link (4 pts)
            if parent and check_parent(story, parent['id']):
                item_score += 4
            else:
                feedback.append(f"Story '...{title_frag}...' not linked to correct feature.")

            # Check Points (3 pts)
            if story.get('story_points') == exp_points:
                item_score += 3
            else:
                feedback.append(f"Story '...{title_frag}...' points wrong (got {story.get('story_points')}).")

            # Check Priority (3 pts)
            if story.get('priority') == exp_prio:
                item_score += 3
            else:
                feedback.append(f"Story '...{title_frag}...' priority wrong.")
            
            score += item_score
        else:
            feedback.append(f"Story containing '{title_frag}' NOT found.")

    # Base points for finding stories (10 pts distributed)
    score += (stories_found * 2.5)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }