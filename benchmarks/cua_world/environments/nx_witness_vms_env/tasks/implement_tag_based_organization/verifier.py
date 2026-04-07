#!/usr/bin/env python3
import json
import os
import tempfile

def verify_implement_tag_based_organization(traj, env_info, task_info):
    """
    Verifies that:
    1. Cameras have the correct tags applied.
    2. A 'Storm Watch' layout exists.
    3. The layout contains ONLY the outdoor cameras.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Load ground truth from metadata
    metadata = task_info.get('metadata', {})
    expected_tags = metadata.get('tag_schema', {})
    outdoor_cams = set(metadata.get('outdoor_cameras', []))
    
    score = 0
    max_score = 100
    feedback = []

    # 2. Verify Camera Tags (50 points)
    # 10 points per camera
    cameras_result = result.get('cameras', {})
    tag_score = 0
    
    for cam_name, required_tags in expected_tags.items():
        if cam_name not in cameras_result:
            feedback.append(f"❌ Camera '{cam_name}' not found in system.")
            continue
            
        actual_tags = set(cameras_result[cam_name].get('tags', []))
        req_tags_set = set(required_tags)
        
        # Check if all required tags are present
        if req_tags_set.issubset(actual_tags):
            tag_score += 10
        else:
            missing = req_tags_set - actual_tags
            feedback.append(f"⚠️ '{cam_name}' missing tags: {', '.join(missing)}")
            
            # Partial credit: 5 pts if at least one correct tag
            if not req_tags_set.isdisjoint(actual_tags):
                tag_score += 5

    score += tag_score
    feedback.append(f"Tagging Score: {tag_score}/50")

    # 3. Verify Layout Creation (20 points)
    layout = result.get('target_layout')
    if layout:
        score += 20
        feedback.append("✅ Layout 'Storm Watch' created.")
    else:
        feedback.append("❌ Layout 'Storm Watch' not found.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 4. Verify Layout Content (30 points)
    # Must contain ALL outdoor cameras and NO others
    layout_items = set(layout.get('items', []))
    
    # Check 1: Are all outdoor cameras present?
    missing_outdoor = outdoor_cams - layout_items
    if not missing_outdoor:
        score += 15
        feedback.append("✅ All outdoor cameras present in layout.")
    else:
        feedback.append(f"❌ Missing from layout: {', '.join(missing_outdoor)}")
        # Partial credit per camera
        present_count = len(outdoor_cams) - len(missing_outdoor)
        score += (present_count * 5)

    # Check 2: Are there any extra (indoor) cameras?
    # Any item in layout_items that is NOT in outdoor_cams is an error
    extras = layout_items - outdoor_cams
    if not extras:
        score += 15
        feedback.append("✅ No incorrect cameras in layout.")
    else:
        feedback.append(f"❌ Incorrect cameras included: {', '.join(extras)}")
        # Penalty? Or just 0 points for this section.
        # Let's say 0 points for this half if there are errors.

    # 5. Final Calculation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }