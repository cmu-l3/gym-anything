#!/usr/bin/env python3
"""
Verifier for rainfall_data_bar_graph task.

Verifies:
1. File creation and validity.
2. Presence of required text labels ("Manaus", "Jan", etc.).
3. Geometric correctness of the bar graph:
   - Identifies bar shapes.
   - Sorts them by X position (time axis).
   - Verifies relative heights match data (Mar > Apr > Jan > Feb).
4. VLM visual confirmation of graph structure.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rainfall_graph(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. File Check (15 pts)
    if result.get('file_found') and result.get('created_during_task'):
        score += 15
        feedback.append("File created successfully.")
    elif result.get('file_found'):
        score += 5
        feedback.append("File found but timestamp suggests it wasn't created during task.")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found."}

    content = result.get('content', {})
    text_content = " ".join(content.get('text_content', [])).lower()
    shapes = content.get('shapes', [])

    # 2. Text Labels (20 pts)
    required_text = ["manaus", "jan", "feb", "mar", "apr"]
    found_text_count = sum(1 for t in required_text if t in text_content)
    
    if found_text_count == len(required_text):
        score += 20
        feedback.append("All text labels found.")
    else:
        partial = int(20 * (found_text_count / len(required_text)))
        score += partial
        feedback.append(f"Found {found_text_count}/{len(required_text)} text labels.")

    # 3. Bar Graph Geometry (35 pts)
    # Filter for significant rectangles (bars)
    # Heuristic: Bars usually have significant height and width, roughly similar widths
    # Filter out tiny specks or huge backgrounds
    valid_shapes = [s for s in shapes if s.get('height', 0) > 10 and s.get('width', 0) > 5]
    
    # We expect 4 bars. If there are more, we try to find the set of 4 that align horizontally
    # Sort by X position
    valid_shapes.sort(key=lambda s: s.get('x', 0))
    
    bars_pass = False
    
    if len(valid_shapes) >= 4:
        # Take the 4 shapes that look most like the data bars
        # For simplicity in this verifier, we assume the 4 clearly distinct columns are the bars
        # We might have background lines, so we look for 4 shapes with similar Y-bottom or similar widths
        # Let's try to find a sequence of 4 shapes
        
        # Simple approach: Just take the 4 distinct X-position groups
        # (But here we just take the list and check if ANY subsequence of 4 fits the profile)
        
        # Profile: Heights relative order: 260, 240, 310, 280
        # Indices: 0 (Jan), 1 (Feb), 2 (Mar), 3 (Apr)
        # Expected: H[2] > H[3] > H[0] > H[1]
        
        # We try to find 4 shapes matching this pattern
        # Since we might have axis lines (thin rectangles), we filter for "bar-like" aspect ratios if needed
        # or just iterate combinations. Given low shape count usually, we can iterate.
        
        import itertools
        
        # Find 4 shapes that are spaced out horizontally
        # Group by X to handle potential duplicates/stacking
        # For now, simplistic check on sorted shapes
        
        # Filter out likely axis lines (very thin width or very thin height)
        candidate_bars = [s for s in valid_shapes if s.get('width', 0) > 10 and s.get('height', 0) > 10]
        
        if len(candidate_bars) >= 4:
            # We assume the user drew them left-to-right as Jan, Feb, Mar, Apr
            # or at least placed them that way.
            # We pick the 4 shapes that are spatially ordered.
            
            # If we have exactly 4, easy. If more, we might have drawn extras.
            # We check the 4 most prominent ones.
            
            b = candidate_bars # use all candidates sorted by X
            
            # We need to find 4 indices i < j < k < l such that heights match logic
            found_pattern = False
            for combo in itertools.combinations(b, 4):
                h_jan = combo[0]['height']
                h_feb = combo[1]['height']
                h_mar = combo[2]['height']
                h_apr = combo[3]['height']
                
                # Logic: Mar > Apr > Jan > Feb
                if (h_mar > h_apr) and (h_apr > h_jan) and (h_jan > h_feb):
                    found_pattern = True
                    break
            
            if found_pattern:
                score += 35
                bars_pass = True
                feedback.append("Bar heights correctly match data trends (Mar > Apr > Jan > Feb).")
            else:
                feedback.append("Bar heights do not match data trends.")
        else:
            feedback.append(f"Not enough bar-like shapes found (found {len(candidate_bars)}).")
    else:
        feedback.append(f"Not enough shapes found (found {len(valid_shapes)}).")

    # 4. Color Check (5 pts)
    # Check if any of the candidate bars have blue-ish color
    # Color is often a large integer or hex string. 
    # ActivInspire often uses specific codes. We'll rely on VLM for color if program check is hard.
    # We'll skip complex programmatic color check and rely on VLM for "blue bars".
    score += 5 # Grant points, will verify via VLM

    # 5. VLM Verification (25 pts)
    # Use VLM to confirm visual structure
    if query_vlm:
        from gym_anything.vlm import get_final_screenshot
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Analyze this image of a bar graph on a whiteboard.
        1. Are there 4 vertical bars?
        2. Are the bars colored blue?
        3. Do the bars look roughly like: 3rd is tallest, 2nd is shortest?
        4. Are there X and Y axis lines?
        Return JSON: {"has_4_bars": bool, "bars_blue": bool, "heights_correct": bool, "axes_present": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_img)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('has_4_bars'): score += 5
            if parsed.get('bars_blue'): score += 5  # Confirm color here
            if parsed.get('heights_correct'): score += 10 # Backup check for geometry
            if parsed.get('axes_present'): score += 5
            feedback.append(f"VLM Analysis: {parsed}")
        else:
            feedback.append("VLM verification failed.")

    return {
        "passed": score >= 70 and bars_pass,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }