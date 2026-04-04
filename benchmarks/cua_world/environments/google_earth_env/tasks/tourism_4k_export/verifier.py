#!/usr/bin/env python3
"""
Verifier for tourism_4k_export task.

VERIFICATION STRATEGY:
This task requires exporting a 4K image of Bora Bora with specific settings.

PROGRAMMATIC CHECKS (55 points max):
1. Output file exists at correct path (15 points)
2. File was created DURING task execution (10 points) - anti-gaming
3. Correct resolution: exactly 3840x2160 (25 points)
4. Reasonable file size >500KB (5 points)

VLM VERIFICATION (45 points max):
5. Geographic content: shows Bora Bora lagoon (20 points)
6. Title "Bora Bora Paradise" visible (15 points)
7. Scale legend visible (10 points)

TRAJECTORY VERIFICATION:
- Uses multiple trajectory frames to verify workflow progression
- Confirms agent navigated to Bora Bora and used Save Image dialog

Pass threshold: 70 points with file created during task + correct resolution
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent completing a Google Earth export task.

TASK: Navigate to Bora Bora, French Polynesia and export a 4K image with title "Bora Bora Paradise".

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful completion, the agent should:
1. Have Google Earth open
2. Navigate to Bora Bora (search or manual navigation)
3. View the turquoise lagoon and volcanic peaks
4. Open the Save Image dialog (File > Save > Save Image)
5. Configure resolution, title, and export settings

Assess:
1. GOOGLE_EARTH_USED: Is Google Earth visible in any frame?
2. BORA_BORA_NAVIGATION: Did the agent navigate to a tropical island/lagoon area?
3. SAVE_DIALOG_OPENED: Is a Save Image or export dialog visible in any frame?
4. WORKFLOW_PROGRESSION: Do frames show meaningful state changes (not stuck on same screen)?

Respond in JSON format:
{
    "google_earth_used": true/false,
    "bora_bora_navigation": true/false,
    "save_dialog_opened": true/false,
    "workflow_progression": true/false,
    "stages_observed": ["list what you see in the frames"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

EXPORTED_IMAGE_VERIFICATION_PROMPT = """You are verifying an exported Google Earth image for a tourism marketing campaign.

REQUIREMENTS:
- Location: Bora Bora, French Polynesia (tropical lagoon with turquoise water)
- Title: "Bora Bora Paradise" should appear on the image
- Scale legend: A distance scale bar should be visible

Analyze this exported image and check:

1. SHOWS_BORA_BORA: Does this show Bora Bora or a similar tropical lagoon? Look for:
   - Turquoise/aquamarine lagoon water (distinctive bright blue-green color)
   - Volcanic mountain peak(s) (dark/green mountains)
   - Coral reef ring or atoll structure
   - Tropical island terrain
   - Aerial/satellite view perspective

2. TITLE_VISIBLE: Is the text "Bora Bora Paradise" visible anywhere on the image?
   (Usually appears at top or as an overlay)

3. SCALE_LEGEND_VISIBLE: Is there a scale bar or distance legend visible?
   (Usually appears at bottom of Google Earth exports)

4. IMAGE_QUALITY: Is the image properly rendered (not showing loading spinners, error messages, or empty areas)?

Respond in JSON format:
{
    "shows_bora_bora": true/false,
    "shows_tropical_lagoon": true/false,
    "title_visible": true/false,
    "title_text_observed": "what title text you can see, or null",
    "scale_legend_visible": true/false,
    "image_quality_good": true/false,
    "confidence": "low"/"medium"/"high",
    "visual_description": "brief description of what the image shows"
}
"""


def verify_tourism_4k_export(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a 4K tourism image of Bora Bora was exported correctly.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    1. Programmatic file checks (existence, timestamp, resolution)
    2. VLM verification of exported image content
    3. VLM verification of trajectory (workflow progression)
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 3840)
    expected_height = metadata.get('expected_height', 2160)
    min_file_size_kb = metadata.get('min_file_size_kb', 500)
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/bora_bora_4k.jpg')
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    image_format = result.get('image_format', 'unknown')
    
    if output_exists:
        score += 15
        feedback_parts.append(f"✅ Output file exists ({image_format})")
        logger.info("Output file exists")
    else:
        feedback_parts.append("❌ Output file NOT found")
        logger.info("Output file not found - early exit")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
        logger.info("File timestamp verified - created during task")
    else:
        feedback_parts.append("⚠️ File may have existed before task (timestamp check failed)")
        logger.warning("File timestamp check failed - possible gaming")
    
    # ================================================================
    # CRITERION 3: Correct resolution 3840x2160 (25 points)
    # ================================================================
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    
    if image_width == expected_width and image_height == expected_height:
        score += 25
        feedback_parts.append(f"✅ Correct resolution: {image_width}x{image_height}")
        logger.info(f"Resolution correct: {image_width}x{image_height}")
    elif image_width > 0 and image_height > 0:
        # Partial credit for having an image with different resolution
        score += 5
        feedback_parts.append(f"⚠️ Wrong resolution: {image_width}x{image_height} (expected {expected_width}x{expected_height})")
        logger.info(f"Resolution incorrect: {image_width}x{image_height}")
    else:
        feedback_parts.append("❌ Could not read image dimensions")
    
    # ================================================================
    # CRITERION 4: Reasonable file size (5 points)
    # ================================================================
    file_size_bytes = result.get('output_size_bytes', 0)
    file_size_kb = file_size_bytes / 1024
    
    if file_size_kb >= min_file_size_kb:
        score += 5
        feedback_parts.append(f"✅ Good file size: {file_size_kb:.1f} KB")
    elif file_size_kb >= 100:
        score += 2
        feedback_parts.append(f"⚠️ Small file size: {file_size_kb:.1f} KB")
    else:
        feedback_parts.append(f"❌ File too small: {file_size_kb:.1f} KB")
    
    logger.info(f"Programmatic score: {score}/55")
    
    # ================================================================
    # VLM VERIFICATION (if available)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        # Copy the exported image for VLM analysis
        temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        exported_image_available = False
        
        try:
            copy_from_env(expected_output_path, temp_image.name)
            # Verify the file was copied successfully
            if os.path.exists(temp_image.name) and os.path.getsize(temp_image.name) > 0:
                exported_image_available = True
                result_details['exported_image_path'] = temp_image.name
        except Exception as e:
            logger.warning(f"Could not copy exported image: {e}")
        
        # ================================================================
        # CRITERION 5: Geographic content - Bora Bora visible (20 points)
        # CRITERION 6: Title visible (15 points)
        # CRITERION 7: Scale legend visible (10 points)
        # ================================================================
        if exported_image_available:
            logger.info("Running VLM verification on exported image...")
            
            try:
                vlm_result = query_vlm(
                    prompt=EXPORTED_IMAGE_VERIFICATION_PROMPT,
                    image=temp_image.name
                )
                result_details['vlm_image_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    # Check geographic content
                    shows_bora_bora = parsed.get('shows_bora_bora', False)
                    shows_tropical = parsed.get('shows_tropical_lagoon', False)
                    
                    if shows_bora_bora:
                        vlm_score += 20
                        feedback_parts.append("✅ VLM confirms Bora Bora lagoon visible")
                    elif shows_tropical:
                        vlm_score += 10
                        feedback_parts.append("⚠️ VLM sees tropical lagoon (may not be Bora Bora)")
                    else:
                        feedback_parts.append("❌ VLM could not confirm Bora Bora content")
                    
                    # Check title
                    title_visible = parsed.get('title_visible', False)
                    if title_visible:
                        vlm_score += 15
                        observed_title = parsed.get('title_text_observed', 'unknown')
                        feedback_parts.append(f"✅ VLM confirms title visible: {observed_title}")
                    else:
                        feedback_parts.append("❌ VLM could not find title text")
                    
                    # Check scale legend
                    scale_visible = parsed.get('scale_legend_visible', False)
                    if scale_visible:
                        vlm_score += 10
                        feedback_parts.append("✅ VLM confirms scale legend visible")
                    else:
                        feedback_parts.append("❌ VLM could not find scale legend")
                    
                    confidence = parsed.get('confidence', 'low')
                    result_details['vlm_confidence'] = confidence
                else:
                    feedback_parts.append(f"⚠️ VLM image analysis failed: {vlm_result.get('error', 'unknown')}")
                    
            except Exception as e:
                logger.warning(f"VLM image verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM image verification error: {e}")
        
        # Clean up temp image
        if os.path.exists(temp_image.name):
            os.unlink(temp_image.name)
        
        # ================================================================
        # TRAJECTORY VERIFICATION (bonus confidence check)
        # ================================================================
        try:
            # Get trajectory frames
            frames = traj.get('frames', [])
            if frames and len(frames) >= 3:
                # Sample frames from trajectory
                n_frames = min(5, len(frames))
                step = max(1, len(frames) // n_frames)
                sampled_frames = [frames[i] for i in range(0, len(frames), step)][:n_frames]
                
                # Get frame paths
                episode_dir = traj.get('episode_dir', '')
                frame_paths = []
                for frame in sampled_frames:
                    if isinstance(frame, dict):
                        frame_path = frame.get('path', '')
                    else:
                        frame_path = str(frame)
                    
                    if frame_path and os.path.exists(frame_path):
                        frame_paths.append(frame_path)
                    elif episode_dir and frame_path:
                        full_path = os.path.join(episode_dir, frame_path)
                        if os.path.exists(full_path):
                            frame_paths.append(full_path)
                
                if frame_paths:
                    logger.info(f"Running trajectory verification on {len(frame_paths)} frames...")
                    traj_result = query_vlm(
                        prompt=TRAJECTORY_VERIFICATION_PROMPT,
                        images=frame_paths
                    )
                    result_details['vlm_trajectory_result'] = traj_result
                    
                    if traj_result.get('success'):
                        traj_parsed = traj_result.get('parsed', {})
                        
                        # Boost confidence if trajectory shows proper workflow
                        if traj_parsed.get('google_earth_used') and traj_parsed.get('workflow_progression'):
                            feedback_parts.append("✅ Trajectory confirms Google Earth workflow")
                            result_details['trajectory_verified'] = True
                        
                        if traj_parsed.get('save_dialog_opened'):
                            feedback_parts.append("✅ Trajectory shows Save dialog interaction")
        except Exception as e:
            logger.warning(f"Trajectory verification failed: {e}")
    else:
        feedback_parts.append("⚠️ VLM not available - visual verification skipped")
    
    # ================================================================
    # CALCULATE FINAL SCORE AND PASS/FAIL
    # ================================================================
    total_score = score + vlm_score
    result_details['programmatic_score'] = score
    result_details['vlm_score'] = vlm_score
    result_details['total_score'] = total_score
    
    # Pass criteria:
    # - Score >= 70 points
    # - File was created during task (anti-gaming)
    # - Correct resolution achieved
    correct_resolution = (image_width == expected_width and image_height == expected_height)
    key_criteria_met = file_created_during_task and correct_resolution and output_exists
    
    passed = total_score >= 70 and key_criteria_met
    
    # Generate summary feedback
    summary = f"Score: {total_score}/100 (Programmatic: {score}/55, VLM: {vlm_score}/45)"
    if passed:
        summary = f"✅ PASSED - {summary}"
    else:
        if not key_criteria_met:
            summary = f"❌ FAILED (key criteria not met) - {summary}"
        else:
            summary = f"❌ FAILED (score below threshold) - {summary}"
    
    feedback_parts.insert(0, summary)
    
    logger.info(f"Final result: passed={passed}, score={total_score}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }