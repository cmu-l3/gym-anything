#!/usr/bin/env python3
"""
Verifier for Stream to TV task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_stream_to_tv(traj, env_info, task_info):
    """
    Verify stream to TV task completion.
    
    Checks:
    1. Stream URL file exists with valid format
    2. VLC process running in streaming mode
    3. Port 8080 listening
    4. Stream accessible with valid content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Stream URL file exists and has valid format
    temp_url_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    try:
        copy_from_env("/tmp/vlc_stream_url.txt", temp_url_file.name)
        
        with open(temp_url_file.name, 'r') as f:
            url_content = f.read().strip()
        
        # Check if URL matches expected format: http://<ip>:8080
        url_pattern = r'https?://(\d{1,3}\.){3}\d{1,3}:8080/?'
        if url_content and re.match(url_pattern, url_content):
            criteria_met += 1
            feedback_parts.append(f"✅ Stream URL documented: {url_content}")
        elif url_content:
            feedback_parts.append(f"⚠️ Stream URL invalid format: {url_content}")
        else:
            feedback_parts.append("❌ Stream URL file empty or missing")
        
        os.unlink(temp_url_file.name)
    except Exception as e:
        feedback_parts.append("❌ Stream URL file not found")
        logger.warning(f"Could not copy stream URL file: {e}")
    
    # Criterion 2: VLC process in streaming mode
    temp_process = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    try:
        copy_from_env("/tmp/vlc_stream_process.txt", temp_process.name)
        
        with open(temp_process.name, 'r') as f:
            process_info = f.read()
        
        # Check if VLC is running with streaming parameters
        # Look for 'sout' (stream output) or 'http' or '--sout'
        if 'sout' in process_info.lower() or '--http' in process_info or 'cvlc' in process_info:
            criteria_met += 1
            feedback_parts.append("✅ VLC streaming process detected")
        elif 'vlc' in process_info.lower():
            feedback_parts.append("⚠️ VLC running but not clearly in streaming mode")
        else:
            feedback_parts.append("❌ VLC streaming process not found")
        
        os.unlink(temp_process.name)
    except Exception as e:
        feedback_parts.append("❌ Could not verify VLC process")
        logger.warning(f"Could not copy process info: {e}")
    
    # Criterion 3: Port 8080 listening
    temp_port = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    try:
        copy_from_env("/tmp/vlc_stream_port.txt", temp_port.name)
        
        with open(temp_port.name, 'r') as f:
            port_info = f.read()
        
        # Check if port 8080 is in LISTEN state
        if ':8080' in port_info and ('LISTEN' in port_info or 'listen' in port_info.lower()):
            criteria_met += 1
            feedback_parts.append("✅ Port 8080 listening")
        else:
            feedback_parts.append("❌ Port 8080 not in LISTEN state")
        
        os.unlink(temp_port.name)
    except Exception as e:
        feedback_parts.append("❌ Could not verify port status")
        logger.warning(f"Could not copy port info: {e}")
    
    # Criterion 4: Stream accessible (from result JSON and optional content check)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    try:
        copy_from_env("/tmp/vlc_stream_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        stream_accessible = result.get('stream_accessible', False)
        content_size = result.get('stream_content_size', 0)
        
        if stream_accessible and content_size > 1000:
            criteria_met += 1
            feedback_parts.append(f"✅ Stream accessible ({content_size} bytes)")
        elif stream_accessible:
            feedback_parts.append(f"⚠️ Stream responded but content small ({content_size} bytes)")
        else:
            feedback_parts.append("❌ Stream not accessible")
        
        os.unlink(temp_result.name)
    except Exception as e:
        feedback_parts.append("⚠️ Could not verify stream accessibility")
        logger.warning(f"Could not copy result JSON: {e}")
    
    # Optional: Check stream content sample if available
    temp_content = tempfile.NamedTemporaryFile(delete=False, suffix='.bin', mode='wb+')
    try:
        copy_from_env("/tmp/vlc_stream_content_sample.bin", temp_content.name)
        
        content_size = os.path.getsize(temp_content.name)
        if content_size > 1000:
            # Read first few bytes to check if it looks like media data
            with open(temp_content.name, 'rb') as f:
                header = f.read(100)
            
            # Check for common media signatures (MPEG-TS, MP4, etc.)
            # MPEG-TS sync byte is 0x47
            if b'\x47' in header[:50] or header[:4] in [b'\x00\x00\x00\x18', b'\x00\x00\x00\x1c']:
                feedback_parts.append(f"✅ Stream content verified ({content_size} bytes)")
            else:
                feedback_parts.append(f"⚠️ Stream content format unclear ({content_size} bytes)")
        
        os.unlink(temp_content.name)
    except Exception as e:
        # This is optional, so don't penalize
        logger.debug(f"Stream content sample not available: {e}")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    try:
        copy_from_env("/tmp/vlc_stream_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completed")
        
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_met": criteria_met,
        "total_criteria": total_criteria
    }