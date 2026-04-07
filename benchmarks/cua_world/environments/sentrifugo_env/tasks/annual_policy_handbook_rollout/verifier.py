#!/usr/bin/env python3
"""
Verifier for annual_policy_handbook_rollout task.

VERIFICATION STRATEGY:
1. Database State (Programmatic): 
   Scans the SQL dump to confirm the requested Titles and Descriptions were inserted.
2. File Integrity (Programmatic): 
   Calculates MD5 hashes of all files in Sentrifugo's upload directory and checks 
   if they match the original source PDFs placed in ~/Documents/2026_Policies/.
3. VLM Hybrid Verification: 
   Uses trajectory frames to confirm the agent actually interacted with the file 
   picker and Sentrifugo UI (anti-gaming).
"""

import json
import os
import tempfile
import logging

# Fallback imports if environment doesn't have gym_anything available directly
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Dummy fallbacks for testing outside framework
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_policy_rollout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    policies = metadata.get('policies', [])

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    temp_source_hashes = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_uploaded_hashes = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    score = 0
    feedback_parts = []

    try:
        # 1. Read task result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 2. Read DB Dump
        copy_from_env("/tmp/sentrifugo_db_dump.sql", temp_dump.name)
        with open(temp_dump.name, 'r', encoding='utf-8', errors='ignore') as f:
            db_content = f.read()

        # 3. Read Source Hashes
        copy_from_env("/tmp/source_pdf_hashes.txt", temp_source_hashes.name)
        with open(temp_source_hashes.name, 'r') as f:
            source_hashes = f.read().strip().split('\n')

        source_hash_map = {}
        for line in source_hashes:
            if line.strip():
                h, path = line.split(None, 1)
                filename = os.path.basename(path)
                source_hash_map[filename] = h

        # 4. Read Uploaded Hashes
        copy_from_env("/tmp/uploaded_pdf_hashes_clean.txt", temp_uploaded_hashes.name)
        with open(temp_uploaded_hashes.name, 'r') as f:
            uploaded_hashes = f.read().strip().split('\n')

        uploaded_hash_set = set()
        for line in uploaded_hashes:
            if line.strip():
                h = line.split(None, 1)[0]
                uploaded_hash_set.add(h)

        # Evaluate each policy (3 policies * 30 points = 90 points)
        for p in policies:
            title = p['title']
            desc = p['desc']
            file_name = p['file']

            # Check DB (15 points per policy)
            title_exists = title in db_content
            desc_exists = desc in db_content

            if title_exists and desc_exists:
                score += 15
                feedback_parts.append(f"DB Record OK: '{title}'")
            elif title_exists:
                score += 7
                feedback_parts.append(f"DB Record Partial (Title only): '{title}'")
            else:
                feedback_parts.append(f"DB Record Missing: '{title}'")

            # Check File Integrity (15 points per policy)
            expected_hash = source_hash_map.get(file_name)
            if expected_hash and expected_hash in uploaded_hash_set:
                score += 15
                feedback_parts.append(f"File Uploaded: {file_name}")
            else:
                feedback_parts.append(f"File Missing/Mismatched: {file_name}")

        # 5. VLM Trajectory Verification (10 points)
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                if images:
                    prompt = (
                        "Look at these screenshots showing an agent interacting with the Sentrifugo web app. "
                        "Did the agent interact with the Policy Documents upload form? "
                        "Look for evidence of file picker dialogs, browsing to Documents/2026_Policies, "
                        "and clicking 'Save' or 'Submit'. "
                        "Reply ONLY with a JSON object: {\"workflow_observed\": true/false}"
                    )
                    vlm_response = query_vlm(images=images, prompt=prompt)
                    parsed = vlm_response.get('parsed', {})
                    if parsed.get('workflow_observed', False):
                        score += 10
                        feedback_parts.append("VLM: Workflow successfully observed (+10)")
                    else:
                        feedback_parts.append("VLM: Workflow NOT clearly observed")
            except Exception as e:
                logger.warning(f"VLM verification skipped or failed: {e}")

    except Exception as e:
        logger.error(f"Verification encountered an error: {e}")
        return {"passed": False, "score": 0, "feedback": f"System error during verification: {str(e)}"}
    finally:
        for tf in [temp_result, temp_dump, temp_source_hashes, temp_uploaded_hashes]:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }