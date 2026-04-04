#!/usr/bin/env python3
"""
Verifier for implement_rtl_support task.

Verifies:
1. AndroidManifest.xml contains android:supportsRtl="true"
2. activity_profile.xml uses start/end instead of left/right
3. Project builds successfully
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_rtl_support(traj, env_info, task_info):
    """Verify RTL support implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh (includes build status and file contents backup)
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Also try to read files directly for authoritative check
    project_dir = task_info.get("metadata", {}).get("project_dir", "/home/ga/AndroidStudioProjects/GlobalNews")
    
    def read_file(path):
        try:
            tf = tempfile.NamedTemporaryFile(delete=False)
            tf.close()
            copy_from_env(path, tf.name)
            with open(tf.name, 'r') as f:
                return f.read()
        except Exception:
            return None
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    manifest_content = read_file(f"{project_dir}/app/src/main/AndroidManifest.xml")
    layout_content = read_file(f"{project_dir}/app/src/main/res/layout/activity_profile.xml")

    # Fallback to JSON content if direct read failed
    if not manifest_content:
        manifest_content = task_result.get("manifest_content", "")
    if not layout_content:
        layout_content = task_result.get("layout_content", "")
    
    build_success = task_result.get("build_success", False)

    score = 0
    feedback = []

    # 1. Verify Manifest (20 pts)
    if 'android:supportsRtl="true"' in manifest_content:
        score += 20
        feedback.append("Manifest: RTL enabled (20/20)")
    else:
        feedback.append("Manifest: android:supportsRtl=\"true\" missing (0/20)")

    # 2. Verify Layout Attributes (60 pts total)
    # Check for forbidden attributes (Left/Right)
    forbidden_patterns = [
        r'layout_margin(Left|Right)',
        r'padding(Left|Right)',
        r'layout_alignParent(Left|Right)',
        r'layout_to(Left|Right)Of',
        r'gravity="[^"]*(left|right)[^"]*"'
    ]
    
    legacy_issues = 0
    for pattern in forbidden_patterns:
        matches = re.findall(pattern, layout_content)
        if matches:
            legacy_issues += len(matches)
            feedback.append(f"Layout: Found {len(matches)} legacy attributes matching '{pattern}'")

    # Check for required attributes (Start/End)
    required_patterns = [
        r'layout_margin(Start|End)',
        r'padding(Start|End)',
        r'gravity="[^"]*(start|end)[^"]*"'
    ]
    
    modern_attributes = 0
    for pattern in required_patterns:
        matches = re.findall(pattern, layout_content)
        modern_attributes += len(matches)

    # Scoring logic for layout
    # Expecting ~10-12 changes. 
    # If legacy_issues == 0 and modern_attributes > 5, full points.
    
    if legacy_issues == 0 and modern_attributes > 0:
        score += 60
        feedback.append("Layout: All attributes migrated to Start/End (60/60)")
    elif legacy_issues == 0:
        # Maybe they just deleted everything? Unlikely to build.
        score += 10
        feedback.append("Layout: No legacy attributes found, but no modern ones either? (10/60)")
    else:
        # Partial credit: Max 60, minus 5 per legacy issue
        partial = max(0, 60 - (legacy_issues * 5))
        score += partial
        feedback.append(f"Layout: {legacy_issues} legacy attributes remaining ({partial}/60)")

    # 3. Verify Build (20 pts)
    if build_success:
        score += 20
        feedback.append("Build: Success (20/20)")
    else:
        feedback.append("Build: Failed (0/20)")

    passed = score >= 80 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }