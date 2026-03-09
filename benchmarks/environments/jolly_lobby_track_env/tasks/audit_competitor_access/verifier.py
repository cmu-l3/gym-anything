#!/usr/bin/env python3
"""
Verifier for Audit Competitor Access task.

Criteria:
1. Output file exists (CSV, PDF, or TXT) in Documents folder.
2. File was created during the task window.
3. Content Inclusion: Contains "Sarah Lee" AND "Tom Borg" (Nexus Industries employees).
4. Content Exclusion: Does NOT contain "John Doe", "Mike Smith", or "Jane Doe" (Other companies).
5. VLM Verification: Agent trajectory confirms usage of filter/search functionality.
"""

import json
import base64
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils from framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_competitor_access(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    positive_samples = metadata.get('positive_samples', ["Sarah Lee", "Tom Borg"])
    negative_samples = metadata.get('negative_samples', ["John Doe", "Mike Smith", "Jane Doe"])
    
    # 1. Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Creation (20 pts)
    output_found = result.get("output_found", False)
    file_created = result.get("file_created_during_task", False)
    
    if output_found:
        score += 10
        feedback_parts.append(f"Output file found at {result.get('output_path')}")
        if file_created:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("Warning: File timestamp indicates it was not created during this session")
    else:
        feedback_parts.append("No output file found (CSV/PDF/TXT)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Content Verification (Inclusion) (30 pts)
    content_b64 = result.get("file_content_base64", "")
    content_str = ""
    try:
        if content_b64 and content_b64 != "BINARY_FORMAT" and content_b64 != "PDF_NO_TEXT_TOOL":
            content_str = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content_str = ""

    inclusion_hits = 0
    if content_str:
        for name in positive_samples:
            if name.lower() in content_str.lower():
                inclusion_hits += 1
        
        inclusion_score = (inclusion_hits / len(positive_samples)) * 30
        score += inclusion_score
        if inclusion_hits == len(positive_samples):
            feedback_parts.append("All target visitors found in report")
        elif inclusion_hits > 0:
            feedback_parts.append(f"Some target visitors found ({inclusion_hits}/{len(positive_samples)})")
        else:
            feedback_parts.append("No target visitors found in report")
    else:
        feedback_parts.append("Could not verify file content text")

    # Criterion 3: Content Verification (Exclusion) (40 pts)
    # The file should NOT contain visitors from other companies
    exclusion_hits = 0
    if content_str:
        for name in negative_samples:
            if name.lower() in content_str.lower():
                exclusion_hits += 1
        
        if exclusion_hits == 0:
            score += 40
            feedback_parts.append("Filter applied correctly (no unrelated visitors)")
        else:
            # Partial credit if they filtered some out? No, strict filtering required for audit.
            # But we'll give minimal points if file is mostly correct? No, 0 for this section.
            feedback_parts.append(f"Failed filter check: Found {exclusion_hits} unrelated visitors")
    
    # Criterion 4: VLM Verification (10 pts)
    # Did they use the search/filter bar?
    frames = sample_trajectory_frames(traj, n=4)
    final_ss = get_final_screenshot(traj)
    images = frames + ([final_ss] if final_ss else [])
    
    vlm_prompt = (
        "Analyze this sequence of screenshots from Jolly Lobby Track software. "
        "Did the user perform a search or apply a filter for 'Nexus' or 'Nexus Industries'? "
        "Look for: 1. Text entered in a search bar. 2. A filtered list showing only specific names. "
        "3. An export or print action."
    )
    
    try:
        vlm_res = query_vlm(images=images, prompt=vlm_prompt)
        if vlm_res.get("success"):
            # Simple keyword check in reasoning if structured parsing fails
            analysis = vlm_res.get("response", "").lower()
            if "search" in analysis or "filter" in analysis or "nexus" in analysis:
                score += 10
                feedback_parts.append("Visual verification passed")
    except Exception:
        pass # Ignore VLM failures for scoring if program check passed

    # Pass Threshold
    # Must have created file + found positives + excluded negatives
    # Threshold 70 ensures filter was applied
    passed = (score >= 70) and file_created

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }