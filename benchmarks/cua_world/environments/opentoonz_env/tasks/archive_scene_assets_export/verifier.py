#!/usr/bin/env python3
"""
Verifier for archive_scene_assets_export task.

Task: Export scene to a new folder ensuring assets are copied (self-contained).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_archive_scene_assets_export(traj, env_info, task_info):
    """
    Verify that the scene and its assets were correctly exported.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # 2. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Scene File Exists (20 pts)
    if result.get('scene_found', False):
        score += 20
        feedback_parts.append("Scene file (.tnz) exported")
    else:
        feedback_parts.append("Scene file missing from output")

    # Criterion 2: Asset Files Exist (30 pts)
    # This proves the "Copy Scene Assets" option was likely used
    if result.get('asset_found', False):
        score += 30
        feedback_parts.append("Asset files (.pli/.tlv) found in package")
    else:
        feedback_parts.append("Asset files missing (package is not self-contained)")

    # Criterion 3: Path Integrity (30 pts)
    # The scene must reference the LOCAL files, not the ORIGINAL files
    path_relative = result.get('path_is_relative', False)
    path_local_abs = result.get('path_is_local_absolute', False)
    path_original = result.get('original_path_reference', False)

    if (path_relative or path_local_abs) and not path_original:
        score += 30
        feedback_parts.append("Scene correctly references local assets")
    elif path_original:
        feedback_parts.append("Scene still references original source files (Export failed to update paths)")
    else:
        feedback_parts.append("Could not verify asset path references")

    # Criterion 4: Anti-Gaming / Freshness (20 pts)
    if result.get('files_created_during_task', False):
        score += 20
        feedback_parts.append("Files created during task session")
    else:
        feedback_parts.append("Files are old or pre-existing")

    # 4. Final Assessment
    # Must have scene AND assets to be considered a "handoff package"
    # Pass threshold: 60 (Requires at least scene + assets + timestamps)
    passed = (score >= 60) and result.get('scene_found', False) and result.get('asset_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }