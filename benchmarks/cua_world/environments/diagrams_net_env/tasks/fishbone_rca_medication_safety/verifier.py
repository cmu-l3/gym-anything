#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fishbone_rca_medication_safety(traj, env_info, task_info):
    """
    Verifies the Fishbone RCA diagram task.
    
    Criteria:
    1. File modified and PDF exported.
    2. Shape count increased significantly (populating the diagram).
    3. Content verification: Check for keywords from the incident report.
    4. Color coding: Check for use of multiple distinct fill colors.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
        
    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('keywords', [])
    min_shapes = metadata.get('min_shapes', 35) # Skeleton is ~15, expect +20 causes
    
    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Logic
    score = 0
    feedback = []
    
    # 1. Basics (15 pts)
    if result.get('file_modified'):
        score += 5
        feedback.append("Draw.io file modified.")
    else:
        feedback.append("Draw.io file NOT modified.")
        
    if result.get('pdf_exists') and result.get('pdf_created_during_task'):
        score += 10
        feedback.append("PDF export successful.")
    else:
        feedback.append("PDF export missing or not created during task.")

    analysis = result.get('diagram_analysis', {})
    
    # 2. Shape Count (Populating the diagram) (30 pts)
    final_count = analysis.get('vertex_count', 0)
    initial_count = int(result.get('initial_shape_count', 15))
    added_shapes = final_count - initial_count
    
    if final_count >= min_shapes:
        score += 30
        feedback.append(f"Excellent diagram population ({final_count} shapes).")
    elif final_count >= (min_shapes - 10):
        score += 15
        feedback.append(f"Moderate diagram population ({final_count} shapes).")
    else:
        feedback.append(f"Insufficient causes added (Only {final_count} total shapes).")

    # 3. Content Verification (Keywords) (35 pts)
    text_content = " ".join(analysis.get('text_content', [])).lower()
    matches = 0
    missing_keywords = []
    
    for kw in expected_keywords:
        if kw.lower() in text_content:
            matches += 1
        else:
            if len(missing_keywords) < 5: # Limit feedback clutter
                missing_keywords.append(kw)
    
    match_percentage = matches / len(expected_keywords) if expected_keywords else 0
    
    if match_percentage >= 0.7:
        score += 35
        feedback.append(f"High content accuracy ({matches} keywords matched).")
    elif match_percentage >= 0.4:
        score += 20
        feedback.append(f"Partial content accuracy ({matches} keywords matched).")
    else:
        score += 5
        feedback.append(f"Low content accuracy ({matches} keywords matched). Missing: {', '.join(missing_keywords)}...")

    # 4. Color Coding (15 pts)
    colors = analysis.get('fill_colors', [])
    unique_colors = len(colors)
    
    if unique_colors >= 4:
        score += 15
        feedback.append(f"Good color coding applied ({unique_colors} colors).")
    elif unique_colors >= 2:
        score += 5
        feedback.append(f"Minimal color coding ({unique_colors} colors).")
    else:
        feedback.append("No distinct color coding detected.")

    # 5. Title (5 pts)
    if analysis.get('title_found'):
        score += 5
        feedback.append("Correct title added.")
    else:
        feedback.append("Title missing or incorrect.")

    # Final tally
    passed = score >= 60 and result.get('pdf_created_during_task')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }