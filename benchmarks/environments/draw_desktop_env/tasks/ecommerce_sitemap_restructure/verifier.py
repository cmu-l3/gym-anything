#!/usr/bin/env python3
"""
Verifier for ecommerce_sitemap_restructure task.

Scoring (100 points total):
- File existence & PNG Export: 10 pts
- Core Structure (Root + Main Cats): 30 pts
- Content Completeness (Leaf nodes): 25 pts
- Hierarchy Accuracy (Connected edges): 15 pts
- Visual Encoding (Colors): 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Expected Hex Colors (Approximate matching allowed)
ORANGE_HEX_PREFIXES = ['#ff9', '#ff8', '#ffa', '#f80', '#fa0', 'orange'] # orange variants
GREEN_HEX_PREFIXES = ['#66f', '#9f9', '#0f0', '#3c3', '#00f', '#00c', 'green'] # green variants

def is_color_match(color_code, target_type):
    """Check if color code matches target type (orange/green)."""
    if not color_code: return False
    c = color_code.lower()
    
    if target_type == 'orange':
        return any(c.startswith(p) for p in ORANGE_HEX_PREFIXES)
    if target_type == 'green':
        return any(c.startswith(p) for p in GREEN_HEX_PREFIXES)
    return False

def verify_ecommerce_sitemap_restructure(traj, env_info, task_info):
    """Verify the Luma sitemap restructure."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Artifacts (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 5
        feedback.append("Drawio file saved")
    else:
        feedback.append("Drawio file missing/unmodified")

    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 5
        feedback.append("PNG exported")
    else:
        feedback.append("PNG export missing/empty")

    # Analysis Data
    analysis = result.get('analysis', {})
    nodes = analysis.get('nodes', [])
    # Create lookup map: label -> node info
    node_map = {n['label']: n for n in nodes}
    
    # 2. Core Structure (30 pts)
    # Expect: Home, Men, Women, Gear, Collections
    core_needed = ['home', 'men', 'women', 'gear', 'collections']
    found_core = [c for c in core_needed if c in node_map]
    
    if 'home' in node_map:
        score += 10
        feedback.append("Root 'Home' found")
    
    # Remaining 4 main cats = 5 pts each (20 total)
    main_cats_score = 0
    for cat in ['men', 'women', 'gear', 'collections']:
        if cat in node_map:
            main_cats_score += 5
    score += main_cats_score
    feedback.append(f"Main categories found: {len(found_core)-1}/4")

    # 3. Content Completeness & Specific Checks (25 pts)
    # Check for specific leaf nodes that shouldn't have changed + new ones
    leaves_to_check = ['hoodies', 'tees', 'pants', 'shorts', 'bags', 'watches', 'eco-friendly', 'outerwear', 'yoga']
    found_leaves = [l for l in leaves_to_check if any(l in n for n in node_map.keys())] # loose matching
    
    # 2 pts per leaf found (approx 18 pts)
    leaf_score = min(20, len(found_leaves) * 2.5)
    score += leaf_score
    
    # Check REMOVED node "Tanks" (5 pts)
    if not any('tanks' in n for n in node_map.keys()):
        score += 5
        feedback.append("Correctly removed 'Tanks'")
    else:
        feedback.append("Failed to remove 'Tanks'")

    # 4. Hierarchy/Edges (15 pts)
    # Simple proxy: do we have enough edges?
    # Min nodes ~20. Min edges should be ~19.
    edge_count = analysis.get('edge_count', 0)
    node_count = analysis.get('node_count', 0)
    
    if edge_count >= (node_count * 0.8) and node_count > 5:
        score += 15
        feedback.append(f"Hierarchy connected ({edge_count} edges)")
    elif edge_count > 5:
        score += 7
        feedback.append(f"Hierarchy partially connected ({edge_count} edges)")
    else:
        feedback.append("Diagram lacks connections")

    # 5. Visual Encoding (20 pts)
    # Check specific visual rules
    color_score = 0
    
    # Rule 1: Outerwear = Orange (Renamed)
    outerwear = node_map.get('outerwear')
    if outerwear:
        if is_color_match(outerwear['color'], 'orange'):
            color_score += 5
            feedback.append("Outerwear: Orange (Correct)")
        else:
            feedback.append(f"Outerwear: {outerwear['color']} (Expected Orange)")
    
    # Rule 2: Collections = Green (New)
    collections = node_map.get('collections')
    if collections:
        if is_color_match(collections['color'], 'green'):
            color_score += 5
            feedback.append("Collections: Green (Correct)")
        else:
            feedback.append(f"Collections: {collections['color']} (Expected Green)")

    # Rule 3: Yoga = Green (New)
    yoga = node_map.get('yoga')
    if yoga:
        if is_color_match(yoga['color'], 'green'):
            color_score += 5
            feedback.append("Yoga: Green (Correct)")
    
    # Rule 4: Eco-Friendly = Green (New)
    eco = node_map.get('eco-friendly')
    if eco:
        if is_color_match(eco['color'], 'green'):
            color_score += 5
            feedback.append("Eco-Friendly: Green (Correct)")

    score += color_score

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "found_nodes": list(node_map.keys()),
            "edge_count": edge_count
        }
    }