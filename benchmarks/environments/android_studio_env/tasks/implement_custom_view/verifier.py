#!/usr/bin/env python3
"""
Verifier for implement_custom_view task.

Criteria:
1. attrs.xml exists and defines 'StatusDotView' styleable with 'dotColor' attribute. (15 pts)
2. StatusDotView.kt exists, extends View. (15 pts)
3. StatusDotView.kt uses obtainStyledAttributes to read 'dotColor'. (20 pts)
4. StatusDotView.kt overrides onDraw and calls drawCircle. (20 pts)
5. activity_main.xml includes the custom view with app:dotColor set. (10 pts)
6. Project builds successfully. (20 pts)

Pass Threshold: 70 points AND Build Success
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_custom_view(traj, env_info, task_info):
    """Verify the custom view implementation task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Extract data
    attrs_content = result.get('attrs_content', '')
    view_content = result.get('view_content', '')
    layout_content = result.get('layout_content', '')
    build_success = result.get('build_success', False)
    
    # 1. Verify attributes (15 pts)
    # Looking for <declare-styleable name="StatusDotView"> and <attr name="dotColor" format="color"/>
    if 'StatusDotView' in attrs_content and 'dotColor' in attrs_content:
        score += 15
        feedback_parts.append("Attributes defined correctly (15/15)")
    elif 'StatusDotView' in attrs_content:
        score += 5
        feedback_parts.append("Styleable defined but attribute missing/wrong (5/15)")
    else:
        feedback_parts.append("Attributes not defined in attrs.xml (0/15)")
        
    # 2. Verify View Class Structure (15 pts)
    # Extends View, package declaration
    if 'class StatusDotView' in view_content and ('View' in view_content or 'android.view.View' in view_content):
        score += 15
        feedback_parts.append("StatusDotView class structure correct (15/15)")
    elif 'class StatusDotView' in view_content:
        score += 5
        feedback_parts.append("StatusDotView class exists but inheritance unclear (5/15)")
    else:
        feedback_parts.append("StatusDotView class not found (0/15)")
        
    # 3. Verify Attribute Parsing (20 pts)
    # obtainStyledAttributes, dotColor usage
    if 'obtainStyledAttributes' in view_content and ('dotColor' in view_content or 'R.styleable' in view_content):
        score += 20
        feedback_parts.append("Attribute parsing logic detected (20/20)")
    else:
        feedback_parts.append("Attribute parsing logic missing/incorrect (0/20)")
        
    # 4. Verify Drawing Logic (20 pts)
    # onDraw override, drawCircle
    if 'onDraw' in view_content and 'drawCircle' in view_content:
        score += 20
        feedback_parts.append("Drawing logic (onDraw/drawCircle) detected (20/20)")
    elif 'onDraw' in view_content:
        score += 10
        feedback_parts.append("onDraw overridden but drawCircle missing (10/20)")
    else:
        feedback_parts.append("Drawing logic missing (0/20)")
        
    # 5. Verify Layout Usage (10 pts)
    # Custom view tag in XML, dotColor attribute usage
    if 'StatusDotView' in layout_content and 'dotColor' in layout_content:
        score += 10
        feedback_parts.append("View added to layout with custom attribute (10/10)")
    elif 'StatusDotView' in layout_content:
        score += 5
        feedback_parts.append("View added to layout but attribute missing (5/10)")
    else:
        feedback_parts.append("Custom view not found in activity_main.xml (0/10)")
        
    # 6. Verify Build (20 pts)
    if build_success:
        score += 20
        feedback_parts.append("Project builds successfully (20/20)")
    else:
        feedback_parts.append("Build failed (0/20)")
        
    # Calculate Final Status
    # Must compile and meet score threshold
    passed = (score >= 70) and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }