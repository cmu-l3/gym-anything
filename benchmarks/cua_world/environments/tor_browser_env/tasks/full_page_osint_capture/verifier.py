#!/usr/bin/env python3
"""Verifier for full_page_osint_capture task.

Checks:
1. Files were created during the task (anti-gaming timestamps).
2. Images are valid PNGs with a height > 1500px (proves full-page screenshot tool).
3. Chain of custody text file exists.
4. Cryptographic hashes in the text file EXACTLY match the dynamic hashes of the generated images.
5. VLM trajectory verifies Developer Tools/Terminal usage.
"""

import json
import logging
import os
import tempfile
import hashlib
import base64
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trajectory_with_vlm(traj) -> dict:
    """Use VLM to sample trajectory frames and verify DevTools or Terminal usage."""
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=6)
        
        import openai
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')

        if not vlm_api_key:
            return {'verified': False, 'details': 'VLM_API_KEY not set'}

        client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)

        prompt = """Analyze these sequence of screenshots from a browser automation task.
Did the agent open the Tor Browser/Firefox Developer Tools (Console, Inspector, Settings) OR a Linux Terminal application at any point?
I am looking for evidence that the agent utilized advanced developer commands or terminal commands.

Respond EXACTLY with:
VERIFIED: [YES/NO]
DETAILS: [Brief explanation of what you see]"""

        content = [{"type": "text", "text": prompt}]
        for frame_path in frames:
            if os.path.exists(frame_path):
                img = Image.open(frame_path).resize((1024, 576))
                import io
                buf = io.BytesIO()
                img.save(buf, format="JPEG")
                b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
                content.append({"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}})

        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=[{"role": "user", "content": content}],
            max_tokens=200,
            temperature=0.0
        )

        resp_text = response.choices[0].message.content
        verified = False
        details = resp_text
        for line in resp_text.split('\n'):
            if line.upper().startswith('VERIFIED:'):
                verified = 'YES' in line.upper()
        return {'verified': verified, 'details': details}
    except Exception as e:
        logger.warning(f"VLM trajectory verification failed: {e}")
        return {'verified': False, 'details': str(e)}

def compute_sha256(filepath: str) -> str:
    """Compute SHA-256 of a file."""
    sha256_hash = hashlib.sha256()
    try:
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except Exception as e:
        logger.error(f"Hash computation failed for {filepath}: {e}")
        return ""

def verify_full_page_osint_capture(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_height_px = metadata.get('min_height_px', 1500)
    min_size_bytes = metadata.get('min_size_bytes', 102400)

    # Temporary files for copied content
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_hist = tempfile.NamedTemporaryFile(delete=False, suffix='_hist.png')
    tmp_comm = tempfile.NamedTemporaryFile(delete=False, suffix='_comm.png')
    tmp_coc = tempfile.NamedTemporaryFile(delete=False, suffix='_coc.txt')
    
    tmp_json.close()
    tmp_hist.close()
    tmp_comm.close()
    tmp_coc.close()

    score = 0
    feedback_parts = []
    
    try:
        # 1. Load JSON Metadata
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        task_start = result.get('task_start', 0)

        # Gate Check: History PNG
        hist_exists = result.get('history_exists', False)
        hist_mtime = result.get('history_mtime', 0)
        hist_size = result.get('history_size', 0)
        hist_created_during_task = hist_mtime > task_start

        if hist_exists and hist_created_during_task and hist_size > min_size_bytes:
            score += 15
            feedback_parts.append("History PNG exists & valid size (15/15)")
        else:
            feedback_parts.append("History PNG missing, empty, or stale (0/15) - GATE FAILED")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # 2. History Image Dimension Analysis & Hashing
        hist_hash = ""
        try:
            copy_from_env("/tmp/history_evidence.png", tmp_hist.name)
            img = Image.open(tmp_hist.name)
            width, height = img.size
            if height > min_height_px:
                score += 15
                feedback_parts.append(f"History PNG is full-page height ({height}px) (15/15)")
            else:
                feedback_parts.append(f"History PNG height too small ({height}px <= {min_height_px}), not full-page (0/15)")
            hist_hash = compute_sha256(tmp_hist.name)
        except Exception as e:
            feedback_parts.append(f"History PNG invalid image file: {e} (0/15)")

        # 3. Community Image Existence & Dimensions & Hashing
        comm_exists = result.get('community_exists', False)
        comm_mtime = result.get('community_mtime', 0)
        comm_size = result.get('community_size', 0)
        comm_created_during_task = comm_mtime > task_start
        comm_hash = ""

        if comm_exists and comm_created_during_task and comm_size > min_size_bytes:
            score += 15
            feedback_parts.append("Community PNG exists & valid size (15/15)")
            try:
                copy_from_env("/tmp/community_evidence.png", tmp_comm.name)
                img = Image.open(tmp_comm.name)
                width, height = img.size
                if height > min_height_px:
                    score += 15
                    feedback_parts.append(f"Community PNG is full-page height ({height}px) (15/15)")
                else:
                    feedback_parts.append(f"Community PNG height too small ({height}px), not full-page (0/15)")
                comm_hash = compute_sha256(tmp_comm.name)
            except Exception as e:
                feedback_parts.append(f"Community PNG invalid image file: {e} (0/15)")
        else:
            feedback_parts.append("Community PNG missing, empty, or stale (0/30)")

        # 4. Chain of Custody Text File Analysis
        coc_exists = result.get('coc_exists', False)
        coc_mtime = result.get('coc_mtime', 0)
        coc_created_during_task = coc_mtime > task_start

        if coc_exists and coc_created_during_task:
            score += 10
            feedback_parts.append("Chain of Custody file exists (10/10)")
            try:
                copy_from_env("/tmp/chain_of_custody.txt", tmp_coc.name)
                with open(tmp_coc.name, 'r', encoding='utf-8', errors='ignore') as f:
                    coc_content = f.read().strip()
                
                # Check dynamic History hash
                if hist_hash and hist_hash in coc_content:
                    score += 10
                    feedback_parts.append("History SHA-256 hash verified in document (10/10)")
                else:
                    feedback_parts.append("History SHA-256 hash NOT found in document (0/10)")

                # Check dynamic Community hash
                if comm_hash and comm_hash in coc_content:
                    score += 10
                    feedback_parts.append("Community SHA-256 hash verified in document (10/10)")
                else:
                    feedback_parts.append("Community SHA-256 hash NOT found in document (0/10)")
            except Exception as e:
                feedback_parts.append(f"Failed to read CoC file: {e} (0/20)")
        else:
            feedback_parts.append("Chain of Custody file missing or stale (0/30)")

        # 5. VLM Trajectory Verification
        vlm_res = verify_trajectory_with_vlm(traj)
        if vlm_res.get('verified', False):
            score += 10
            feedback_parts.append("VLM confirms DevTools/Terminal usage (10/10)")
        else:
            feedback_parts.append("VLM did not detect DevTools/Terminal usage (0/10)")

    finally:
        # Cleanup
        for p in [tmp_json.name, tmp_hist.name, tmp_comm.name, tmp_coc.name]:
            if os.path.exists(p):
                os.unlink(p)

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }