#!/usr/bin/env python3
"""
Verifier for pharma_rca_fishbone task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pharma_rca_fishbone(traj, env_info, task_info):
    """
    Verifies the creation of the Fishbone diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_cause_keywords', [])

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Modification (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file created and saved.")
    else:
        feedback.append("Draw.io file not found or not saved.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get('analysis', {})
    text_content_list = analysis.get('text_content', [])
    full_text = " ".join(text_content_list).lower()

    # 2. Structural Elements (20 pts)
    # Check for 6M categories
    categories_found = analysis.get('categories_found', [])
    cat_score = len(categories_found) * 2  # Max 12
    if len(categories_found) == 6:
        cat_score = 15 # Bonus for all
        feedback.append("All 6M categories found.")
    else:
        feedback.append(f"Found {len(categories_found)}/6 categories.")
    score += cat_score

    # Check shape count (complex diagram expectation)
    num_shapes = analysis.get('num_shapes', 0)
    if num_shapes >= 20:
        score += 5
        feedback.append(f"Complex diagram structure detected ({num_shapes} shapes).")
    elif num_shapes >= 10:
        score += 2
        feedback.append("Simple diagram structure detected.")
    
    # 3. Content Accuracy (40 pts)
    # Check for specific root cause keywords from the report
    keywords_found = 0
    missing_keywords = []
    for kw in required_keywords:
        if kw.lower() in full_text:
            keywords_found += 1
        else:
            missing_keywords.append(kw)
    
    # Scale score based on keywords found (max 40)
    # There are ~13 keywords. 3 pts each approx.
    keyword_score = min(40, keywords_found * 3)
    score += keyword_score
    feedback.append(f"Content match: {keywords_found}/{len(required_keywords)} specific cause details found.")
    
    if keywords_found < 5:
        feedback.append(f"Missing key details like: {', '.join(missing_keywords[:3])}...")

    # 4. Multi-page Requirement (15 pts)
    num_pages = analysis.get('num_pages', 0)
    page_names = [p.lower() for p in analysis.get('page_names', [])]
    
    if num_pages >= 2:
        score += 10
        feedback.append("Multi-page document created.")
        # Check for CAPA page
        if any("corrective" in name or "action" in name or "capa" in name for name in page_names):
            score += 5
            feedback.append("Corrective Actions page identified.")
    else:
        feedback.append("Failed to create second page.")

    # 5. PNG Export (15 pts)
    if result.get('png_exists'):
        png_size = result.get('png_size', 0)
        if png_size > 5000: # Reasonable size for a diagram
            score += 15
            feedback.append("PNG exported successfully.")
        else:
            score += 5
            feedback.append("PNG exported but seems empty/too small.")
    else:
        feedback.append("PNG export missing.")

    passed = score >= 60 and result.get('file_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }