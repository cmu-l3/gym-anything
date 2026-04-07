#!/usr/bin/env python3
import os
import json
import tempfile

def verify_create_git_voice_system(traj, env_info, task_info):
    """
    Verify the creation of a dynamic Talon module for Git branch switching.
    Uses multi-criteria verification including timestamp anti-gaming checks,
    content evaluation, and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Directory and files setup (10 points)
    if result.get('dir_exists') and result.get('git_py_exists') and result.get('git_talon_exists'):
        score += 10
        feedback.append("Directory and files created (+10)")
    else:
        feedback.append("Directory or required files missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Anti-gaming: Check timestamps
    task_start = int(result.get('task_start', 0))
    py_mtime = int(result.get('git_py_mtime', 0))
    talon_mtime = int(result.get('git_talon_mtime', 0))
    
    if py_mtime < task_start or talon_mtime < task_start:
        feedback.append("Files were created before task started (gaming detected)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    git_py_content = result.get('git_py_content', '')
    git_talon_content = result.get('git_talon_content', '')

    # 2. List Declaration (15 points)
    if 'Module' in git_py_content and 'git_branch' in git_py_content:
        score += 15
        feedback.append("Talon API elements declared (+15)")
    else:
        feedback.append("Missing Module or git_branch list declarations in git.py")

    # 3. Subprocess Logic (15 points)
    if 'subprocess' in git_py_content and 'git branch' in git_py_content and 'test_repo' in git_py_content:
        score += 15
        feedback.append("Subprocess logic implemented (+15)")
    else:
        feedback.append("Missing subprocess, 'git branch', or 'test_repo' path in git.py")

    # 4. Spoken Form Parsing (15 points)
    if ('replace' in git_py_content or 're.sub' in git_py_content) and ('/' in git_py_content or '-' in git_py_content):
        score += 15
        feedback.append("Spoken form parsing logic found (+15)")
    else:
        feedback.append("Missing character replacement for spoken forms in git.py")

    # 5. Talon Commands (15 points)
    if 'git status' in git_talon_content and 'git add' in git_talon_content and 'git commit' in git_talon_content:
        score += 15
        feedback.append("Static Git commands mapped (+15)")
    else:
        feedback.append("Missing some static Git commands in git.talon")

    # 6. Dynamic Checkout (10 points)
    if 'git checkout' in git_talon_content and 'git_branch' in git_talon_content:
        score += 10
        feedback.append("Dynamic branch checkout mapped (+10)")
    else:
        feedback.append("Missing dynamic checkout mapping in git.talon")

    # 7. VLM Trajectory Verification (20 points)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = 'Look at these screenshots from a computer session. Determine if the agent was actively writing or viewing code in a text editor (like Notepad, VS Code, etc.) or terminal. Respond with a JSON object containing a boolean "editor_used". Example: {"editor_used": true}'
                vlm_result = query_vlm(images=images, prompt=prompt)
                
                if vlm_result.get('success') and vlm_result.get('parsed', {}).get('editor_used', False):
                    vlm_score = 20
                    feedback.append("VLM confirmed text editor usage (+20)")
                else:
                    feedback.append("VLM could not confirm editor usage")
    except Exception as e:
        feedback.append(f"VLM error: {e}")
    
    score += vlm_score

    # Check for syntax errors in talon.log
    talon_log = result.get('talon_log', '')
    if 'SyntaxError' in talon_log and 'git.py' in talon_log:
        feedback.append("Warning: SyntaxError found in talon.log for git.py")
        score -= 10
    
    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}