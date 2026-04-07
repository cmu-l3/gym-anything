#!/usr/bin/env python3
"""
Verifier for Create Appointment Category task in OpenEMR

Verifies that a new "Telehealth Visit" appointment category was created
with the correct specifications.

Scoring (100 points total):
- Category exists and newly created: 30 points
- Category name contains "Telehealth": 25 points  
- Duration is ~20 minutes (±5 min): 20 points
- Color is assigned: 10 points
- Description is present: 10 points
- Category is active: 5 points

Pass threshold: 70 points with category_created AND correct_name
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_appointment_category(traj, env_info, task_info):
    """
    Verify that the Telehealth Visit appointment category was created correctly.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available - cannot verify task"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_category_name', 'Telehealth Visit')
    expected_duration = metadata.get('expected_duration_minutes', 20)
    duration_tolerance = metadata.get('duration_tolerance_minutes', 5)
    scoring = metadata.get('scoring', {
        'category_created': 30,
        'correct_name': 25,
        'correct_duration': 20,
        'color_assigned': 10,
        'description_present': 10,
        'category_active': 5
    })
    pass_threshold = metadata.get('pass_threshold', 70)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/create_category_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy/read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read verification data: {e}"
            }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "category_created": False,
        "correct_name": False,
        "correct_duration": False,
        "color_assigned": False,
        "description_present": False,
        "category_active": False
    }
    
    # Extract data from result
    baseline_max_id = result.get('baseline_max_id', 0)
    baseline_count = result.get('baseline_count', 0)
    current_count = result.get('current_count', 0)
    category_found = result.get('category_found', False)
    category = result.get('category', {})
    validation = result.get('validation', {})
    
    logger.info(f"Baseline: max_id={baseline_max_id}, count={baseline_count}")
    logger.info(f"Current: count={current_count}, found={category_found}")
    logger.info(f"Category: {category}")
    
    # CRITERION 1: Category exists and was newly created (30 points)
    if category_found:
        cat_id = category.get('id', '')
        try:
            cat_id_int = int(cat_id) if cat_id else 0
        except (ValueError, TypeError):
            cat_id_int = 0
            
        if cat_id_int > baseline_max_id:
            score += scoring.get('category_created', 30)
            subscores["category_created"] = True
            feedback_parts.append(f"✅ New category created (ID: {cat_id})")
        elif cat_id_int > 0:
            # Category exists but may have been pre-existing
            score += scoring.get('category_created', 30) // 2  # Partial credit
            feedback_parts.append(f"⚠️ Category found but may not be newly created (ID: {cat_id})")
        else:
            feedback_parts.append("❌ Category not properly created")
    else:
        feedback_parts.append("❌ No Telehealth category found in database")
        # Cannot proceed without category
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 2: Category name contains "Telehealth" (25 points)
    cat_name = category.get('name', '')
    if cat_name and 'telehealth' in cat_name.lower():
        score += scoring.get('correct_name', 25)
        subscores["correct_name"] = True
        feedback_parts.append(f"✅ Category name correct: '{cat_name}'")
    elif cat_name and ('tele' in cat_name.lower() or 'video' in cat_name.lower()):
        # Partial credit for related names
        score += scoring.get('correct_name', 25) // 2
        feedback_parts.append(f"⚠️ Category name partially matches: '{cat_name}'")
    else:
        feedback_parts.append(f"❌ Category name does not contain 'Telehealth': '{cat_name}'")
    
    # CRITERION 3: Duration is approximately 20 minutes (20 points)
    duration_minutes = category.get('duration_minutes', 0)
    duration_seconds = category.get('duration_seconds', 0)
    
    # Handle case where duration_minutes wasn't calculated
    if not duration_minutes and duration_seconds:
        duration_minutes = duration_seconds // 60
    
    min_duration = expected_duration - duration_tolerance
    max_duration = expected_duration + duration_tolerance
    
    if duration_minutes and min_duration <= duration_minutes <= max_duration:
        score += scoring.get('correct_duration', 20)
        subscores["correct_duration"] = True
        feedback_parts.append(f"✅ Duration correct: {duration_minutes} minutes")
    elif duration_minutes > 0:
        # Partial credit for having a duration set
        score += scoring.get('correct_duration', 20) // 2
        feedback_parts.append(f"⚠️ Duration set but not ideal: {duration_minutes} minutes (expected ~{expected_duration})")
    else:
        feedback_parts.append(f"❌ Duration not properly set: {duration_minutes} minutes")
    
    # CRITERION 4: Color is assigned (10 points)
    cat_color = category.get('color', '')
    if cat_color and cat_color.strip() and cat_color.lower() not in ['null', 'none', '']:
        score += scoring.get('color_assigned', 10)
        subscores["color_assigned"] = True
        feedback_parts.append(f"✅ Color assigned: {cat_color}")
    else:
        feedback_parts.append("❌ No color assigned to category")
    
    # CRITERION 5: Description is present (10 points)
    cat_desc = category.get('description', '')
    if cat_desc and cat_desc.strip() and cat_desc.lower() not in ['null', 'none', '']:
        score += scoring.get('description_present', 10)
        subscores["description_present"] = True
        feedback_parts.append(f"✅ Description present: '{cat_desc[:50]}...' " if len(cat_desc) > 50 else f"✅ Description present: '{cat_desc}'")
    else:
        feedback_parts.append("❌ No description provided for category")
    
    # CRITERION 6: Category is active (5 points)
    cat_active = category.get('active', '1')
    if cat_active in ['1', 1, True, 'true', '']:
        score += scoring.get('category_active', 5)
        subscores["category_active"] = True
        feedback_parts.append("✅ Category is active")
    else:
        feedback_parts.append("❌ Category is not active")
    
    # Determine pass/fail
    # Must have category_created AND correct_name to pass
    required_met = subscores["category_created"] and subscores["correct_name"]
    passed = score >= pass_threshold and required_met
    
    # Add summary
    feedback_parts.insert(0, f"Score: {score}/100 (threshold: {pass_threshold})")
    
    if passed:
        feedback_parts.append("🎉 TASK PASSED: Telehealth Visit category successfully created!")
    elif not required_met:
        feedback_parts.append(f"❌ TASK FAILED: Required criteria not met (need category_created AND correct_name)")
    else:
        feedback_parts.append(f"❌ TASK FAILED: Score {score} below threshold {pass_threshold}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "category_name": cat_name,
            "duration_minutes": duration_minutes,
            "color": cat_color,
            "baseline_id": baseline_max_id,
            "category_id": category.get('id', ''),
            "new_categories_added": current_count - baseline_count
        }
    }


# Additional verification using VLM for trajectory analysis (optional enhancement)
def verify_with_vlm(traj, env_info, task_info):
    """
    Optional VLM-based verification to supplement database verification.
    Checks trajectory frames to verify the agent navigated to correct screens.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("VLM utilities not available, skipping trajectory verification")
        return None
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    
    # Sample frames from trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    
    if not frames and not final:
        return None
    
    # VLM prompt to verify workflow
    prompt = """Analyze these screenshots from an OpenEMR task.
    
TASK: Create a new appointment category called "Telehealth Visit" with 20 minute duration.

Look at the workflow progression and determine:
1. Did the agent navigate to Administration/Calendar settings?
2. Did the agent access a category creation form?
3. Is there evidence of filling in category name "Telehealth"?
4. Is there evidence of setting a duration?
5. Was a save/submit action performed?

Respond in JSON format:
{
    "navigated_to_admin": true/false,
    "accessed_category_form": true/false,
    "entered_telehealth_name": true/false,
    "set_duration": true/false,
    "saved_category": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
    
    all_frames = frames + ([final] if final else [])
    
    try:
        result = query_vlm(
            prompt=prompt,
            images=all_frames
        )
        return result
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return None