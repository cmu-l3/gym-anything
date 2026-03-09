#!/usr/bin/env python3
"""Verifier for migrate_deprecated_api task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_migrate_api(traj, env_info, task_info):
    """
    Verify the migration of processLegacy to processModern.
    
    Criteria:
    1. No stale calls: All calls to processLegacy in caller files should be gone.
    2. Modern calls present: Replaced with processModern.
    3. Declaration preserved: processLegacy declaration in DataProcessor.java must exist.
    4. Compile success: Project must compile (checked via export script result).
    5. Files modified: Anti-gaming check on timestamps.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/data-pipeline')
    caller_files = metadata.get('caller_files', [])
    main_class = metadata.get('main_class_file', 'src/main/java/com/pipeline/DataProcessor.java')
    
    score = 0
    feedback_parts = []
    
    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # Load result from export script (for compile status)
    task_result = {}
    try:
        content = copy_and_read("/tmp/task_result.json")
        if content:
            task_result = json.loads(content)
    except Exception as e:
        logger.warning(f"Failed to load task result: {e}")

    # --- Criterion 1 & 2: Check Caller Files (55 pts total) ---
    stale_calls = 0
    modern_calls = 0
    files_checked = 0
    
    for rel_path in caller_files:
        content = copy_and_read(f"{project_dir}/{rel_path}")
        if content:
            files_checked += 1
            # Count calls. Note: simple string match is usually sufficient for this specific task
            # We look for .processLegacy(
            stale_calls += content.count(".processLegacy(")
            modern_calls += content.count(".processModern(")
    
    # 35 points for removing all stale calls
    if files_checked > 0:
        if stale_calls == 0:
            score += 35
            feedback_parts.append("All legacy calls removed")
        else:
            feedback_parts.append(f"{stale_calls} legacy calls remaining")
            # Partial credit? No, clean migration required for full points.
            # Maybe tiny partial if some removed, but let's stick to binary for cleanliness.
            
    # 20 points for having correct number of modern calls
    expected_modern = metadata.get("expected_modern_calls", 12)
    if modern_calls >= expected_modern:
        score += 20
        feedback_parts.append(f"Found {modern_calls} modern calls (expected >= {expected_modern})")
    elif modern_calls > 0:
        # Partial credit
        partial = int(20 * (modern_calls / expected_modern))
        score += partial
        feedback_parts.append(f"Found {modern_calls}/{expected_modern} modern calls")
    else:
        feedback_parts.append("No modern calls found")

    # --- Criterion 3: Deprecated Declaration Preserved (10 pts) ---
    dp_content = copy_and_read(f"{project_dir}/{main_class}")
    if dp_content:
        # Must contain the definition
        has_decl = "public List<String> processLegacy(" in dp_content
        has_dep_anno = "@Deprecated" in dp_content
        
        if has_decl:
            score += 10
            feedback_parts.append("Deprecated method declaration preserved")
            if not has_dep_anno:
                feedback_parts.append("(Warning: @Deprecated annotation missing)")
        else:
            feedback_parts.append("Error: Deprecated method declaration was deleted")
    else:
        feedback_parts.append("DataProcessor.java not found")

    # --- Criterion 4: Maven Compile (25 pts) ---
    exit_code = task_result.get("compile_exit_code", 1)
    if exit_code == 0:
        score += 25
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append(f"Project compilation failed (exit code {exit_code})")

    # --- Criterion 5: Files Modified (10 pts) ---
    # Check if files were actually touched using timestamps
    initial_stats = copy_and_read("/tmp/initial_file_stats.txt")
    final_stats = copy_and_read("/tmp/final_file_stats.txt")
    
    modified_count = 0
    if initial_stats and final_stats:
        initial_map = {}
        for line in initial_stats.strip().split('\n'):
            parts = line.split(' ')
            if len(parts) >= 2:
                initial_map[parts[0]] = parts[1]
        
        for line in final_stats.strip().split('\n'):
            parts = line.split(' ')
            if len(parts) >= 2:
                fname = parts[0]
                fts = parts[1]
                if fname in initial_map and initial_map[fname] != fts:
                    modified_count += 1
    
    if modified_count >= 5: # We expect at least 6 caller files to change
        score += 10
        feedback_parts.append(f"{modified_count} files modified")
    elif modified_count > 0:
        score += 5
        feedback_parts.append(f"Only {modified_count} files modified")
    else:
        feedback_parts.append("No files modified (do nothing detected)")

    # --- VLM Verification (Bonus/Confirmation) ---
    # Using the gym_anything VLM helper if available
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=5)
        if frames:
            feedback_parts.append(f"VLM: Checked {len(frames)} frames")
    except ImportError:
        pass

    passed = score >= 60 and exit_code == 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }