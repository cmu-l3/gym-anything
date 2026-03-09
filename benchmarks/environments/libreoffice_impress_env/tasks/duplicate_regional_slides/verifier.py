#!/usr/bin/env python3
"""
Verifier for duplicate_regional_slides task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_duplicate_regional_slides(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Basic file checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "File quarter_review.odp not found"}
    
    if not result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not modified (timestamp unchanged)"}

    # Analysis checks
    analysis = result.get('analysis', {})
    if not analysis.get('success'):
        return {"passed": False, "score": 0, "feedback": f"Could not analyze ODP file: {analysis.get('error')}"}

    slides = analysis.get('slides', [])
    slide_count = analysis.get('slide_count', 0)

    score = 0
    feedback_parts = []
    
    # 1. Slide Count (20 pts)
    # Strict requirement: Exactly 9 slides
    if slide_count == 9:
        score += 20
        feedback_parts.append("✅ Correct slide count (9)")
    else:
        feedback_parts.append(f"❌ Incorrect slide count: {slide_count} (expected 9)")

    # Define groups
    # Group 1: Slides 0-2 (North America)
    # Group 2: Slides 3-5 (Europe)
    # Group 3: Slides 6-8 (Asia-Pacific)
    groups = [
        {"name": "North America", "indices": [0, 1, 2], "points": 15},
        {"name": "Europe", "indices": [3, 4, 5], "points": 15},
        {"name": "Asia-Pacific", "indices": [6, 7, 8], "points": 15}
    ]
    
    # Content keywords to verify preservation (from task description)
    # We look for these in the text of each group to ensure content wasn't deleted
    content_keywords = ["4.2M", "Enterprise", "retention"]

    total_regions_passed = 0
    total_content_passed = 0

    # Verify each group
    for group in groups:
        indices = group['indices']
        region_name = group['name']
        
        # Skip if we don't have enough slides
        if max(indices) >= slide_count:
            feedback_parts.append(f"❌ Missing slides for {region_name}")
            continue

        # Check Titles (Prefix)
        titles_correct = 0
        group_text_blob = ""
        
        for idx in indices:
            slide_texts = slides[idx].get('text', [])
            combined_text = " ".join(slide_texts)
            group_text_blob += combined_text + " "
            
            # Check if region name is in the text (flexible matching: case insensitive)
            if region_name.lower() in combined_text.lower():
                titles_correct += 1
        
        # Score for titles
        if titles_correct == 3:
            score += group['points']
            total_regions_passed += 1
            feedback_parts.append(f"✅ {region_name} titles correct")
        elif titles_correct > 0:
            partial = int(group['points'] / 3 * titles_correct)
            score += partial
            feedback_parts.append(f"⚠️ {region_name} partial titles ({titles_correct}/3)")
        else:
            feedback_parts.append(f"❌ {region_name} titles missing")

        # Check Content Preservation (10 pts per group)
        # We check if at least 2 of the 3 keywords are present in this group's text
        keywords_found = sum(1 for k in content_keywords if k.lower() in group_text_blob.lower())
        if keywords_found >= 2:
            score += 10
            total_content_passed += 1
            feedback_parts.append(f"✅ {region_name} content preserved")
        else:
            feedback_parts.append(f"❌ {region_name} content missing")

    # Add points for file modification (5 pts)
    score += 5

    # Pass logic: Must have correct slide count AND at least 2/3 regions correct
    passed = (slide_count == 9) and (total_regions_passed >= 2) and (total_content_passed >= 2)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }