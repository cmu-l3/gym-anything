#!/usr/bin/env python3
"""
Verifier for retail_video_wall_vlm_orchestration task.
"""

import json
import tempfile
import os
import logging
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retail_video_wall_vlm_orchestration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlm_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check Process (10 pts)
    vlc_running = result.get('vlc_running', False)
    ffmpeg_running = result.get('ffmpeg_running', False)
    
    if vlc_running:
        score += 10
        feedback_parts.append("+ VLC process is running")
    else:
        feedback_parts.append("- VLC process is NOT running")
        
    if ffmpeg_running:
        feedback_parts.append("- FFMPEG process detected (possible cheating)")
        
    # Check Artifacts (10 pts)
    vlm_exists = result.get('vlm_file_exists', False)
    script_exists = result.get('script_exists', False)
    
    if vlm_exists and script_exists:
        score += 10
        feedback_parts.append("+ signage.vlm and start_signage.sh exist")
    else:
        if not vlm_exists: feedback_parts.append("- signage.vlm missing")
        if not script_exists: feedback_parts.append("- start_signage.sh missing")
        
    # VLM Syntax check (20 pts)
    vlm_content_b64 = result.get('vlm_content_b64', '')
    vlm_valid = False
    if vlm_content_b64:
        try:
            vlm_text = base64.b64decode(vlm_content_b64).decode('utf-8', errors='ignore').lower()
            if 'new window broadcast' in vlm_text or 'setup window input' in vlm_text or 'window_promo.mp4' in vlm_text:
                vlm_valid = True
                
            if 'setup' in vlm_text and 'output' in vlm_text and 'control' in vlm_text:
                score += 20
                feedback_parts.append("+ VLM syntax contains correct keywords")
            elif vlm_valid:
                score += 10
                feedback_parts.append("~ VLM syntax partially correct")
            else:
                feedback_parts.append("- VLM syntax missing required keywords")
        except:
            pass
            
    # Helper to analyze streams
    def analyze_stream(stream_data, expect_audio, name):
        pts = 0
        streams = stream_data.get('streams', [])
        
        has_video = False
        has_audio = False
        
        for s in streams:
            ctype = s.get('codec_type', '')
            if ctype == 'video':
                has_video = True
            elif ctype == 'audio':
                has_audio = True
                
        stream_feedback = []
        if has_video:
            pts += 10
            stream_feedback.append(f"{name} has video")
        else:
            stream_feedback.append(f"{name} missing video")
            
        if expect_audio:
            if has_audio:
                pts += 10
                stream_feedback.append(f"{name} has audio (correct)")
            else:
                stream_feedback.append(f"{name} missing audio")
        else:
            if not has_audio and has_video: # Ensure it connected at all
                pts += 10
                stream_feedback.append(f"{name} audio stripped (correct)")
            elif has_audio:
                stream_feedback.append(f"{name} has audio (should be stripped)")
                
        return pts, ", ".join(stream_feedback)

    # Check Window Stream (20 pts) - No Audio
    streams_data = result.get('streams', {})
    w_pts, w_feed = analyze_stream(streams_data.get('window', {}), False, "Window")
    score += w_pts
    feedback_parts.append(w_feed)
    
    # Check Entrance Stream (20 pts) - With Audio
    e_pts, e_feed = analyze_stream(streams_data.get('entrance', {}), True, "Entrance")
    score += e_pts
    feedback_parts.append(e_feed)
    
    # Check Checkout Stream (20 pts) - No Audio
    c_pts, c_feed = analyze_stream(streams_data.get('checkout', {}), False, "Checkout")
    score += c_pts
    feedback_parts.append(c_feed)

    # Calculate pass
    # Pass if score >= 70 and at least two streams are successfully streaming video
    streams_up = sum(1 for p in [w_pts, e_pts, c_pts] if p >= 10)
    
    passed = score >= 70 and streams_up >= 2 and vlc_running and not ffmpeg_running
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }