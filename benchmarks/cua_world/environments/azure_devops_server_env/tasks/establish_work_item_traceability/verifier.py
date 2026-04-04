#!/usr/bin/env python3
"""
Verifier for establish_work_item_traceability task.
Verifies the creation of a Feature, parent-child links to Stories, related links to Bugs,
and breakdown of a Story into Tasks.
"""

import json
import logging
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traceability(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_file.close()
    try:
        # Try both path styles
        try:
            copy_from_env("C:/Users/Docker/task_results/establish_work_item_traceability_result.json", temp_file.name)
        except:
            copy_from_env("C:\\Users\\Docker\\task_results\\establish_work_item_traceability_result.json", temp_file.name)
            
        with open(temp_file.name, "r", encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criteria 1: Feature Creation (15 pts)
    if result.get("feature_exists"):
        score += 15
        feedback.append("Feature 'Product Inventory Management' created.")
    else:
        feedback.append("Failed to create Feature work item.")

    # Criteria 2: Feature -> Story Links (Child) (20 pts)
    # Expect 2 specific stories
    child_links = result.get("feature_child_links", [])
    child_titles = [item.get("title") for item in child_links]
    
    expected_stories = [
        "Implement product inventory search",
        "Design REST API rate limiting"
    ]
    
    linked_stories_count = 0
    for story in expected_stories:
        if story in child_titles:
            linked_stories_count += 1
            
    if linked_stories_count == 2:
        score += 20
        feedback.append("Both User Stories linked as Children of Feature.")
    elif linked_stories_count == 1:
        score += 10
        feedback.append("Only 1/2 User Stories linked to Feature.")
    else:
        feedback.append("No User Stories linked correctly to Feature.")

    # Criteria 3: Story -> Bug Links (Related) (25 pts)
    # 3 specific related links expected
    related_links = result.get("story_related_links", [])
    
    # Map: Source Story -> List of expected Linked Bug Titles
    expected_related = {
        "Implement product inventory search": [
            "Product price calculation bug",
            "Inventory count goes negative"
        ],
        "Design REST API rate limiting": [
            "API 500 error on special chars"
        ]
    }
    
    found_links = 0
    for link in related_links:
        source = link.get("source_story")
        target = link.get("target_title")
        if source in expected_related and target in expected_related[source]:
            found_links += 1
            
    # Max 3 links to find. 25 pts total. ~8 pts each.
    link_score = min(25, int(found_links * 8.34))
    score += link_score
    feedback.append(f"Linked {found_links}/3 Bugs correctly.")

    # Criteria 4: Task Creation (20 pts)
    # Expect 2 tasks under "Implement product inventory search"
    tasks = result.get("tasks_created", [])
    
    task_map = {
        "set up elasticsearch index for products": 8,
        "build search api endpoint": 12
    }
    
    tasks_found = 0
    work_correct = 0
    
    for task in tasks:
        title_lower = task.get("title", "").lower()
        if title_lower in task_map:
            tasks_found += 1
            # Check remaining work (allow small variance or exact)
            expected_work = task_map[title_lower]
            actual_work = task.get("remaining_work", 0)
            if abs(actual_work - expected_work) < 0.1:
                work_correct += 1
                
    if tasks_found >= 2:
        score += 10
        feedback.append("Both Tasks created.")
    elif tasks_found == 1:
        score += 5
        feedback.append("1/2 Tasks created.")
        
    if work_correct >= 2:
        score += 10
        feedback.append("Remaining Work set correctly for both tasks.")
    elif work_correct == 1:
        score += 5
        feedback.append("Remaining Work set correctly for 1 task.")

    # Criteria 5: VLM Verification of UI Interaction (20 pts)
    # Check if agent actually used the Board/Backlog UI
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Did the user interact with the Azure DevOps Boards or Work Items UI?
    Look for:
    1. Dragging and dropping work items (to link/parent them).
    2. Opening the "Add link" dialog.
    3. Filling out "New Work Item" forms.
    4. Viewing the "Relations" or "Links" tab.
    
    Answer 'yes' if any of these are visible.
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if "yes" in vlm_res.get("response", "").lower():
            score += 20
            feedback.append("VLM confirmed UI interaction.")
        else:
            feedback.append("VLM did not observe clear UI interaction for linking.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if hard score is high, assume interaction happened
        if score >= 60:
            score += 20

    # Final Pass Check
    passed = score >= 60 and result.get("feature_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }