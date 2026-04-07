#!/usr/bin/env python3
"""Verifier for tor_circuit_rotation_report task.

Verifies the agent navigated correctly, documented IP addresses, 
and performed the circuit rotation in Tor Browser.
"""

import json
import logging
import os
import re
import tempfile
import ipaddress
import base64
from io import BytesIO
from typing import List

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_public_ipv4s(text: str) -> List[str]:
    """Extract valid, public IPv4 addresses from text."""
    # Find all potential IPv4s
    potential_ips = re.findall(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b', text)
    valid_public_ips = []
    
    for ip_str in potential_ips:
        try:
            ip = ipaddress.IPv4Address(ip_str)
            # Must be a global/public IP, not private, loopback, or broadcast
            if not ip.is_private and not ip.is_loopback and not ip.is_multicast and not ip.is_reserved:
                # Extra explicit filter for 0.0.0.0 and 255.255.255.255
                if ip_str not in ["0.0.0.0", "255.255.255.255"]:
                    valid_public_ips.append(ip_str)
        except ipaddress.AddressValueError:
            pass
            
    # Return unique IPs
    return list(set(valid_public_ips))


def vlm_verify_circuit_rotation(traj) -> dict:
    """Use VLM on trajectory frames to detect if the user interacted with 'New Circuit' UI."""
    try:
        frames = sample_trajectory_frames(traj, n=8)
        if not frames:
            return {"verified": False, "score": 0, "feedback": "No frames available"}

        # Encode frames
        encoded_frames = []
        for frame in frames:
            from PIL import Image
            if isinstance(frame, str) and os.path.exists(frame):
                img = Image.open(frame).convert("RGB")
            else:
                img = Image.fromarray(frame).convert("RGB")
                
            img.thumbnail((1280, 720))
            buffer = BytesIO()
            img.save(buffer, format="JPEG", quality=80)
            encoded_frames.append(base64.b64encode(buffer.getvalue()).decode('utf-8'))

        import openai
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')
        
        if not vlm_api_key:
            return {"verified": False, "score": 0, "feedback": "VLM_API_KEY not configured"}

        client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)

        prompt = """Analyze these sequential screenshots of an agent using Tor Browser.
I need to know if the agent accessed the 'New Circuit for this Site' feature.

Look for ANY of the following in the sequence:
1. The site information/padlock menu opened with a "New Circuit for this Site" button visible or clicked.
2. The main hamburger menu opened with a "New Circuit for this Site" button visible or clicked.
3. The Tor Browser UI showing a notification or refresh indicating a circuit rotation.

Did the agent open the menu or UI element to request a new Tor circuit?
Reply ONLY with YES or NO."""

        content = [{"type": "text", "text": prompt}]
        for frame_b64 in encoded_frames:
             content.append({
                 "type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{frame_b64}"}
             })

        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=[{"role": "user", "content": content}],
            max_tokens=20,
            temperature=0.0
        )
        
        reply = response.choices[0].message.content.strip().upper()
        if "YES" in reply:
            return {"verified": True, "score": 25, "feedback": "VLM verified circuit rotation UI interaction."}
        else:
            return {"verified": False, "score": 0, "feedback": "VLM did not detect circuit rotation UI interaction."}
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        return {"verified": False, "score": 0, "feedback": f"VLM Error: {str(e)}"}


def verify_circuit_rotation(traj, env_info, task_info):
    """
    Scoring Breakdown (100 pts total):
    1. File exists at exact path [GATE] : 10 pts
    2. File created/modified after start: 10 pts
    3. Contains >= 1 valid public IPv4  : 10 pts
    4. Contains >= 2 distinct IPs       : 15 pts
    5. History: check.torproject.org    : 5 pts
    6. History: check visited >= 2 times: 10 pts
    7. History: www.torproject.org      : 5 pts
    8. Bookmark 'Tor Connection Verifier': 10 pts
    9. VLM trajectory verification      : 25 pts
    
    Pass threshold: 60 points + file exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read VM export: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    file_exists = result.get('file_exists', False)
    if file_exists:
        score += 10
        feedback_parts.append("Report file exists (+10)")
    else:
        feedback_parts.append("Report file missing")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
        
    # Check timestamp
    file_mtime = int(result.get('file_mtime', 0))
    task_start = int(result.get('task_start_time', 0))
    if file_mtime > task_start and task_start > 0:
        score += 10
        feedback_parts.append("Report created during task (+10)")
    else:
        feedback_parts.append("Report predates task start (0)")

    # Extract IPs
    content = result.get('file_content', '')
    # Handle the literal escaped newlines from the bash script
    content = content.replace('\\n', '\n')
    ips = extract_public_ipv4s(content)
    
    if len(ips) >= 1:
        score += 10
        feedback_parts.append(f"Found valid public IP (+10)")
    else:
        feedback_parts.append("No valid public IP found in report")
        
    if len(ips) >= 2:
        score += 15
        feedback_parts.append(f"Found {len(ips)} distinct public IPs (+15)")
    elif len(ips) == 1:
        feedback_parts.append(f"Only 1 valid public IP found. Needed 2 for rotation evidence.")

    # History & Bookmarks
    if result.get('history_check_torproject'):
        score += 5
        feedback_parts.append("Visited check.torproject.org (+5)")
        
        visits = result.get('history_check_torproject_visits', 0)
        if visits >= 2:
            score += 10
            feedback_parts.append(f"check.torproject.org reloaded ({visits} visits) (+10)")
        else:
            feedback_parts.append(f"check.torproject.org only visited once")
            
    if result.get('history_www_torproject'):
        score += 5
        feedback_parts.append("Visited www.torproject.org (+5)")
        
    if result.get('bookmark_tor_verifier_exists'):
        score += 10
        feedback_parts.append("Bookmark created correctly (+10)")
        
    # VLM Trajectory Verification
    vlm_result = vlm_verify_circuit_rotation(traj)
    score += vlm_result['score']
    feedback_parts.append(vlm_result['feedback'])

    passed = score >= 60 and file_exists
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "ips_found": ips,
            "db_found": result.get('db_found'),
            "vlm_verified": vlm_result['verified']
        }
    }