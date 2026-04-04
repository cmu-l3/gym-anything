#!/usr/bin/env python3
"""
Verifier for Agile User Story Map task.

Checks:
1. File Artifacts: File existence, modification, PNG export.
2. Backbone (Activities): Presence of 5 activities, color-coded Blue, horizontal alignment.
3. Stories: Presence of backlog stories, color-coded Yellow, alignment under parent.
4. Release Slicing: MVP stories above V2 stories (vertical stratification).
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected Content
ACTIVITIES = ["Registration", "Donation Posting", "Inventory Browse", "Claim Process", "Impact Tracking"]

# Mapping Stories to Activities and Release Phase for verification
# Structure: {StoryText: (ActivityIndex, Phase)} where Phase 0=MVP, 1=V2
STORY_MAP = {
    "Sign up as Restaurant Donor": (0, 0),
    "Sign up as Shelter": (0, 0),
    "Single Sign-On": (0, 1),
    "Verify Non-Profit": (0, 1),
    
    "Create New Donation": (1, 0),
    "Upload Photo": (1, 0),
    "Set Expiration": (1, 0),
    "Bulk Upload": (1, 1),
    "Recurring": (1, 1),
    
    "View Available": (2, 0),
    "View Map": (2, 0),
    "Filter by Food": (2, 0),
    "Push Notifications": (2, 1),
    
    "Claim Donation": (3, 0),
    "Generate Pickup": (3, 0),
    "In-app Chat": (3, 1),
    "Schedule Pickup": (3, 1),
    
    "View History": (4, 0),
    "View Total Weight": (4, 1),
    "Tax Receipt": (4, 1)
}

def match_text(text, keywords):
    """Fuzzy match text against keywords."""
    if not text: return False
    text = text.lower()
    # Check if enough keywords match
    found = 0
    total = len(keywords.split())
    for word in keywords.lower().split():
        if word in text:
            found += 1
    return found >= max(1, total - 1) # Allow 1 missing word for long phrases

def verify_agile_user_story_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Artifacts (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 5
        feedback.append("Draw.io file saved.")
    if result.get("png_exists"):
        score += 5
        feedback.append("PNG exported.")
    
    # 2. Backbone Analysis (20 pts)
    # Check for Activities in Blue candidates
    backbone_shapes = result.get("backbone_candidates", [])
    found_activities = []
    
    for act in ACTIVITIES:
        for shape in backbone_shapes:
            if match_text(shape['text'], act):
                found_activities.append(shape)
                break
    
    if len(found_activities) == 5:
        score += 20
        feedback.append(f"All 5 Backbone Activities found and Blue.")
    elif len(found_activities) >= 3:
        score += 10
        feedback.append(f"Partial Backbone: {len(found_activities)}/5 activities found.")
    else:
        feedback.append(f"Backbone missing or not blue (found {len(found_activities)}).")

    # 3. Story Content & Coloring (20 pts)
    story_shapes = result.get("story_candidates", [])
    found_stories = {} # Map story key to shape
    
    for key in STORY_MAP.keys():
        for shape in story_shapes:
            if match_text(shape['text'], key):
                found_stories[key] = shape
                break
    
    found_count = len(found_stories)
    total_stories = len(STORY_MAP)
    
    if found_count >= total_stories - 2: # Allow 2 missing
        score += 20
        feedback.append(f"Stories found: {found_count}/{total_stories} (Yellow).")
    elif found_count >= total_stories / 2:
        score += 10
        feedback.append(f"Partial stories: {found_count}/{total_stories}.")
    else:
        feedback.append(f"Few stories found: {found_count}/{total_stories}.")

    # 4. Spatial Alignment (20 pts)
    # Verify stories are under the correct activity
    # We need to sort activities by X coordinate to establish columns
    alignment_score = 0
    
    if len(found_activities) >= 3:
        found_activities.sort(key=lambda s: s['geo']['x'] if s['geo'] else 0)
        
        # Determine column boundaries (midpoints between activities)
        # Simple heuristic: Story X should be closer to Parent Activity X than others
        aligned_count = 0
        checked_count = 0
        
        for key, shape in found_stories.items():
            if not shape['geo']: continue
            
            target_act_idx = STORY_MAP[key][0]
            # Find the actual shape for this activity index (if we found it)
            # Since found_activities might be missing some, we need to map names back
            target_act_name = ACTIVITIES[target_act_idx]
            parent_shape = next((s for s in found_activities if match_text(s['text'], target_act_name)), None)
            
            if parent_shape and parent_shape['geo']:
                checked_count += 1
                # Check horizontal overlap
                px = parent_shape['geo']['x']
                pw = parent_shape['geo']['width']
                sx = shape['geo']['x']
                sw = shape['geo']['width']
                
                # Center comparison
                pc = px + pw/2
                sc = sx + sw/2
                
                if abs(pc - sc) < 150: # Tolerance for alignment
                    aligned_count += 1
        
        if checked_count > 0:
            ratio = aligned_count / checked_count
            if ratio > 0.7:
                score += 20
                feedback.append(f"Spatial Alignment: Good ({aligned_count}/{checked_count}).")
            elif ratio > 0.4:
                score += 10
                feedback.append(f"Spatial Alignment: Fair ({aligned_count}/{checked_count}).")
            else:
                feedback.append("Spatial Alignment: Poor.")
    
    # 5. Release Slicing (30 pts)
    # MVP (Phase 0) should be ABOVE V2 (Phase 1)
    # Y coordinates increase downwards
    mvp_shapes = [found_stories[k] for k, v in STORY_MAP.items() if k in found_stories and v[1] == 0 and found_stories[k]['geo']]
    v2_shapes = [found_stories[k] for k, v in STORY_MAP.items() if k in found_stories and v[1] == 1 and found_stories[k]['geo']]
    
    if mvp_shapes and v2_shapes:
        avg_mvp_y = sum(s['geo']['y'] for s in mvp_shapes) / len(mvp_shapes)
        avg_v2_y = sum(s['geo']['y'] for s in v2_shapes) / len(v2_shapes)
        
        # Check if MVP is generally above V2 (smaller Y)
        # Also check separation
        if avg_mvp_y < avg_v2_y:
            # Check for a separator line in between
            separators = result.get('separators', [])
            has_separator = False
            for sep in separators:
                if not sep['geo']: continue
                sy = sep['geo']['y']
                if avg_mvp_y < sy < avg_v2_y:
                    has_separator = True
                    break
            
            if has_separator:
                score += 30
                feedback.append("Release Slicing: Excellent (MVP above Line above V2).")
            else:
                # If clear visual separation even without explicit line object (gap)
                if avg_v2_y - avg_mvp_y > 100:
                    score += 25
                    feedback.append("Release Slicing: Good (MVP clearly above V2).")
                else:
                    score += 15
                    feedback.append("Release Slicing: Weak (MVP above V2 but crowded).")
        else:
            feedback.append("Release Slicing: Fail (V2 mixed with or above MVP).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }