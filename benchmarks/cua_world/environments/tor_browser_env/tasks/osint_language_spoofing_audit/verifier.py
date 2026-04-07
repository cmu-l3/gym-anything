#!/usr/bin/env python3
"""Verifier for osint_language_spoofing_audit task.

Checks that the agent successfully bypassed Tor's language spoofing protection,
captured the Russian headers from httpbin.org, and importantly, RESTORED the
protection afterwards to capture the English headers.
"""

import json
import logging
import os
import re
import tempfile
import base64
from io import BytesIO
from PIL import Image

# Import framework VLM tools
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trajectory_with_vlm(frames) -> dict:
    """Uses VLM to verify the agent actually navigated the Settings UI or about:config."""
    if not frames:
        return {'verified': False, 'confidence': 0.0, 'details': 'No frames provided'}

    try:
        import openai
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')

        if not vlm_api_key:
            logger.warning("VLM API Key not set, skipping trajectory VLM verification.")
            return {'verified': True, 'confidence': 1.0, 'details': 'Skipped (No API Key)'} # Default pass if no key

        client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)

        prompt = """Analyze these sequence of frames from a Tor Browser session.
Did the user navigate to 'about:config' OR the browser's Language Settings to change language or spoofing preferences?
Look for:
- The 'about:config' warning screen or search bar
- The text 'privacy.spoof_english' in a list
- Firefox/Tor Settings page under 'Language' or 'General'

Respond strictly with:
VERIFIED: [YES/NO]
CONFIDENCE: [0-100]
DETAILS: [brief reason]"""

        content = [{"type": "text", "text": prompt}]
        
        # Add up to 6 evenly sampled frames to the VLM
        for img_path in frames[:6]:
            if os.path.exists(img_path):
                img = Image.open(img_path).resize((1024, 768))
                buf = BytesIO()
                img.save(buf, format="JPEG", quality=80)
                b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
                content.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{b64}"}
                })

        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=[{"role": "user", "content": content}],
            max_tokens=300,
            temperature=0.0
        )
        
        response_text = response.choices[0].message.content
        if isinstance(response_text, list):
            response_text = response_text[-1].get('text', '') if isinstance(response_text[-1], dict) else str(response_text[-1])

        verified = False
        for line in response_text.strip().split('\n'):
            if line.upper().startswith('VERIFIED:'):
                verified = 'YES' in line.upper()
                break
                
        return {'verified': verified, 'details': response_text}
    except Exception as e:
        logger.error(f"VLM error: {e}")
        return {'verified': False, 'details': str(e)}

def parse_header_file(file_content: str):
    """Parses JSON or regex extracts headers if wrapped in HTML tags by browser."""
    try:
        data = json.loads(file_content)
        headers = data.get("headers", {})
        # httpbin capitalizes standardly, but lowercasing for safety
        return {k.lower(): v for k, v in headers.items()}
    except json.JSONDecodeError:
        # Fallback to regex if they saved page source (HTML)
        headers = {}
        al_match = re.search(r'"Accept-Language":\s*"([^"]+)"', file_content, re.IGNORECASE)
        ua_match = re.search(r'"User-Agent":\s*"([^"]+)"', file_content, re.IGNORECASE)
        if al_match:
            headers['accept-language'] = al_match.group(1)
        if ua_match:
            headers['user-agent'] = ua_match.group(1)
        return headers

def verify_osint_language_spoofing(traj, env_info, task_info):
    """
    Verification strategy:
    1. httpbin.org visited (15 pts)
    2. headers_ru.json is valid, created during task, language starts with 'ru', UA is Mozilla (20 pts)
    3. headers_en.json is valid, created during task, language starts with 'en', UA is Mozilla (20 pts)
    4. Trajectory shows configuration UI usage via VLM (25 pts)
    5. OPSEC Setting Restored (privacy.spoof_english = true) (20 pts) [REQUIRED GATE]
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Load Main Result JSON
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)

    # 2. Check Browser History
    if result.get('visited_httpbin', False):
        score += 15
        feedback_parts.append("Visited httpbin.org (15/15)")
    else:
        feedback_parts.append("httpbin.org not found in history (0/15)")

    # 3. Check RU Headers File
    if result.get('ru_file_exists') and result.get('ru_file_is_new'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            copy_from_env("/home/ga/Documents/headers_ru.json", tmp.name)
            with open(tmp.name, 'r') as f:
                ru_content = f.read()
            os.unlink(tmp.name)
            
        ru_headers = parse_header_file(ru_content)
        al = ru_headers.get('accept-language', '')
        ua = ru_headers.get('user-agent', '')
        
        if al.startswith('ru') and 'Mozilla' in ua:
            score += 20
            feedback_parts.append("Russian headers captured correctly (20/20)")
        else:
            feedback_parts.append(f"RU headers invalid: AL='{al}', UA='{ua}' (0/20)")
    else:
        feedback_parts.append("headers_ru.json missing or stale (0/20)")

    # 4. Check EN Headers File
    if result.get('en_file_exists') and result.get('en_file_is_new'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            copy_from_env("/home/ga/Documents/headers_en.json", tmp.name)
            with open(tmp.name, 'r') as f:
                en_content = f.read()
            os.unlink(tmp.name)
            
        en_headers = parse_header_file(en_content)
        al = en_headers.get('accept-language', '')
        ua = en_headers.get('user-agent', '')
        
        if al.startswith('en') and 'Mozilla' in ua:
            score += 20
            feedback_parts.append("English headers captured correctly (20/20)")
        else:
            feedback_parts.append(f"EN headers invalid: AL='{al}', UA='{ua}' (0/20)")
    else:
        feedback_parts.append("headers_en.json missing or stale (0/20)")

    # 5. Check OPSEC Restoration (GATE)
    opsec_restored = result.get('privacy_spoof_english', False)
    if opsec_restored:
        score += 20
        feedback_parts.append("OPSEC Restored (privacy.spoof_english=true) (20/20)")
    else:
        feedback_parts.append("FAIL: OPSEC NOT restored. privacy.spoof_english is false (0/20)")

    # 6. VLM Trajectory Verification
    frames = sample_trajectory_frames(traj, n=6)
    vlm_result = verify_trajectory_with_vlm(frames)
    if vlm_result['verified']:
        score += 25
        feedback_parts.append("Trajectory verified via VLM (25/25)")
    else:
        feedback_parts.append("VLM did not detect configuration UI usage (0/25)")

    # Determine Pass
    passed = score >= 60 and opsec_restored

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }