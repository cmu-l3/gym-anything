#!/usr/bin/env python3
"""
Verifier for algorithm_pattern task.

Criteria:
1. Files exist: level1.png, level2.png, level3.png (15 pts each)
2. Timestamps are valid (created during task) and sequential (10 pts)
3. VLM verifies screenshots show completed patterns (15 pts each)
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, though we use gym_anything.vlm usually
# Assuming standard environment where gym_anything is available or we use the provided structure
try:
    from gym_anything.vlm import query_vlm
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": True, "parsed": {"is_valid": True}}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_algorithm_pattern(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check Files & Timestamps
    levels = ['level1', 'level2', 'level3']
    files_valid = {}
    
    for lvl in levels:
        data = result.get(lvl, {})
        exists = data.get('exists', False)
        size = data.get('size', 0)
        created_during = data.get('created_during_task', False)
        
        if exists and size > 50000 and created_during:
            score += 5 # Base points for valid file existence
            files_valid[lvl] = True
            feedback.append(f"{lvl}: File exists and valid.")
        else:
            files_valid[lvl] = False
            feedback.append(f"{lvl}: Missing or invalid (Size: {size}, Created during task: {created_during})")

    # 3. Check Sequential Timestamps (Anti-gaming)
    if all(files_valid.values()):
        t1 = result['level1']['mtime']
        t2 = result['level2']['mtime']
        t3 = result['level3']['mtime']
        
        if t1 < t2 < t3:
            score += 10
            feedback.append("Timestamps are sequential (Good).")
        else:
            feedback.append(f"Timestamps not sequential ({t1}, {t2}, {t3}).")

    # 4. VLM Content Verification
    # We need to pull the screenshots from the env to verify their content
    
    vlm_prompt = """
    Analyze this screenshot from the educational software GCompris.
    1. Is the "Algorithm" / Pattern completion activity visible? (Look for a sequence of objects/shapes)
    2. Is the pattern completed? (No empty slots, usually a success indicator like a star, OK button, or animation)
    3. Does it look like a valid attempt at the task?
    
    Return JSON:
    {
        "is_algorithm_activity": true/false,
        "is_completed": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    for i, lvl in enumerate(levels):
        if not files_valid[lvl]:
            continue
            
        remote_path = f"/home/ga/algorithm_{lvl}.png"
        local_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(remote_path, local_img.name)
            
            # Query VLM
            vlm_res = query_vlm(prompt=vlm_prompt, image=local_img.name)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_algorithm_activity") and parsed.get("is_completed"):
                    score += 25 # High value for visual proof
                    feedback.append(f"{lvl}: Visual verification passed.")
                else:
                    feedback.append(f"{lvl}: Visual verification failed (Activity: {parsed.get('is_algorithm_activity')}, Completed: {parsed.get('is_completed')})")
            else:
                feedback.append(f"{lvl}: VLM query failed, cannot verify content.")
                
        except Exception as e:
            feedback.append(f"{lvl}: Failed to retrieve image for VLM check: {e}")
        finally:
            if os.path.exists(local_img.name):
                os.unlink(local_img.name)

    # 5. Final check
    # Max score calculation:
    # 3 files * 5 pts (existence) = 15
    # Sequential = 10
    # 3 files * 25 pts (VLM) = 75
    # Total = 100
    
    passed = score >= 60 # Pass if at least 2 levels are fully correct (2*30 = 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }