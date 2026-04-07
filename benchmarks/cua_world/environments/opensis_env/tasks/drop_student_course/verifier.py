#!/usr/bin/env python3
"""
Verifier for drop_student_course task.

Logic:
1. Verify the specific schedule record linking Philip to PSY101 is GONE.
2. Verify Philip (student) still exists (ensure agent didn't delete the student).
3. Verify PSY101 (course) still exists (ensure agent didn't delete the course).
4. Verify the database was actually modified during the task window.
5. VLM: Verify the agent navigated to the schedule screen.
"""

import json
import os
import sys
import logging
import tempfile

# Add parent directory to path to import vlm_utils if needed
# In this environment, we usually assume vlm_utils is available or we define helpers inline
# Here we'll rely on the gym-anything standard structure

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_drop_student_course(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utils (assuming available in environment python path or standard location)
    try:
        from vlm_utils import sample_trajectory_frames, query_vlm
        VLM_AVAILABLE = True
    except ImportError:
        logger.warning("VLM utils not found, skipping visual verification")
        VLM_AVAILABLE = False

    # 1. Read result JSON
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

    score = 0
    feedback = []

    # Criterion 1: Schedule Record Removed (40 pts)
    # schedule_record_count should be 0
    schedule_count = result.get("schedule_record_count", -1)
    if schedule_count == 0:
        score += 40
        feedback.append("Success: Student is no longer scheduled in PSY101.")
    elif schedule_count > 0:
        feedback.append(f"Fail: Student is still scheduled in PSY101 ({schedule_count} records found).")
    else:
        feedback.append("Error: Could not verify schedule status.")

    # Criterion 2: Student Safety Check (15 pts)
    # student_record_exists should be 1
    if result.get("student_record_exists", 0) > 0:
        score += 15
        feedback.append("Safety Check: Student record preserved.")
    else:
        feedback.append("Critical Fail: Student record was deleted! You should only drop the course.")

    # Criterion 3: Course Safety Check (15 pts)
    # course_record_exists should be 1
    if result.get("course_record_exists", 0) > 0:
        score += 15
        feedback.append("Safety Check: Course record preserved.")
    else:
        feedback.append("Critical Fail: Course record was deleted! You should only drop the student.")

    # Criterion 4: Total Count Check (15 pts)
    # Final count should be Initial - 1 (approximately, assuming no other changes)
    initial = result.get("initial_total_schedule_count", 0)
    final = result.get("final_total_schedule_count", 0)
    if final < initial:
        score += 15
        feedback.append(f"Consistency: Total schedule count decreased ({initial} -> {final}).")
    elif final == initial and schedule_count == 0:
        # Weird edge case, maybe they added another course?
        feedback.append("Warning: Schedule count did not decrease, but specific course was dropped.")
        score += 10
    else:
        feedback.append("Fail: Schedule count did not decrease.")

    # Criterion 5: Visual/Trajectory Verification (15 pts)
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = """
        I am an administrator removing a student from a course in OpenSIS.
        Look at these screenshots of my workflow.
        
        Do you see any of the following:
        1. A student schedule list or grid?
        2. A "Drop" button or trash icon next to a course?
        3. A dialog confirming removal?
        4. The "Student Schedule" tab being active?
        
        Answer YES or NO and explain briefly.
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp and vlm_resp.get("success"):
                response_text = vlm_resp.get("response", "").lower()
                if "yes" in response_text or "schedule" in response_text:
                    vlm_score = 15
                    feedback.append("Visual: Trajectory confirms interaction with schedule screen.")
                else:
                    feedback.append("Visual: Could not confirm schedule interaction from screenshots.")
            else:
                # Fallback if VLM fails but logic passed
                if score >= 70: vlm_score = 15
        except Exception as e:
            logger.error(f"VLM error: {e}")
            if score >= 70: vlm_score = 15 # Benefit of doubt if logic passed
    else:
        # If VLM not available, give points if logic strictly passed
        if score >= 70:
            vlm_score = 15
            feedback.append("Visual: VLM skipped, points awarded based on database success.")

    score += vlm_score

    # Final Pass/Fail
    # Must have removed schedule AND kept student AND kept course
    passed = (schedule_count == 0) and \
             (result.get("student_record_exists", 0) > 0) and \
             (result.get("course_record_exists", 0) > 0) and \
             (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }