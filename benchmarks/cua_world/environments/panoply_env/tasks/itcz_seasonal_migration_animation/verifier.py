#!/usr/bin/env python3
"""
Verifier for itcz_seasonal_migration_animation task.

Occupation: Earth Science Curriculum Developer
Industry: Education / Museum Exhibits
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 70):
  1. Animation file exists (20 pts): itcz_animation.* exists, size >= 100KB.
  2. Frame count verified (30 pts): Programmatic inspection proves the file has 12 frames.
     (Partial credit given if > 1 frame but != 12, or if file size suggests an animation
     but python library parsing failed).
  3. Lesson plan report complete (20 pts): lesson_plan.txt exists and contains required fields.
  4. Correct Northern Peak (15 pts): NORTHERN_PEAK_MONTH identifies July or August.
  5. Correct Southern Peak (15 pts): SOUTHERN_PEAK_MONTH identifies January or February.
"""

import json
import os
import tempfile
import re

def verify_itcz_animation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/itcz_seasonal_migration_animation_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))
    metadata = task_info.get('metadata', {})
    
    valid_north = metadata.get('correct_northern_peak', ["july", "august", "jul", "aug"])
    valid_south = metadata.get('correct_southern_peak', ["january", "february", "jan", "feb"])

    # ----------------------------------------------------------------
    # Criterion 1: Animation File Exists & Reasonable Size (20 pts)
    # ----------------------------------------------------------------
    anim_exists = result.get('animation_exists', False)
    anim_mtime = int(result.get('animation_mtime', 0))
    anim_size = int(result.get('animation_size', 0))
    anim_fmt = result.get('animation_format', 'none')

    if anim_exists and anim_mtime >= task_start and anim_size >= 100000:
        score += 20
        feedback.append(f"Animation exported: itcz_animation.{anim_fmt} ({anim_size/1024:.1f} KB)")
    elif anim_exists and anim_mtime >= task_start and anim_size >= 20000:
        score += 10
        feedback.append(f"Animation exported but suspiciously small ({anim_size/1024:.1f} KB)")
    else:
        feedback.append(f"Animation missing or not created during task "
                        f"(exists={anim_exists}, size={anim_size}, mtime={anim_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: Animation Frame Count (30 pts)
    # ----------------------------------------------------------------
    anim_frames = int(result.get('animation_frames', 0))
    
    if anim_frames == 12:
        score += 30
        feedback.append(f"Verified exactly 12 frames in the exported animation.")
    elif anim_frames > 1:
        score += 15
        feedback.append(f"Animation has {anim_frames} frames (expected 12).")
    elif anim_frames == 0 and anim_size >= 100000:
        # Fallback if cv2/PIL failed but file is large
        score += 15
        feedback.append("Could not programmatically extract frame count, but file size suggests valid animation.")
    else:
        feedback.append(f"File does not appear to be a multi-frame animation (frames={anim_frames}).")

    # ----------------------------------------------------------------
    # Criterion 3: Lesson Plan Completeness (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    audience = result.get('target_audience', '').strip()
    northern_val = result.get('northern_peak', '').strip()
    southern_val = result.get('southern_peak', '').strip()
    reported_frames = result.get('animation_frames_report', '').strip()

    has_required = bool(audience) and bool(northern_val) and bool(southern_val)

    if report_exists and report_mtime >= task_start and has_required:
        score += 20
        feedback.append("Lesson plan report is complete.")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Lesson plan exists but is missing required fields.")
    else:
        feedback.append("Lesson plan missing or not created during task.")

    # ----------------------------------------------------------------
    # Criterion 4: Correct Northern Peak (15 pts)
    # ----------------------------------------------------------------
    north_lower = northern_val.lower()
    if any(re.search(r'\b' + month + r'\b', north_lower) for month in valid_north):
        score += 15
        feedback.append(f"Correct northern peak identified: {northern_val}")
    elif northern_val:
        feedback.append(f"Incorrect northern peak identified: {northern_val} (Expected July or August)")

    # ----------------------------------------------------------------
    # Criterion 5: Correct Southern Peak (15 pts)
    # ----------------------------------------------------------------
    south_lower = southern_val.lower()
    if any(re.search(r'\b' + month + r'\b', south_lower) for month in valid_south):
        score += 15
        feedback.append(f"Correct southern peak identified: {southern_val}")
    elif southern_val:
        feedback.append(f"Incorrect southern peak identified: {southern_val} (Expected January or February)")

    # ----------------------------------------------------------------
    # Final Score Calculation
    # ----------------------------------------------------------------
    passed = score >= 70 and anim_exists and anim_size >= 20000

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }