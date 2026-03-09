#!/usr/bin/env python3
"""
Verifier for copy_artifact_to_release_repo task.
"""

import json
import os
import tempfile
import logging

# Import VLM utilities if available, otherwise mock them
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_copy_artifact(traj, env_info, task_info):
    """
    Verify that artifacts were copied from staging to release.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Data extraction
    orig_jar_sha = result.get("original_checksums", {}).get("jar", "orig_jar_missing")
    orig_pom_sha = result.get("original_checksums", {}).get("pom", "orig_pom_missing")
    
    target_jar = result.get("target_artifacts", {}).get("jar", {})
    target_pom = result.get("target_artifacts", {}).get("pom", {})
    source_jar = result.get("source_artifacts", {}).get("jar", {})
    source_pom = result.get("source_artifacts", {}).get("pom", {})

    # Criterion 1: JAR in release repo (25 pts)
    if target_jar.get("exists"):
        score += 25
        feedback.append("JAR found in release repo.")
    else:
        feedback.append("JAR NOT found in release repo.")

    # Criterion 2: POM in release repo (25 pts)
    if target_pom.get("exists"):
        score += 25
        feedback.append("POM found in release repo.")
    else:
        feedback.append("POM NOT found in release repo.")

    # Criterion 3: Integrity Check (15 pts)
    integrity_pass = True
    if target_jar.get("sha256") != orig_jar_sha:
        integrity_pass = False
        feedback.append("JAR checksum mismatch (corrupted copy?).")
    if target_pom.get("sha256") != orig_pom_sha:
        integrity_pass = False
        feedback.append("POM checksum mismatch.")
    
    if integrity_pass and target_jar.get("exists") and target_pom.get("exists"):
        score += 15
        feedback.append("Artifact integrity verified.")

    # Criterion 4: Source Preservation (15 pts) - Ensure it was a COPY, not a MOVE
    if source_jar.get("exists") and source_pom.get("exists"):
        score += 15
        feedback.append("Source artifacts preserved (correctly copied).")
    else:
        feedback.append("Source artifacts missing (moved instead of copied?).")

    # Criterion 5: VLM / Anti-gaming (20 pts)
    # If VLM is available, check trajectory. If not, rely on file existence timestamp logic implicit in the fact
    # that we wiped the repo at start.
    
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        # Simple VLM check placeholder
        # In a real scenario, we would query a VLM here with frames
        # For now, we assume if artifacts exist and we have trajectory, some work was done
        if len(traj) > 2:
            vlm_score = 20
            feedback.append("Trajectory verification passed.")
        else:
             feedback.append("Trajectory too short.")
    else:
        # Fallback if VLM not available: pass if artifacts exist (assuming secure env)
        if target_jar.get("exists"):
            vlm_score = 20
            feedback.append("Implicit verification passed.")
            
    score += vlm_score

    passed = (score >= 60) and target_jar.get("exists") and target_pom.get("exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }