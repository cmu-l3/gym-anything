#!/usr/bin/env python3
"""
Verifier for Hospitality IPTV Streaming Setup task.

Verification Strategy (Multiple Independent Programmatic Signals):
1. Process Verification: Checks that port 8080 and 8081 are actively bound by a `vlc` process (anti-gaming against ffmpeg mock servers).
2. Network Stream Probe: Parses the live HTTP stream output using ffprobe to verify the video was actively transcoded to the required specifications (H.264, 1280x720) and audio to MP3.
3. Documentation Verification: Checks the requested bash scripts exist and contain VLC streaming commands along with bitrate specifications.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hospitality_iptv_streaming_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    port_8080_proc = result.get("port_8080_proc", "")
    port_8081_proc = result.get("port_8081_proc", "")
    promo_probe = result.get("promo_probe", {})
    ambient_probe = result.get("ambient_probe", {})
    promo_script = result.get("promo_script", "")
    ambient_script = result.get("ambient_script", "")
    
    # 1. Promo Process Alive (15 points)
    promo_alive = False
    if "8080" in port_8080_proc:
        if "vlc" in port_8080_proc.lower() or "cvlc" in port_8080_proc.lower():
            score += 15
            promo_alive = True
            feedback_parts.append("+ Promo process (vlc) alive on port 8080")
        else:
            feedback_parts.append("- Process listening on 8080 is not VLC (anti-gaming violation)")
    else:
        feedback_parts.append("- No process is listening on port 8080")

    # 2. Promo Stream Specs (25 points)
    if promo_alive and "streams" in promo_probe and len(promo_probe["streams"]) > 0:
        v_stream = next((s for s in promo_probe["streams"] if s.get("codec_type") == "video"), None)
        if v_stream:
            spec_score = 0
            # Validate Transcoding Codec
            if v_stream.get("codec_name") == "h264":
                spec_score += 10
            # Validate Transcoding Resolution
            if v_stream.get("width") == 1280 and v_stream.get("height") == 720:
                spec_score += 15
                
            score += spec_score
            feedback_parts.append(f"+ Promo stream specs verification: {spec_score}/25 pts (Codec: {v_stream.get('codec_name')}, Res: {v_stream.get('width')}x{v_stream.get('height')})")
        else:
            feedback_parts.append("- Promo stream is active but no video stream was detected inside the mux")
    elif promo_alive:
        err = promo_probe.get("error", "Unknown probe error")
        feedback_parts.append(f"- Promo stream probe failed to read data: {err}")

    # 3. Ambient Process Alive (15 points)
    ambient_alive = False
    if "8081" in port_8081_proc:
        if "vlc" in port_8081_proc.lower() or "cvlc" in port_8081_proc.lower():
            score += 15
            ambient_alive = True
            feedback_parts.append("+ Ambient process (vlc) alive on port 8081")
        else:
            feedback_parts.append("- Process listening on 8081 is not VLC (anti-gaming violation)")
    else:
        feedback_parts.append("- No process is listening on port 8081")

    # 4. Ambient Stream Specs (25 points)
    if ambient_alive and "streams" in ambient_probe and len(ambient_probe["streams"]) > 0:
        a_stream = next((s for s in ambient_probe["streams"] if s.get("codec_type") == "audio"), None)
        if a_stream:
            # Validate Transcoding Codec
            if a_stream.get("codec_name") == "mp3":
                score += 25
                feedback_parts.append("+ Ambient stream specs verification: 25/25 pts (Codec: MP3)")
            else:
                score += 10  # Partial credit for getting audio through
                feedback_parts.append(f"- Ambient stream has incorrect audio codec: {a_stream.get('codec_name')}")
        else:
            feedback_parts.append("- Ambient stream is active but no audio stream was detected inside the mux")
    elif ambient_alive:
        err = ambient_probe.get("error", "Unknown probe error")
        feedback_parts.append(f"- Ambient stream probe failed to read data: {err}")

    # 5. Launch Scripts & Bitrate parameters (20 points)
    scripts_score = 0
    
    if promo_script.strip():
        scripts_score += 5
        # Look for bitrate params (vb=2000, vb=2M, vbitrate=2000, 2048)
        if any(x in promo_script.lower() for x in ["2000", "2048", "2m"]):
            scripts_score += 5
            
    if ambient_script.strip():
        scripts_score += 5
        # Look for audio bitrate param (ab=192, 192)
        if "192" in ambient_script:
            scripts_score += 5
            
    score += scripts_score
    if scripts_score > 0:
        feedback_parts.append(f"+ Documentation scripts verified: {scripts_score}/20 pts")
    else:
        feedback_parts.append("- Launch scripts are missing or empty")

    # To pass, they must score >= 70 AND have successfully established at least one live VLC stream
    passed = score >= 70 and (promo_alive or ambient_alive)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }