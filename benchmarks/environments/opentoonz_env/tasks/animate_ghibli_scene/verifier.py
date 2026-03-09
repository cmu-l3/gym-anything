#!/usr/bin/env python3
"""
Verifier for animate_ghibli_scene task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Agent output exists and is valid video/frames (15 points)
2. Output was created during task (10 points)
3. Output has reasonable size/frame count (10 points)
4. Agent output has MOTION (anti-static hack) (20 points)
5. Motion pattern similarity to reference (15 points)
6. Visual similarity to reference frames (15 points)
7. VLM: Animation quality assessment (15 points)

Pass threshold: 55% AND key criteria (output created + has motion + passes VLM check)
"""

import json
import tempfile
import os
import logging
import subprocess
import numpy as np
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_frames_from_video(video_path, output_dir, max_frames=30):
    """Extract frames from video for analysis."""
    try:
        os.makedirs(output_dir, exist_ok=True)
        cmd = [
            'ffmpeg', '-y', '-i', video_path,
            '-vf', f'fps=10,scale=480:-1',  # 10fps, scaled down for speed
            '-vframes', str(max_frames),
            f'{output_dir}/frame_%04d.png'
        ]
        subprocess.run(cmd, capture_output=True, timeout=60)

        frames = sorted(Path(output_dir).glob('frame_*.png'))
        return [str(f) for f in frames]
    except Exception as e:
        logger.error(f"Frame extraction failed: {e}")
        return []


def compute_motion_score(frames):
    """
    Compute motion score by analyzing frame differences.
    Returns score 0-1 where higher = more motion.
    """
    try:
        from PIL import Image

        if len(frames) < 2:
            return 0.0

        total_diff = 0
        comparisons = 0

        # Compare consecutive frames
        for i in range(min(len(frames) - 1, 20)):  # Max 20 comparisons
            img1 = np.array(Image.open(frames[i]).convert('L'))
            img2 = np.array(Image.open(frames[i + 1]).convert('L'))

            # Ensure same size
            if img1.shape != img2.shape:
                continue

            # Calculate absolute difference
            diff = np.abs(img1.astype(float) - img2.astype(float))
            avg_diff = np.mean(diff)
            total_diff += avg_diff
            comparisons += 1

        if comparisons == 0:
            return 0.0

        avg_motion = total_diff / comparisons

        # Normalize: 0-5 diff = static, >20 diff = lots of motion
        motion_score = min(1.0, max(0.0, (avg_motion - 2) / 20))

        return motion_score

    except Exception as e:
        logger.error(f"Motion computation failed: {e}")
        return 0.0


def compute_visual_similarity(agent_frames, reference_frames):
    """
    Compute visual similarity between agent and reference animations.
    Uses SSIM-like comparison.
    """
    try:
        from PIL import Image

        if not agent_frames or not reference_frames:
            return 0.0

        similarities = []

        # Compare corresponding frames (or sample if different lengths)
        n_compare = min(len(agent_frames), len(reference_frames), 10)

        for i in range(n_compare):
            agent_idx = int(i * len(agent_frames) / n_compare)
            ref_idx = int(i * len(reference_frames) / n_compare)

            agent_img = np.array(Image.open(agent_frames[agent_idx]).convert('RGB'))
            ref_img = np.array(Image.open(reference_frames[ref_idx]).convert('RGB'))

            # Resize to same dimensions
            target_size = (min(agent_img.shape[1], ref_img.shape[1]),
                          min(agent_img.shape[0], ref_img.shape[0]))

            agent_img = np.array(Image.fromarray(agent_img).resize(target_size))
            ref_img = np.array(Image.fromarray(ref_img).resize(target_size))

            # Compute normalized cross-correlation (simple similarity)
            agent_norm = (agent_img - agent_img.mean()) / (agent_img.std() + 1e-6)
            ref_norm = (ref_img - ref_img.mean()) / (ref_img.std() + 1e-6)

            similarity = np.mean(agent_norm * ref_norm)
            similarity = max(0, min(1, (similarity + 1) / 2))  # Normalize to 0-1

            similarities.append(similarity)

        return np.mean(similarities) if similarities else 0.0

    except Exception as e:
        logger.error(f"Visual similarity failed: {e}")
        return 0.0


def compute_motion_similarity(agent_frames, reference_frames):
    """
    Compare motion patterns between agent and reference.
    Checks if motion direction and magnitude are similar.
    """
    try:
        from PIL import Image

        def get_motion_vector(frames):
            """Extract average motion direction from frames."""
            if len(frames) < 3:
                return np.zeros(2)

            motions = []
            for i in range(min(len(frames) - 1, 10)):
                img1 = np.array(Image.open(frames[i]).convert('L')).astype(float)
                img2 = np.array(Image.open(frames[i + 1]).convert('L')).astype(float)

                if img1.shape != img2.shape:
                    continue

                # Simple optical flow approximation using gradient
                dy = np.gradient(img2 - img1, axis=0)
                dx = np.gradient(img2 - img1, axis=1)

                avg_motion = np.array([np.mean(dx), np.mean(dy)])
                motions.append(avg_motion)

            return np.mean(motions, axis=0) if motions else np.zeros(2)

        agent_motion = get_motion_vector(agent_frames)
        ref_motion = get_motion_vector(reference_frames)

        # Compute motion magnitude similarity
        agent_mag = np.linalg.norm(agent_motion)
        ref_mag = np.linalg.norm(ref_motion)

        if ref_mag < 0.1:  # Reference has very little motion
            mag_similarity = 1.0 if agent_mag < 0.5 else 0.5
        else:
            mag_ratio = min(agent_mag, ref_mag) / max(agent_mag, ref_mag, 0.01)
            mag_similarity = mag_ratio

        # Compute motion direction similarity (if both have significant motion)
        if agent_mag > 0.1 and ref_mag > 0.1:
            agent_dir = agent_motion / agent_mag
            ref_dir = ref_motion / ref_mag
            direction_similarity = (np.dot(agent_dir, ref_dir) + 1) / 2
        else:
            direction_similarity = 0.5

        # Combined score
        motion_similarity = 0.6 * mag_similarity + 0.4 * direction_similarity

        return motion_similarity

    except Exception as e:
        logger.error(f"Motion similarity failed: {e}")
        return 0.0


def verify_animate_ghibli_scene(traj, env_info, task_info):
    """
    Multi-signal verification for Ghibli animation task.

    Uses multiple independent signals to verify the agent created
    a genuine animation that matches the reference.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_output_size_kb = metadata.get('min_output_size_kb', 50)
    min_motion_score = metadata.get('min_motion_score', 0.3)
    min_visual_similarity = metadata.get('min_visual_similarity', 0.5)

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ================================================================
    # CRITERION 1: Agent output exists (15 points)
    # ================================================================
    agent_video_found = result.get('agent_video_found', False)
    agent_frame_count = result.get('agent_frame_count', 0)

    if agent_video_found and agent_frame_count >= 10:
        score += 15
        feedback_parts.append(f"Output found ({agent_frame_count} frames)")
    elif agent_video_found:
        score += 8
        feedback_parts.append(f"Output found (low frame count: {agent_frame_count})")
    else:
        feedback_parts.append("No animation output found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"reason": "No output created"}
        }

    # ================================================================
    # CRITERION 2: Output created during task (10 points)
    # ================================================================
    initial_count = result.get('initial_output_count', 0)
    current_count = result.get('current_output_count', 0)

    if current_count > initial_count:
        score += 10
        feedback_parts.append("New output created")
    else:
        feedback_parts.append("Output may have existed before task")

    # ================================================================
    # CRITERION 3: Output size reasonable (10 points)
    # ================================================================
    output_size_kb = result.get('agent_video_size_kb', 0)

    if output_size_kb >= 500:  # Good quality animation
        score += 10
        feedback_parts.append(f"Good size ({output_size_kb}KB)")
    elif output_size_kb >= min_output_size_kb:
        score += 7
        feedback_parts.append(f"Acceptable size ({output_size_kb}KB)")
    elif output_size_kb >= 10:
        score += 3
        feedback_parts.append(f"Small output ({output_size_kb}KB)")
    else:
        feedback_parts.append(f"Output too small ({output_size_kb}KB)")

    # ================================================================
    # CRITERION 4: Has MOTION - anti-static hack (20 points)
    # ================================================================
    has_motion = result.get('has_motion', False)
    export_motion_score = float(result.get('motion_score', 0))

    # Also verify motion ourselves by extracting frames
    agent_frames = []
    reference_frames = []

    with tempfile.TemporaryDirectory() as temp_dir:
        # Try to copy and analyze agent video
        try:
            agent_video_local = f"{temp_dir}/agent.mp4"
            copy_from_env("/tmp/agent_animation.mp4", agent_video_local)
            agent_frames = extract_frames_from_video(
                agent_video_local, f"{temp_dir}/agent_frames", max_frames=30
            )
        except Exception as e:
            logger.warning(f"Could not copy agent video: {e}")

        # Try to copy and analyze reference video
        try:
            ref_video_local = f"{temp_dir}/reference.mp4"
            copy_from_env("/tmp/reference_animation.mp4", ref_video_local)
            reference_frames = extract_frames_from_video(
                ref_video_local, f"{temp_dir}/ref_frames", max_frames=30
            )
        except Exception as e:
            logger.warning(f"Could not copy reference video: {e}")

        # Compute motion score from extracted frames
        computed_motion_score = 0.0
        if agent_frames:
            computed_motion_score = compute_motion_score(agent_frames)

        # Use max of export and computed scores
        final_motion_score = max(export_motion_score, computed_motion_score)

        if final_motion_score >= min_motion_score:
            score += 20
            has_motion = True
            feedback_parts.append(f"Good motion (score: {final_motion_score:.2f})")
        elif final_motion_score > 0.1:
            score += 10
            has_motion = True
            feedback_parts.append(f"Some motion (score: {final_motion_score:.2f})")
        elif has_motion:
            score += 5
            feedback_parts.append("Minimal motion detected")
        else:
            feedback_parts.append("FAIL: No animation - output is static")

        # ================================================================
        # CRITERION 5: Motion pattern similarity (15 points)
        # ================================================================
        motion_similarity = 0.0
        if agent_frames and reference_frames:
            motion_similarity = compute_motion_similarity(agent_frames, reference_frames)

            if motion_similarity >= 0.7:
                score += 15
                feedback_parts.append(f"Motion matches reference ({motion_similarity:.2f})")
            elif motion_similarity >= 0.5:
                score += 10
                feedback_parts.append(f"Partial motion match ({motion_similarity:.2f})")
            elif motion_similarity >= 0.3:
                score += 5
                feedback_parts.append(f"Low motion match ({motion_similarity:.2f})")
            else:
                feedback_parts.append(f"Motion doesn't match reference ({motion_similarity:.2f})")
        else:
            feedback_parts.append("Could not compare motion patterns")

        # ================================================================
        # CRITERION 6: Visual similarity (15 points)
        # ================================================================
        visual_similarity = 0.0
        if agent_frames and reference_frames:
            visual_similarity = compute_visual_similarity(agent_frames, reference_frames)

            if visual_similarity >= 0.7:
                score += 15
                feedback_parts.append(f"Visually similar ({visual_similarity:.2f})")
            elif visual_similarity >= min_visual_similarity:
                score += 10
                feedback_parts.append(f"Partial visual match ({visual_similarity:.2f})")
            elif visual_similarity >= 0.3:
                score += 5
                feedback_parts.append(f"Low visual match ({visual_similarity:.2f})")
            else:
                feedback_parts.append(f"Visually different ({visual_similarity:.2f})")
        else:
            feedback_parts.append("Could not compare visuals")

    # ================================================================
    # CRITERION 7: VLM verification (15 points)
    # ================================================================
    vlm_passed = False
    vlm_score = 0

    if query_vlm and agent_frames:
        try:
            # Use middle frame for VLM analysis
            middle_frame = agent_frames[len(agent_frames) // 2]

            vlm_result = query_vlm(
                image=middle_frame,
                prompt="""Analyze this frame from an animation:

1. Does this appear to be from a Studio Ghibli-style scene?
2. Can you see signs of animation effects (particles, motion blur, lighting effects)?
3. Does the image have artistic quality (not just a static photo)?
4. Rate the overall animation quality from 1-10.

Respond with: {ghibli_style: yes/no, has_effects: yes/no, artistic: yes/no, quality: N}
"""
            )

            vlm_text = str(vlm_result).lower() if vlm_result else ""

            # Parse VLM response
            has_ghibli_style = 'yes' in vlm_text and any(
                w in vlm_text for w in ['ghibli', 'anime', 'artistic', 'illustrated']
            )
            has_effects = 'yes' in vlm_text and any(
                w in vlm_text for w in ['particle', 'effect', 'motion', 'animation']
            )

            # Extract quality score
            import re
            quality_match = re.search(r'quality[:\s]*(\d+)', vlm_text)
            quality_score = int(quality_match.group(1)) if quality_match else 5

            if has_ghibli_style and has_effects and quality_score >= 6:
                vlm_score = 15
                vlm_passed = True
                feedback_parts.append(f"VLM: High quality animation (quality={quality_score})")
            elif has_effects or quality_score >= 5:
                vlm_score = 10
                vlm_passed = True
                feedback_parts.append(f"VLM: Acceptable animation (quality={quality_score})")
            elif quality_score >= 3:
                vlm_score = 5
                feedback_parts.append(f"VLM: Low quality (quality={quality_score})")
            else:
                feedback_parts.append("VLM: Failed quality check")

            score += vlm_score

        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM check skipped")
            # Give partial credit if other criteria are met
            if has_motion and visual_similarity >= 0.5:
                score += 7
                vlm_passed = True
    else:
        feedback_parts.append("VLM not available")
        # Fallback: give partial credit based on other metrics
        if has_motion and final_motion_score >= 0.3:
            score += 8
            vlm_passed = True

    # ================================================================
    # NEGATIVE CHECKS
    # ================================================================
    if not has_motion:
        feedback_parts.append("CRITICAL FAIL: Animation has no motion")
        score = min(score, 25)

    if output_size_kb < 10:
        feedback_parts.append("CRITICAL FAIL: Output suspiciously small")
        score = min(score, 20)

    # ================================================================
    # FINAL RESULT
    # ================================================================
    # Key criteria: output created + has motion + (VLM passed OR good visual similarity)
    key_criteria_met = (
        agent_video_found and
        has_motion and
        (vlm_passed or visual_similarity >= min_visual_similarity)
    )

    # Pass threshold: 55% AND key criteria
    passed = score >= 55 and key_criteria_met

    if passed and score >= 80:
        feedback_parts.append("Excellent animation!")
    elif passed:
        feedback_parts.append("Animation successful")
    else:
        if not key_criteria_met:
            feedback_parts.append("FAIL: Key criteria not met")
        else:
            feedback_parts.append(f"FAIL: Score {score}/100 below threshold")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "agent_video_found": agent_video_found,
            "agent_frame_count": agent_frame_count,
            "output_size_kb": output_size_kb,
            "has_motion": has_motion,
            "motion_score": final_motion_score if 'final_motion_score' in dir() else export_motion_score,
            "motion_similarity": motion_similarity if 'motion_similarity' in dir() else 0,
            "visual_similarity": visual_similarity if 'visual_similarity' in dir() else 0,
            "vlm_passed": vlm_passed,
            "vlm_score": vlm_score,
            "key_criteria_met": key_criteria_met
        }
    }
