#!/usr/bin/env python3
"""
Verifier for retail_shelf_planogram task.

Logic:
1. Files exist and modified (10 pts)
2. PNG export exists (10 pts)
3. Title label exists (5 pts)
4. Shape Analysis (75 pts):
   - Categorize found shapes into Top, Eye, Touch, Bottom based on strategy.
   - Calculate average Y coordinate for each category found.
   - Verify Y_Top < Y_Eye < Y_Touch < Y_Bottom (since Y=0 is top of canvas).
   - Partial credit for correct pairwise relationships (e.g. Top < Bottom).
"""

import json
import tempfile
import os
import logging
import statistics

logger = logging.getLogger(__name__)

def verify_retail_shelf_planogram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    metadata = task_info.get('metadata', {})
    categories = metadata.get('categories', {
        "top": ["All Bran", "Muesli"],
        "eye": ["Corn Flakes", "Raisin Bran"],
        "touch": ["Froot Loops", "Apple Jacks"],
        "bottom": ["Bag O' Puffs", "Value Oats"]
    })

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name): os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File checks (20 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file saved")
    else:
        feedback.append("Draw.io file missing or not saved")
        
    if result.get('png_exists'):
        score += 10
        feedback.append("PNG export found")
    else:
        feedback.append("PNG export missing")

    # Analysis data
    analysis = result.get('analysis', {})
    shapes = analysis.get('shapes_found', [])
    
    # 2. Title check (5 pts)
    if analysis.get('title_found'):
        score += 5
        feedback.append("Title label found")
    
    # 3. Shape Classification & Spatial Logic (75 pts)
    # Group found Y-coordinates by category
    cat_y_values = {"top": [], "eye": [], "touch": [], "bottom": []}
    found_count = 0
    
    for s in shapes:
        name = s['name']
        y = s['y']
        found_count += 1
        
        for cat, items in categories.items():
            if name in items:
                cat_y_values[cat].append(y)
                break
    
    # Score for finding products (max 15 pts)
    # 8 products total, approx 2 pts each
    prod_score = min(15, found_count * 2)
    score += prod_score
    if found_count < 8:
        feedback.append(f"Found {found_count}/8 products")
    else:
        feedback.append("All products found")

    # Calculate average Y for each category to compare levels
    avg_y = {}
    for cat, vals in cat_y_values.items():
        if vals:
            avg_y[cat] = statistics.mean(vals)
            
    # Spatial Logic (60 pts)
    # We expect: Top_Y < Eye_Y < Touch_Y < Bottom_Y (smaller Y is higher on screen)
    # We will test 6 pairwise relationships (10 pts each):
    # Top < Eye, Top < Touch, Top < Bottom
    # Eye < Touch, Eye < Bottom
    # Touch < Bottom
    
    spatial_score = 0
    comparisons = [
        ("top", "eye"), ("top", "touch"), ("top", "bottom"),
        ("eye", "touch"), ("eye", "bottom"),
        ("touch", "bottom")
    ]
    
    success_pairs = 0
    for high, low in comparisons:
        if high in avg_y and low in avg_y:
            if avg_y[high] < avg_y[low]:
                spatial_score += 10
                success_pairs += 1
            else:
                feedback.append(f"Spatial Error: {high.title()} shelf is below {low.title()} shelf")
        else:
            # If a category is missing, we can't compare, no points
            pass
            
    score += spatial_score
    
    if success_pairs == 6:
        feedback.append("Perfect shelf arrangement!")
    elif success_pairs > 0:
        feedback.append(f"Spatial arrangement partial success ({success_pairs}/6 relations correct)")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }