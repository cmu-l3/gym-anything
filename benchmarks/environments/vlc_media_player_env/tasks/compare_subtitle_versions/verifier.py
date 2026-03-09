#!/usr/bin/env python3
"""
Verifier for Compare Subtitle Versions task.
Checks if the agent correctly identified and selected the best subtitle file.
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compare_subtitle_versions(traj, env_info, task_info):
    """
    Verify that agent selected the correct subtitle file (v2).
    
    Verification steps:
    1. Check if selected_subtitle.srt was exported
    2. Compare content with the correct subtitle file (v2)
    3. Verify it's not v1 or v3
    4. Award partial credit for attempting the task
    
    Args:
        traj: Trajectory data
        env_info: Environment information
        task_info: Task information
        
    Returns:
        dict with passed, score, and feedback
    """
    logger.info("Starting subtitle comparison verification")
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy selected subtitle file
    temp_selected = tempfile.NamedTemporaryFile(delete=False, suffix='.srt')
    
    try:
        copy_from_env("/tmp/vlc_selected_subtitle.srt", temp_selected.name)
    except Exception as e:
        logger.error(f"Error copying selected subtitle: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ FAILED: No subtitle file was selected | Expected at /home/ga/Videos/selected_subtitle.srt"
        }
    
    # Check if file is empty
    file_size = os.path.getsize(temp_selected.name)
    if file_size == 0:
        os.unlink(temp_selected.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ FAILED: Selected subtitle file is empty | You must copy one of the subtitle files"
        }
    
    criteria_met += 1
    feedback_parts.append(f"✅ Subtitle selected ({file_size} bytes)")
    
    # Read selected subtitle content
    try:
        with open(temp_selected.name, 'r', encoding='utf-8', errors='ignore') as f:
            selected_content = f.read()
    except Exception as e:
        os.unlink(temp_selected.name)
        return {"passed": False, "score": 0, "feedback": f"ERROR: Could not read selected subtitle: {e}"}
    
    os.unlink(temp_selected.name)
    
    # Copy the three original subtitle files for comparison
    temp_dir = tempfile.mkdtemp(prefix='vlc_subtitle_verify_')
    
    try:
        # Copy v1, v2, v3 from container
        v1_path = os.path.join(temp_dir, 'v1.srt')
        v2_path = os.path.join(temp_dir, 'v2.srt')
        v3_path = os.path.join(temp_dir, 'v3.srt')
        
        copy_from_env("/home/ga/Videos/subtitles/das_leben_subtitles_v1.srt", v1_path)
        copy_from_env("/home/ga/Videos/subtitles/das_leben_subtitles_v2.srt", v2_path)
        copy_from_env("/home/ga/Videos/subtitles/das_leben_subtitles_v3.srt", v3_path)
        
        with open(v1_path, 'r', encoding='utf-8', errors='ignore') as f:
            v1_content = f.read()
        with open(v2_path, 'r', encoding='utf-8', errors='ignore') as f:
            v2_content = f.read()
        with open(v3_path, 'r', encoding='utf-8', errors='ignore') as f:
            v3_content = f.read()
        
    except Exception as e:
        logger.error(f"Error copying original subtitles: {e}")
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {"passed": False, "score": 33, "feedback": f"ERROR: Could not verify subtitle versions: {e}"}
    
    # Clean up temp dir
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)
    
    # Determine which version was selected (normalize whitespace for comparison)
    def normalize(text):
        return ' '.join(text.split())
    
    selected_norm = normalize(selected_content)
    v1_norm = normalize(v1_content)
    v2_norm = normalize(v2_content)
    v3_norm = normalize(v3_content)
    
    selected_version = None
    if selected_norm == v1_norm:
        selected_version = "v1"
    elif selected_norm == v2_norm:
        selected_version = "v2"
    elif selected_norm == v3_norm:
        selected_version = "v3"
    else:
        feedback_parts.append("⚠️ Selected file modified or doesn't match any version")
        return {
            "passed": False, 
            "score": 20, 
            "feedback": " | ".join(feedback_parts) + " | ❌ Content doesn't match v1/v2/v3"
        }
    
    criteria_met += 1
    feedback_parts.append(f"Version identified: {selected_version}")
    
    # Check if correct version was selected
    correct_version = "v2"
    
    if selected_version == correct_version:
        criteria_met += 1
        feedback_parts.append("✅ CORRECT choice (v2 - professional DVD subtitle)")
        
        feedback = " | ".join(feedback_parts) + " | Perfect timing at 5:20, professional translation"
        
        return {
            "passed": True,
            "score": 100,
            "feedback": feedback
        }
    else:
        # Wrong version selected - provide detailed feedback
        if selected_version == "v1":
            issue = "v1 is auto-translated with poor grammar and +2s timing offset"
        elif selected_version == "v3":
            issue = "v3 has -1s timing offset (appears too early)"
        else:
            issue = "unknown issue"
        
        feedback = " | ".join(feedback_parts) + f" | ❌ INCORRECT: {issue} | v2 has perfect timing and professional quality"
        
        # Award partial credit for attempting the task
        return {
            "passed": False,
            "score": 40,
            "feedback": feedback
        }
