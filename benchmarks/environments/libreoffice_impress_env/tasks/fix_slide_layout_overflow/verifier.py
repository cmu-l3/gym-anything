#!/usr/bin/env python3
"""
Verifier for fix_slide_layout_overflow task.
Reads the JSON result exported from the container which contains:
- Metadata about file modification
- ODP analysis results (parsed inside container using odfpy)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_slide_layout(traj, env_info, task_info):
    """
    Verify that the slide layout issues were fixed.
    
    Scoring:
    - File exists and modified: 10 pts
    - Slide 1 Title Centered: 15 pts
    - Slide 2 Columns Applied: 30 pts
    - Slide 3 Overlap Fixed (Position adjusted): 25 pts
    - Slide 4 Font Size Increased: 20 pts
    
    Threshold: 75 pts (Must fix columns + at least 2 others)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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

    analysis = result.get("analysis", {})
    file_created = result.get("file_created_during_task", False)
    
    score = 0
    feedback_parts = []
    
    # Check 1: File integrity (10 pts)
    if analysis.get("file_exists") and file_created and analysis.get("is_valid_odp"):
        score += 10
        feedback_parts.append("✅ File saved and valid")
    else:
        feedback_parts.append("❌ File not saved or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Slide 1 Alignment (15 pts)
    if analysis.get("title_centered"):
        score += 15
        feedback_parts.append("✅ Title centered")
    else:
        feedback_parts.append("❌ Title not centered")

    # Check 3: Slide 2 Columns (30 pts)
    if analysis.get("columns_applied"):
        score += 30
        feedback_parts.append("✅ Text columns applied")
    else:
        feedback_parts.append("❌ Text columns not applied")

    # Check 4: Slide 3 Overlap (25 pts)
    if analysis.get("overlap_fixed"):
        score += 25
        feedback_parts.append("✅ Overlap fixed (shape moved)")
    else:
        feedback_parts.append("❌ Overlap not fixed")

    # Check 5: Slide 4 Font Size (20 pts)
    if analysis.get("font_size_fixed"):
        score += 20
        feedback_parts.append("✅ Font size increased to 24pt")
    else:
        feedback_parts.append("❌ Font size incorrect")

    # Bonus: Content Preservation Check (Implicitly handled if structure found, but let's note it)
    if not analysis.get("content_preserved"):
        feedback_parts.append("⚠️ Warning: Some list content missing")
        # Optional penalty could go here

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }