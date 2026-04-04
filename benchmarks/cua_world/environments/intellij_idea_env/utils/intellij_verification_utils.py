#!/usr/bin/env python3
"""Shared verification utilities for IntelliJ IDEA environment tasks."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def copy_and_read_text(copy_from_env, remote_path):
    """Copy a text file from the environment and return its contents.

    Args:
        copy_from_env: The copy function from env_info
        remote_path: Path inside the VM to copy from

    Returns:
        String contents of the file, or None if not found
    """
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
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
        return None


def copy_and_read_binary(copy_from_env, remote_path):
    """Copy a binary file from the environment and return its bytes.

    Args:
        copy_from_env: The copy function from env_info
        remote_path: Path inside the VM to copy from

    Returns:
        Bytes contents of the file, or None if not found
    """
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
        tmp.close()
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, 'rb') as f:
            content = f.read()
        os.unlink(tmp.name)
        return content
    except Exception as e:
        logger.debug(f"Failed to read {remote_path}: {e}")
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
        return None


def verify_java_class_file(copy_from_env, class_path):
    """Verify a .class file exists and has valid Java magic bytes.

    Args:
        copy_from_env: The copy function from env_info
        class_path: Path to the .class file inside the VM

    Returns:
        True if the file is a valid Java class file
    """
    content = copy_and_read_binary(copy_from_env, class_path)
    if content and len(content) >= 4:
        return content[:4] == b'\xca\xfe\xba\xbe'
    return False


def read_json_result(copy_from_env, result_path="/tmp/task_result.json"):
    """Read and parse the task result JSON from the VM.

    Args:
        copy_from_env: The copy function from env_info
        result_path: Path to the result JSON file inside the VM

    Returns:
        Parsed dict, or None if not found/invalid
    """
    content = copy_and_read_text(copy_from_env, result_path)
    if content:
        try:
            return json.loads(content)
        except json.JSONDecodeError as e:
            logger.warning(f"Invalid JSON in {result_path}: {e}")
    return None


def vlm_verify_intellij_task(traj, env_info, task_description, checklist_items):
    """Perform VLM-based verification of an IntelliJ IDEA task using trajectory frames.

    Uses trajectory frames (not just the final screenshot) for robust verification
    following the vlm_checklist_patterns.md guidelines.

    Args:
        traj: Trajectory dict with frames and screenshots
        env_info: Environment info dict (contains query_vlm, copy_from_env)
        task_description: Human-readable description of the task
        checklist_items: List of strings describing what to check in the trajectory

    Returns:
        Dict with keys: vlm_score (int 0-100), vlm_feedback (str), vlm_passed (bool)
        Returns None if VLM is not available.
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return None

    try:
        # Import trajectory helpers
        from gym_anything.vlm import (
            sample_trajectory_frames,
            get_final_screenshot,
            get_first_screenshot,
        )

        # Collect frames: first + sampled mid-trajectory + last
        frames = []
        first = get_first_screenshot(traj)
        if first:
            frames.append(first)

        mid_frames = sample_trajectory_frames(traj, num_samples=4,
                                               include_first=False,
                                               include_last=False)
        frames.extend(mid_frames)

        last = get_final_screenshot(traj)
        if last and last not in frames:
            frames.append(last)

        # Also try to get task end screenshot from VM
        copy_from_env = env_info.get('copy_from_env')
        if copy_from_env and not frames:
            try:
                tmp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                tmp_ss.close()
                copy_from_env("/tmp/task_end.png", tmp_ss.name)
                if os.path.exists(tmp_ss.name) and os.path.getsize(tmp_ss.name) > 0:
                    frames.append(tmp_ss.name)
            except Exception:
                pass

        if not frames:
            return {"vlm_score": 0, "vlm_feedback": "No trajectory frames available", "vlm_passed": False}

        # Build the VLM prompt
        checklist_str = "\n".join(f"  {i+1}. {item}" for i, item in enumerate(checklist_items))
        n_frames = len(frames)

        prompt = f"""You are verifying whether a GUI agent completed a task in IntelliJ IDEA.

Task: {task_description}

You are shown {n_frames} screenshots from the agent's trajectory:
- Image 1: Initial state
- Images 2-{n_frames-1}: Sampled during the agent's work
- Image {n_frames}: Final state

Checklist to verify:
{checklist_str}

For each checklist item, respond YES or NO.
Then provide an overall score from 0 to 100 based on how many items were satisfied.

Respond in this exact JSON format:
{{
  "items": [
    {{"item": "<item description>", "passed": true/false, "evidence": "<what you see>"}}
  ],
  "overall_score": <0-100>,
  "summary": "<brief summary>"
}}"""

        vlm_result = query_vlm(prompt=prompt, images=frames)

        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            vlm_score = parsed.get('overall_score', 0)
            summary = parsed.get('summary', vlm_result.get('response', '')[:200])
            items = parsed.get('items', [])
            passed_count = sum(1 for item in items if item.get('passed'))
            total_count = len(items) if items else len(checklist_items)

            return {
                "vlm_score": int(vlm_score) if isinstance(vlm_score, (int, float)) else 0,
                "vlm_feedback": f"VLM: {passed_count}/{total_count} checks passed. {summary}",
                "vlm_passed": passed_count >= total_count * 0.6,
                "vlm_items": items,
            }
        else:
            error = vlm_result.get('error', 'Unknown error') if vlm_result else 'VLM returned None'
            return {"vlm_score": 0, "vlm_feedback": f"VLM query failed: {error}", "vlm_passed": False}

    except ImportError:
        logger.warning("gym_anything.vlm not available, skipping VLM verification")
        return {"vlm_score": 0, "vlm_feedback": "VLM module not available", "vlm_passed": False}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"vlm_score": 0, "vlm_feedback": f"VLM error: {e}", "vlm_passed": False}
