#!/usr/bin/env python3
"""
Verifier for landscape_maintenance_guide task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_landscape_manual(traj, env_info, task_info):
    """
    Verify the Landscape Maintenance Manual creation.
    
    Criteria:
    1. File creation (10 pts)
    2. Seasonal Organization (Heading 1 = Spring/Summer/Fall/Winter) (20 pts)
    3. Installed Plants Inclusion (20 pts)
    4. Distractor Plants Exclusion (10 pts)
    5. Formatting (Heading 2 used for plants) (15 pts)
    6. Contact Table (15 pts)
    7. TOC & Page Numbers (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    installed_plants = metadata.get('installed_plants', [])
    distractor_plants = metadata.get('distractor_plants', [])
    seasons = metadata.get('seasons', ["Spring", "Summer", "Fall", "Winter"])
    contacts = metadata.get('contacts', [])
    
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
            
    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get('file_exists') and result.get('file_size', 0) > 1000:
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found or empty."}
        
    full_text = result.get('full_text', "").lower()
    h1_texts = [h.lower() for h in result.get('heading1_texts', [])]
    h2_texts = [h.lower() for h in result.get('heading2_texts', [])]
    
    # 2. Seasonal Organization (Heading 1) (20 pts)
    # Check if all seasons appear in Heading 1 list
    seasons_found = [s for s in seasons if any(s.lower() in h for h in h1_texts)]
    if len(seasons_found) == 4:
        score += 20
        feedback.append("Document correctly organized by Season (Heading 1).")
    elif len(seasons_found) > 0:
        score += 10
        feedback.append(f"Partial seasonal organization found: {seasons_found}")
    else:
        feedback.append("Seasonal organization (Heading 1) missing.")
        
    # 3. Installed Plants Inclusion (20 pts)
    # Check if installed plants are present in text (checking full text is safer than strict H2 check for this)
    plants_found_count = sum(1 for p in installed_plants if p.lower() in full_text)
    if plants_found_count == len(installed_plants):
        score += 20
        feedback.append("All installed plants included.")
    elif plants_found_count >= len(installed_plants) * 0.7:
        score += 10
        feedback.append(f"Most installed plants included ({plants_found_count}/{len(installed_plants)}).")
    else:
        feedback.append(f"Missing many installed plants ({plants_found_count}/{len(installed_plants)} found).")
        
    # 4. Distractor Plants Exclusion (10 pts)
    # Check if distractor plants are absent
    distractors_found = [p for p in distractor_plants if p.lower() in full_text]
    if not distractors_found:
        score += 10
        feedback.append("Correctly filtered out non-installed plants.")
    else:
        feedback.append(f"Included plants that should have been excluded: {distractors_found}")
        
    # 5. Formatting - Plants as Heading 2 (15 pts)
    # Check if a sample of installed plants appear in H2 list
    # We check if at least 50% of installed plants are formatted as H2
    h2_plant_matches = sum(1 for p in installed_plants if any(p.lower() in h for h in h2_texts))
    if h2_plant_matches >= len(installed_plants) * 0.5:
        score += 15
        feedback.append("Plants correctly formatted as Heading 2.")
    else:
        feedback.append("Plants not consistently formatted as Heading 2.")
        
    # 6. Contact Table (15 pts)
    # Check if table content contains contact info
    table_content = " ".join(result.get('table_content', [])).lower()
    contact_matches = 0
    for c in contacts:
        if c['company'].lower() in table_content or c['phone'] in table_content:
            contact_matches += 1
            
    if contact_matches == len(contacts):
        score += 15
        feedback.append("Contact table created with correct info.")
    elif contact_matches > 0:
        score += 7
        feedback.append("Contact table partially correct.")
    else:
        feedback.append("Contact table missing or empty.")
        
    # 7. TOC & Page Numbers (10 pts)
    nav_score = 0
    if result.get('has_toc'):
        nav_score += 5
    if result.get('has_page_numbers'):
        nav_score += 5
    score += nav_score
    if nav_score == 10:
        feedback.append("TOC and Page Numbers present.")
    elif nav_score > 0:
        feedback.append("Partial navigation elements present.")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }