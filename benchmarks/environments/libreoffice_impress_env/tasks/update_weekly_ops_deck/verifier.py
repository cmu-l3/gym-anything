#!/usr/bin/env python3
"""
Verifier for Update Weekly Ops Deck task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_weekly_ops_deck(traj, env_info, task_info):
    """
    Verify the presentation update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. File Existence & Timing (10 pts)
    if result.get('file_exists'):
        # Check timestamp
        mtime = int(result.get('file_mtime', 0))
        start_time = int(result.get('task_start', 0))
        if mtime > start_time:
            score += 10
            feedback_parts.append("✅ File saved correctly")
        else:
            feedback_parts.append("❌ File exists but was not saved during task")
    else:
        feedback_parts.append("❌ File 'Ops_Review_Week_43.odp' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Get data
    parsed = result.get('parsed_content', {})
    expected = result.get('expected_values', {})
    
    if parsed.get('error'):
        return {"passed": False, "score": score, "feedback": f"File parsing error: {parsed['error']}"}

    slides = parsed.get('slides', [])
    tables = parsed.get('tables', [])
    shapes = parsed.get('shapes', [])

    # 2. Slide 1: Subtitle Date Update (15 pts)
    date_updated = False
    expected_date = expected.get('date', '')
    
    if len(slides) > 0:
        s1_text = " ".join(slides[0].get('text', []))
        if expected_date in s1_text:
            date_updated = True
    
    if date_updated:
        score += 15
        feedback_parts.append("✅ Date updated")
    else:
        feedback_parts.append(f"❌ Date not updated (Expected '{expected_date}')")

    # 3. Slide 2: Table Values (30 pts)
    table_correct = False
    exp_throughput = str(expected.get('throughput', ''))
    exp_defect = str(expected.get('defect_rate', ''))
    
    # Find the metrics table
    found_table = None
    for tbl in tables:
        # Check headers to identify table
        if tbl and len(tbl) > 0 and "Metric" in tbl[0]:
            found_table = tbl
            break
            
    if found_table:
        # Check rows
        throughput_found = False
        defect_found = False
        
        for row in found_table:
            # Row format: [MetricName, Week41, Week42]
            if len(row) >= 3:
                if "Throughput" in row[0] and exp_throughput in row[2]:
                    throughput_found = True
                if "Defect Rate" in row[0] and exp_defect in row[2]:
                    defect_found = True
        
        if throughput_found and defect_found:
            score += 30
            feedback_parts.append("✅ Table metrics updated")
        elif throughput_found or defect_found:
            score += 15
            feedback_parts.append("⚠️ Partial table update")
        else:
            feedback_parts.append(f"❌ Table values incorrect (Expected {exp_throughput}, {exp_defect})")
    else:
        feedback_parts.append("❌ Metrics table not found")

    # 4. Slide 3: Status Color (25 pts)
    # Check for shape named "MigrationStatus" or similar, check fill color
    color_correct = False
    green_variants = ["#00ff00", "#008000", "#00aa00", "#008000"] # Basic hex codes
    
    found_shape = None
    for shape in shapes:
        if shape.get('name') == 'MigrationStatus':
            found_shape = shape
            break
    
    if found_shape:
        fill = str(found_shape.get('fill_color', '')).lower()
        # Check if green-ish (contains 00ff00 or similar, or just check simple hex)
        # ODF usually stores exact hex. We generated it, but user might pick from palette.
        # Palette greens: #008000 (Green), #00ff00 (Lime), #90ee90 (LightGreen)
        # We accept if it's NOT red (#ff0000) and looks vaguely green, or simple hex check
        
        # Robust check: Red component low, Green component high
        # Or simple exact matches for common palette greens
        if fill in ["#008000", "#00ff00", "#66ff66", "#32cd32", "#006400"]: 
            color_correct = True
        elif fill != "#ff0000":
            # If changed from red, give partial credit or benefit of doubt if likely green
            # (Simplification: Just check if not red for now, but strictly we want green)
            if "00" in fill and "ff" not in fill[1:3]: # heuristic
                 color_correct = True
    
    if color_correct:
        score += 25
        feedback_parts.append("✅ Status color changed to Green")
    else:
        feedback_parts.append("❌ Status color not green")

    # 5. Slide 4: List Item Removal (20 pts)
    sarah_removed = True
    if len(slides) > 3:
        s4_text = " ".join(slides[3].get('text', []))
        if "Sarah" in s4_text:
            sarah_removed = False
    
    if sarah_removed:
        score += 20
        feedback_parts.append("✅ 'Sarah' removed from list")
    else:
        feedback_parts.append("❌ 'Sarah' still present in list")

    # Final Result
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }