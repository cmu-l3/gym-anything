#!/usr/bin/env python3
"""
Verifier for add_requirement_comment task.

Verification Strategy:
1. Programmatic:
   - Check if any project file was modified (anti-gaming).
   - Search through the project JSON files for the specific comment text.
   - Verify the text matches expected string exactly or with high similarity.
2. Visual (VLM):
   - Check trajectory frames for the "Discussion" panel.
   - Verify the comment text was typed in the UI.

Scoring:
- 40 pts: Correct comment text found in project files.
- 10 pts: Files were actually modified during task (anti-gaming).
- 25 pts: VLM confirms Discussion panel was opened.
- 25 pts: VLM confirms comment being typed/submitted.
"""

import json
import os
import tarfile
import tempfile
import logging
import shutil
from difflib import SequenceMatcher

# Import VLM utils provided by framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_requirement_comment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', "")
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Task Result & Data
    # =========================================================
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result JSON
        result_file = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/tmp/task_result.json", result_file)
        with open(result_file, 'r') as f:
            result = json.load(f)
            
        # Get project data archive
        archive_path = os.path.join(temp_dir, "project_data.tar.gz")
        copy_from_env("/tmp/project_data.tar.gz", archive_path)
        
        # Extract archive
        data_dir = os.path.join(temp_dir, "data")
        os.makedirs(data_dir, exist_ok=True)
        try:
            with tarfile.open(archive_path, "r:gz") as tar:
                tar.extractall(path=data_dir)
        except Exception as e:
            logger.error(f"Failed to extract project data: {e}")
            feedback_parts.append("Failed to retrieve project data")

        # =========================================================
        # 2. Programmatic Verification (50 pts total)
        # =========================================================
        
        # Criterion A: Files modified (10 pts)
        if result.get("files_modified", False):
            score += 10
            feedback_parts.append("Project files modified")
        else:
            feedback_parts.append("No file changes detected")

        # Criterion B: Comment text found (40 pts)
        text_found = False
        max_similarity = 0.0
        
        # Search all JSON files extracted from the tarball
        for root, dirs, files in os.walk(data_dir):
            for file in files:
                if file.endswith(".json"):
                    try:
                        with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            
                            # Check for exact match
                            if expected_text in content:
                                text_found = True
                                max_similarity = 1.0
                                break
                                
                            # Check for fuzzy match if exact fails (robustness against formatting/encoding)
                            # We just check if the content contains a significant chunk
                            s = SequenceMatcher(None, content, expected_text)
                            match = s.find_longest_match(0, len(content), 0, len(expected_text))
                            if match.size > len(expected_text) * 0.9: # 90% of the text is there
                                text_found = True
                                max_similarity = match.size / len(expected_text)
                                break
                    except Exception:
                        continue
            if text_found: 
                break
        
        if text_found:
            score += 40
            feedback_parts.append("Comment text verified in project files")
        else:
            feedback_parts.append("Expected comment text not found in saved files")

        # =========================================================
        # 3. VLM Verification (50 pts total)
        # =========================================================
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = f"""
            You are verifying a software task in ReqView.
            The user was supposed to:
            1. Open the SRS document.
            2. Open the 'Discussion' panel for a requirement.
            3. Type the comment: "{expected_text[:30]}..."

            Look at the screenshots.
            Q1: Is the 'Discussion' panel or a comment input area visible in any frame? (Yes/No)
            Q2: Can you see the user typing the comment text or the text appearing in the panel? (Yes/No)
            
            Return JSON: {{ "discussion_panel_visible": bool, "text_entry_visible": bool }}
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                # Criterion C: Discussion Panel Visible (25 pts)
                if parsed.get("discussion_panel_visible", False):
                    score += 25
                    feedback_parts.append("VLM: Discussion panel detected")
                
                # Criterion D: Text Entry Visible (25 pts)
                if parsed.get("text_entry_visible", False):
                    score += 25
                    feedback_parts.append("VLM: Comment entry detected")
            else:
                feedback_parts.append("VLM verification failed")
                # Fallback: if text_found matches perfectly, give partial credit for VLM implicit success
                if text_found:
                    score += 30 
                    feedback_parts.append("(Fallback credit for verified file content)")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }