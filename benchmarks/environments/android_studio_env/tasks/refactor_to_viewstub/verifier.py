#!/usr/bin/env python3
"""
Verifier for refactor_to_viewstub task.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_to_viewstub(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created layout_stats_details.xml with the extracted content.
    2. Modified activity_stats.xml to use ViewStub.
    3. Modified StatsActivity.kt to inflate the ViewStub.
    4. Maintained a buildable project.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Read result JSON
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    metadata = task_info.get('metadata', {})
    unique_strings = metadata.get('unique_content_strings', [])
    stub_id = metadata.get('stub_id', 'stub_details')

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Criterion 1: Layout Extraction (30 pts)
    # ------------------------------------------------------------------
    details_content = result.get('layout_details_content', '')
    details_exists = result.get('layout_details_exists', False)
    
    criterion_1_score = 0
    if details_exists and details_content:
        # Check if extracted content contains the specific strings from the heavy layout
        found_strings = [s for s in unique_strings if s in details_content]
        if len(found_strings) >= 3:
            criterion_1_score = 30
            feedback.append("✓ Extracted layout file created with correct content.")
        elif len(found_strings) > 0:
            criterion_1_score = 15
            feedback.append("⚠ Extracted layout file exists but missing some content elements.")
        else:
            feedback.append("✗ Extracted layout file exists but appears empty or incorrect.")
    else:
        feedback.append("✗ New layout file 'layout_stats_details.xml' not found.")
    
    score += criterion_1_score

    # ------------------------------------------------------------------
    # Criterion 2: ViewStub Implementation (30 pts)
    # ------------------------------------------------------------------
    stats_content = result.get('layout_stats_content', '')
    stats_exists = result.get('layout_stats_exists', False)
    
    criterion_2_score = 0
    if stats_exists and stats_content:
        # Check for ViewStub tag
        has_stub_tag = '<ViewStub' in stats_content
        # Check for layout reference
        has_layout_ref = '@layout/layout_stats_details' in stats_content
        
        if has_stub_tag and has_layout_ref:
            criterion_2_score = 30
            feedback.append("✓ ViewStub correctly added to activity layout.")
        elif has_stub_tag:
            criterion_2_score = 15
            feedback.append("⚠ ViewStub tag found but layout reference seems incorrect.")
        else:
            feedback.append("✗ No ViewStub tag found in activity layout.")
            
        # Penalty if heavy content is still there (inline)
        for s in unique_strings:
            if s in stats_content:
                criterion_2_score = max(0, criterion_2_score - 5)
                feedback.append(f"⚠ Found heavy content '{s}' still inside main layout (should be removed).")
                break
    else:
        feedback.append("✗ Main activity layout file missing.")
        
    score += criterion_2_score

    # ------------------------------------------------------------------
    # Criterion 3: Activity Logic Update (20 pts)
    # ------------------------------------------------------------------
    activity_content = result.get('activity_content', '')
    
    criterion_3_score = 0
    if activity_content:
        # Check for stub usage patterns
        # Pattern 1: viewStub.inflate()
        # Pattern 2: binding.stub.inflate()
        # Pattern 3: findViewById<ViewStub>(...).inflate()
        
        has_inflate = 'inflate()' in activity_content or '.inflate' in activity_content
        has_stub_ref = 'ViewStub' in activity_content or stub_id in activity_content
        
        if has_inflate and has_stub_ref:
            criterion_3_score = 20
            feedback.append("✓ Activity logic updated to handle ViewStub inflation.")
        elif has_inflate or has_stub_ref:
            criterion_3_score = 10
            feedback.append("⚠ Activity logic seems partially updated (found inflation or stub ref, but not both clearly).")
        else:
            feedback.append("✗ No logic found in Activity to inflate the ViewStub.")
    
    score += criterion_3_score

    # ------------------------------------------------------------------
    # Criterion 4: Build Success (20 pts)
    # ------------------------------------------------------------------
    build_success = result.get('build_success', False)
    
    if build_success:
        score += 20
        feedback.append("✓ Project compiles successfully.")
    else:
        feedback.append("✗ Project failed to compile.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }