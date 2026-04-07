#!/usr/bin/env python3
"""
Verifier for Social Media Content Repurposing Pipeline.
Scores files based on metadata gathered by export_result.sh in the container.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_social_media_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files = data.get('files', {})
    manifest = data.get('manifest_data')
    
    score = 0
    max_score = 34
    feedback_parts = []
    
    all_files_created_during_task = True
    any_file_created = False

    # 1. Evaluate Landscape Highlights (8 points)
    # highlight_A.mp4 through highlight_D.mp4
    for h in ['highlight_A.mp4', 'highlight_B.mp4', 'highlight_C.mp4', 'highlight_D.mp4']:
        f_info = files.get(h)
        if f_info and f_info.get('exists'):
            any_file_created = True
            if not f_info.get('created_during_task'):
                all_files_created_during_task = False
            
            # Check duration (~10s) and dimensions (1920x1080)
            dur = f_info.get('duration', 0)
            w, h_dim = f_info.get('width', 0), f_info.get('height', 0)
            
            if 8 <= dur <= 12 and w >= h_dim and f_info.get('has_video'):
                score += 2
                feedback_parts.append(f"+ {h}: Correct duration & format.")
            elif f_info.get('size_bytes', 0) > 10000:
                score += 1
                feedback_parts.append(f"~ {h}: Exists but format/duration off ({dur}s, {w}x{h_dim}).")
        else:
            feedback_parts.append(f"- {h} missing.")
            all_files_created_during_task = False

    # 2. Evaluate Vertical Crops (8 points)
    for v in ['vertical_A.mp4', 'vertical_B.mp4', 'vertical_C.mp4', 'vertical_D.mp4']:
        f_info = files.get(v)
        if f_info and f_info.get('exists'):
            any_file_created = True
            if not f_info.get('created_during_task'):
                all_files_created_during_task = False
                
            dur = f_info.get('duration', 0)
            w, h_dim = f_info.get('width', 0), f_info.get('height', 0)
            
            # Portrait check: width < height
            if 8 <= dur <= 12 and w < h_dim and f_info.get('has_video'):
                score += 2
                feedback_parts.append(f"+ {v}: Valid portrait crop ({w}x{h_dim}).")
            elif f_info.get('size_bytes', 0) > 10000:
                score += 1
                feedback_parts.append(f"~ {v}: Exists but format/crop invalid ({w}x{h_dim}).")
        else:
            feedback_parts.append(f"- {v} missing.")
            all_files_created_during_task = False

    # 3. Evaluate Compilation Reel (4 points)
    comp_info = files.get('compilation.mp4')
    if comp_info and comp_info.get('exists'):
        any_file_created = True
        if not comp_info.get('created_during_task'):
            all_files_created_during_task = False
            
        score += 1 # Exists
        dur = comp_info.get('duration', 0)
        if 35 <= dur <= 45:
            score += 2
            feedback_parts.append(f"+ Compilation: Correct duration ({dur}s).")
        else:
            feedback_parts.append(f"~ Compilation: Incorrect duration ({dur}s, expected ~40s).")
            
        if comp_info.get('has_video'):
            score += 1
    else:
        feedback_parts.append("- Compilation missing.")
        all_files_created_during_task = False

    # 4. Evaluate Audio Extraction (3 points)
    audio_info = files.get('compilation_audio.mp3')
    if audio_info and audio_info.get('exists'):
        any_file_created = True
        if not audio_info.get('created_during_task'):
            all_files_created_during_task = False
            
        score += 1 # Exists
        if 35 <= audio_info.get('duration', 0) <= 45:
            score += 1
        if audio_info.get('has_audio') and not audio_info.get('has_video'):
            score += 1
            feedback_parts.append("+ Audio extracted successfully (no video track).")
        else:
            feedback_parts.append("~ Audio file invalid or contains video.")
    else:
        feedback_parts.append("- Audio extraction missing.")
        all_files_created_during_task = False

    # 5. Evaluate Thumbnails (4 points)
    for t in ['thumb_A.png', 'thumb_B.png', 'thumb_C.png', 'thumb_D.png']:
        f_info = files.get(t)
        if f_info and f_info.get('exists') and f_info.get('size_bytes', 0) > 5000:
            any_file_created = True
            if not f_info.get('created_during_task'):
                all_files_created_during_task = False
            score += 1
        else:
            feedback_parts.append(f"- {t} missing or empty.")
            all_files_created_during_task = False

    # 6. Evaluate JSON Manifest (4 points)
    if isinstance(manifest, dict) and not manifest.get('error'):
        score += 1
        dels = manifest.get('deliverables', {})
        if isinstance(dels, dict):
            # Check highlights
            if 'highlights' in dels and len(dels['highlights']) == 4:
                score += 1
            # Check verticals
            if 'verticals' in dels and len(dels['verticals']) == 4:
                score += 1
            # Check compilation & audio
            if 'compilation' in dels and 'audio' in dels:
                score += 1
        feedback_parts.append("+ Manifest parsed successfully.")
    else:
        feedback_parts.append("- Manifest missing or invalid JSON.")

    # 7. Anti-Gaming Check (3 points)
    if any_file_created and all_files_created_during_task:
        score += 3
        feedback_parts.append("+ All files created during task (passed anti-gaming).")
    elif any_file_created:
        feedback_parts.append("! WARNING: Some files existed before task started.")

    # Calculate final status
    passed = score >= 19 and any_file_created # 19 points is ~55% of 34
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }