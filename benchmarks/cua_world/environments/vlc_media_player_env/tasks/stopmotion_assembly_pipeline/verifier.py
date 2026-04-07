#!/usr/bin/env python3
"""
Verifier for stopmotion_assembly_pipeline task.
Validates exact specifications of multiple media deliverables.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stopmotion_assembly_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 59
    feedback_parts = []

    # Read media stats
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            media = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    start_time = media.get("start_time", 0)

    # 1. Master Video (Max 12 pts)
    master = media.get("master", {})
    if master.get("exists"):
        score += 2
        
        if master.get("width") == 1280 and master.get("height") == 720:
            score += 2
            
        dur = master.get("duration", 0)
        if 9.0 <= dur <= 11.0:
            score += 3
            
        if master.get("codec") == "h264":
            score += 2
            
        if master.get("audio_streams", 0) > 0:
            score += 3
            feedback_parts.append("Master: Correct")
        else:
            feedback_parts.append("Master: Missing Audio")
    else:
        feedback_parts.append("Master: Not Found")

    # 2. Cinematic Video (Max 9 pts)
    cinematic = media.get("cinematic", {})
    if cinematic.get("exists") and cinematic.get("codec") == "h264":
        score += 2
        
        dur = cinematic.get("duration", 0)
        if 4.5 <= dur <= 5.5:
            score += 3
            
        if cinematic.get("width") == 1280 and cinematic.get("height") == 720:
            score += 2
            
        if cinematic.get("audio_streams", 0) == 0:
            score += 2
            feedback_parts.append("Cinematic: Correct")
        else:
            feedback_parts.append("Cinematic: Has Audio (Should be silent)")
    else:
        feedback_parts.append("Cinematic: Not Found/Invalid")

    # 3. Web Preview (Max 11 pts)
    web = media.get("web", {})
    if web.get("exists"):
        score += 2
        
        if web.get("width") == 640 and web.get("height") == 360:
            score += 3
            
        dur = web.get("duration", 0)
        if 9.0 <= dur <= 11.0:
            score += 2
            
        if web.get("audio_streams", 0) > 0:
            score += 2
            
        master_size = master.get("size", float('inf'))
        if web.get("size", 0) < master_size:
            score += 2
            feedback_parts.append("Web: Correct")
        else:
            feedback_parts.append("Web: Not smaller than master")
    else:
        feedback_parts.append("Web: Not Found")

    # 4. Animated Preview (Max 7 pts)
    preview = media.get("preview", {})
    if preview.get("exists"):
        score += 2
        
        dur = preview.get("duration", 0)
        if 5.0 <= dur <= 7.0:
            score += 3
            
        if preview.get("width") == 640 and preview.get("height") == 360:
            score += 2
            feedback_parts.append("Preview: Correct")
    else:
        feedback_parts.append("Preview: Not Found")

    # 5. Proof Sheet (Max 9 pts)
    proof = media.get("proof_sheet", {})
    if proof.get("exists"):
        score += 2
        
        w, h = proof.get("width", 0), proof.get("height", 0)
        if w >= 1200 and h >= 800:
            score += 3
            
        if proof.get("size", 0) >= 100 * 1024:  # >= 100KB ensures it's not a solid blank image
            score += 4  # Includes visual variety points
            feedback_parts.append("Proof Sheet: Correct")
        else:
            feedback_parts.append("Proof Sheet: Too small (empty?)")
    else:
        feedback_parts.append("Proof Sheet: Not Found")

    # 6. Assembly Manifest (Max 7 pts)
    temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/assembly_manifest.json", temp_manifest.name)
        with open(temp_manifest.name, 'r') as f:
            manifest = json.load(f)
            
        score += 2  # Valid JSON
        
        if manifest.get("project_name") == "StopMotion Commercial" and manifest.get("total_frames") == 120:
            score += 2
            
        deliverables = manifest.get("deliverables", [])
        if isinstance(deliverables, list) and len(deliverables) >= 4:
            has_required_keys = all(all(k in d for k in ["filename", "duration_seconds", "resolution", "has_audio"]) for d in deliverables)
            if has_required_keys:
                score += 3
                feedback_parts.append("Manifest: Correct")
            else:
                feedback_parts.append("Manifest: Missing required item fields")
        else:
            feedback_parts.append("Manifest: Deliverables array invalid")
            
    except Exception as e:
        feedback_parts.append("Manifest: Invalid or Not Found")
    finally:
        if os.path.exists(temp_manifest.name):
            os.unlink(temp_manifest.name)

    # 7. Anti-Gaming / Timestamp Validation (Max 4 pts)
    files_created_during_task = True
    for key, data in media.items():
        if isinstance(data, dict) and data.get("exists"):
            if data.get("mtime", 0) < start_time:
                files_created_during_task = False
    
    if files_created_during_task and start_time > 0:
        score += 2
        
    master_dur = master.get("duration", 0)
    cine_dur = cinematic.get("duration", 0)
    if master_dur > 0 and cine_dur > 0:
        ratio = master_dur / cine_dur
        if 1.7 <= ratio <= 2.3:  # Expecting roughly 2.0
            score += 2

    # Final Evaluation
    pass_threshold = 35
    key_deliverables_exist = master.get("exists") and (cinematic.get("exists") or web.get("exists"))
    
    passed = score >= pass_threshold and key_deliverables_exist

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }