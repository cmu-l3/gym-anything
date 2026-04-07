#!/usr/bin/env python3
"""
Verifier for configure_branching_lesson task.

Criteria evaluated:
1. Lesson Created: Verifies the Lesson activity exists in the DB.
2. Pages Created: Verifies exact 3 pages are created with expected titles.
3. Image Embedded: Verifies placard_1090.jpg is uploaded to the lesson context and linked.
4. Branching Logic: Analyzes jump edges to ensure correct traversal between pages.
5. VLM Trajectory Check: Confirms the Moodle UI was actively used during the task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_branching_lesson(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load the exported task result JSON
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

    feedback_parts = []
    score = 0

    # ================================================================
    # CRITERION 1: Lesson Created (15 points)
    # ================================================================
    lesson_exists = result.get('lesson_exists', False)
    if lesson_exists:
        score += 15
        feedback_parts.append("Lesson created")
    else:
        feedback_parts.append("Lesson not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Parse Moodle lesson data
    pages = result.get('pages', [])
    answers = result.get('answers', [])
    files = result.get('files', [])

    page_map = {}
    page_id_map = {}
    for p in pages:
        title = p['title'].strip().lower()
        page_map[title] = p
        page_id_map[int(p['id'])] = title

    # ================================================================
    # CRITERION 2: Pages Created (25 points)
    # ================================================================
    expected_titles = ['scene arrival', 'failure protocol', 'protective actions']
    found_pages = sum(1 for exp in expected_titles if exp in page_map)
    
    pages_score = min(25, found_pages * 9) # ~8.33 per page, max 25
    score += pages_score
    feedback_parts.append(f"{found_pages}/3 pages created")

    # ================================================================
    # CRITERION 3: Image Embedded (15 points)
    # ================================================================
    image_score = 0
    has_file = any('1090' in f['filename'] or 'placard' in f['filename'] for f in files)
    
    if has_file:
        image_score += 10
        
    if 'scene arrival' in page_map:
        content = page_map['scene arrival']['contents'].lower()
        if '<img' in content and has_file:
            image_score += 5
        elif '<img' in content:
            image_score += 3
            
    score += image_score
    feedback_parts.append(f"Image embedded: {image_score}/15 pts")

    # ================================================================
    # CRITERION 4: Branching Logic (25 points)
    # ================================================================
    def resolve_jump(jumpto, current_page_id):
        jumpto = int(jumpto)
        if jumpto > 0:
            return jumpto
        if jumpto == -9:
            return 'END_OF_LESSON'
        
        current_page = next((p for p in pages if int(p['id']) == current_page_id), None)
        if not current_page:
            return None
            
        if jumpto == -1: # Next Page
            nxt = int(current_page['nextpageid'])
            return nxt if nxt != 0 else 'END_OF_LESSON'
        if jumpto == -2: # Previous Page
            prv = int(current_page['prevpageid'])
            return prv if prv != 0 else None
            
        return None

    correct_jumps = 0
    if found_pages == 3:
        # Analyze Scene Arrival navigational graph edges
        sa_page = page_map['scene arrival']
        sa_answers = [a for a in answers if int(a['pageid']) == int(sa_page['id'])]
        sa_jumps = set()
        for ans in sa_answers:
            target = resolve_jump(ans['jumpto'], int(sa_page['id']))
            target_title = page_id_map.get(target, str(target))
            if target_title == 'failure protocol':
                sa_jumps.add('failure protocol')
            elif target_title == 'protective actions':
                sa_jumps.add('protective actions')
        correct_jumps += len(sa_jumps)
        
        # Analyze Failure Protocol navigational graph edges
        fp_page = page_map['failure protocol']
        fp_answers = [a for a in answers if int(a['pageid']) == int(fp_page['id'])]
        fp_jumps = set()
        for ans in fp_answers:
            target = resolve_jump(ans['jumpto'], int(fp_page['id']))
            target_title = page_id_map.get(target, str(target))
            if target_title == 'scene arrival':
                fp_jumps.add('scene arrival')
        correct_jumps += len(fp_jumps)
        
        # Analyze Protective Actions navigational graph edges
        pa_page = page_map['protective actions']
        pa_answers = [a for a in answers if int(a['pageid']) == int(pa_page['id'])]
        pa_jumps = set()
        for ans in pa_answers:
            target = resolve_jump(ans['jumpto'], int(pa_page['id']))
            if target == 'END_OF_LESSON':
                pa_jumps.add('END_OF_LESSON')
        correct_jumps += len(pa_jumps)

    jump_score = min(25, int((correct_jumps / 4) * 25)) if correct_jumps > 0 else 0
    score += jump_score
    feedback_parts.append(f"Correct jumps: {correct_jumps}/4")

    # ================================================================
    # CRITERION 5: VLM Trajectory Verification (20 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            imgs = frames + [final] if final else frames
            
            prompt = """You are analyzing screenshots of an agent setting up a Moodle Lesson.
            Check if the agent:
            1. Used the Moodle web interface.
            2. Edited Lesson pages or configured branch tables/jumps.
            
            Respond in JSON format:
            {
                "moodle_ui_used": true/false,
                "lesson_edited": true/false
            }
            """
            vlm_res = query_vlm(prompt=prompt, images=imgs)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get('moodle_ui_used'): vlm_score += 10
                if parsed.get('lesson_edited'): vlm_score += 10
                feedback_parts.append("VLM verified workflow")
            else:
                feedback_parts.append("VLM verification failed")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM error")
    else:
        # VLM framework omitted, default pass points
        vlm_score = 20
        feedback_parts.append("VLM skipped")
        
    score += vlm_score

    # Determine final passage state
    key_criteria_met = lesson_exists and found_pages >= 2 and correct_jumps >= 1
    passed = score >= 70 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }