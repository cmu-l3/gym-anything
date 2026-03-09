#!/usr/bin/env python3
"""
Verifier for coastal_flythrough_export task.

VERIFICATION STRATEGY:
1. Output file exists at correct path (15 points)
2. File created during task - anti-gaming (15 points)
3. Valid video format/playable (15 points)
4. Resolution meets requirements (15 points)
5. Duration in acceptable range (15 points)
6. VLM: Aerial/satellite view perspective (15 points)
7. VLM: Coastal geography visible (15 points)
8. VLM: Identifiable as Amalfi Coast region (10 points - bonus)

Uses trajectory frames for VLM verification to prevent gaming.
Pass threshold: 60 points with key criteria met.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# VLM PROMPTS
# =============================================================================

# Process verification using trajectory frames
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing screenshots from an agent creating a flythrough video in Google Earth Pro.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful flythrough video creation, the agent should progress through these stages:
1. Google Earth Pro is open showing the globe/map
2. Navigation to Amalfi Coast, Italy (Mediterranean coastal area)
3. Path creation along the coastline (visible path line on the map)
4. Movie Maker tool opened (dialog or recording interface)
5. Video export/save operation

Assess what you can observe in the sequence:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro interface visible at any point?
2. ITALY_REGION_VISIBLE: Do any frames show Italy or Mediterranean coastal region?
3. PATH_CREATION: Do you see evidence of a path being drawn or existing?
4. MOVIE_MAKER_USED: Is there any dialog, progress bar, or recording interface visible?
5. MEANINGFUL_WORKFLOW: Do the frames show progression through different stages?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "italy_region_visible": true/false,
    "path_creation_evidence": true/false,
    "movie_maker_evidence": true/false,
    "meaningful_workflow": true/false,
    "stages_observed": ["list stages you identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

# Content verification for extracted video frames
VIDEO_CONTENT_PROMPT = """You are verifying frames extracted from a flythrough video created in Google Earth Pro.

These frames should show an aerial flythrough of the Amalfi Coast, Italy.

Expected characteristics:
- Aerial/satellite perspective (looking down at terrain, not street-level)
- Coastal geography (water/sea meeting land with cliffs)
- Mediterranean region features (blue water, terraced hillsides, clustered villages)
- The Amalfi Coast specifically: dramatic cliffs, winding coastal road, villages like Positano/Amalfi

Assess the following:
1. AERIAL_PERSPECTIVE: Do these frames show an aerial/bird's eye view (not street-level)?
2. COASTAL_GEOGRAPHY: Is there a coastline visible (water meeting land)?
3. REAL_TERRAIN: Does this look like real satellite/aerial imagery (not just UI or blank)?
4. AMALFI_FEATURES: Are there features consistent with the Amalfi Coast?
   - Dramatic coastal cliffs
   - Blue Mediterranean water
   - Terraced hillsides with buildings
   - Winding coastal road

Respond in JSON format:
{
    "aerial_perspective": true/false,
    "coastal_geography": true/false,
    "real_terrain_imagery": true/false,
    "amalfi_coast_features": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "describe what you see in the frames"
}
"""


def _query_vlm_safe(query_vlm, prompt: str, image: Optional[str] = None, 
                    images: Optional[List[str]] = None) -> Optional[Dict]:
    """Safely query VLM with error handling."""
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    
    if not image and not images:
        logger.warning("No images provided for VLM query")
        return None
    
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        else:
            logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
            return None
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
        return None


def verify_coastal_flythrough_export(traj: Dict[str, Any], env_info: Dict[str, Any], 
                                      task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the coastal flythrough video export task.
    
    Uses multi-signal verification:
    - Programmatic checks on video file
    - Trajectory analysis via VLM
    - Video content analysis via VLM
    
    Args:
        traj: Trajectory data with frames captured during task
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Videos/amalfi_flythrough.mp4')
    min_width = metadata.get('min_resolution_width', 1280)
    min_height = metadata.get('min_resolution_height', 720)
    min_duration = metadata.get('duration_min_seconds', 10)
    max_duration = metadata.get('duration_max_seconds', 30)
    min_file_size = metadata.get('min_file_size_bytes', 500000)
    
    feedback_parts = []
    result_details = {}
    score = 0
    
    # =================================================================
    # STEP 1: Copy and parse result file from container
    # =================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # =================================================================
    # CRITERION 1: Output file exists (15 points)
    # =================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Video file exists at expected path")
    else:
        feedback_parts.append("❌ Video file NOT found at /home/ga/Videos/amalfi_flythrough.mp4")
        # Early return if no file - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # =================================================================
    # CRITERION 2: File created during task - anti-gaming (15 points)
    # =================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task (anti-gaming passed)")
    else:
        feedback_parts.append("⚠️ File may predate task start")
        result_details['anti_gaming_warning'] = True
    
    # =================================================================
    # CRITERION 3: Valid video format (15 points)
    # =================================================================
    video_format = result.get('video_format', 'unknown')
    video_codec = result.get('video_codec', 'unknown')
    file_size = result.get('output_size_bytes', 0)
    
    is_valid_format = ('mp4' in str(video_format).lower() or 
                       'mov' in str(video_format).lower() or
                       'mpeg' in str(video_format).lower())
    
    if is_valid_format and file_size >= min_file_size:
        score += 15
        feedback_parts.append(f"✅ Valid video format ({video_format}, {video_codec})")
    elif is_valid_format:
        score += 10
        feedback_parts.append(f"⚠️ Valid format but small file ({file_size} bytes)")
    elif file_size >= min_file_size:
        score += 8
        feedback_parts.append(f"⚠️ Good file size but format unclear ({video_format})")
    else:
        feedback_parts.append(f"❌ Invalid format or file too small ({video_format}, {file_size} bytes)")
    
    # =================================================================
    # CRITERION 4: Resolution meets requirements (15 points)
    # =================================================================
    video_width = result.get('video_width', 0)
    video_height = result.get('video_height', 0)
    
    try:
        video_width = int(video_width) if video_width else 0
        video_height = int(video_height) if video_height else 0
    except (ValueError, TypeError):
        video_width = 0
        video_height = 0
    
    if video_width >= min_width and video_height >= min_height:
        score += 15
        feedback_parts.append(f"✅ Resolution {video_width}x{video_height} meets requirements")
    elif video_width >= min_width * 0.75 and video_height >= min_height * 0.75:
        score += 10
        feedback_parts.append(f"⚠️ Resolution {video_width}x{video_height} slightly below target")
    elif video_width > 0 and video_height > 0:
        score += 5
        feedback_parts.append(f"⚠️ Resolution {video_width}x{video_height} below requirements")
    else:
        feedback_parts.append("❌ Could not determine video resolution")
    
    # =================================================================
    # CRITERION 5: Duration in acceptable range (15 points)
    # =================================================================
    video_duration = result.get('video_duration', 0)
    
    try:
        video_duration = float(video_duration) if video_duration else 0
    except (ValueError, TypeError):
        video_duration = 0
    
    if min_duration <= video_duration <= max_duration:
        score += 15
        feedback_parts.append(f"✅ Duration {video_duration:.1f}s is in acceptable range")
    elif video_duration > 0 and video_duration < min_duration * 2:
        score += 8
        feedback_parts.append(f"⚠️ Duration {video_duration:.1f}s outside target range")
    elif video_duration > 0:
        score += 5
        feedback_parts.append(f"⚠️ Duration {video_duration:.1f}s far from target")
    else:
        feedback_parts.append("❌ Could not determine video duration")
    
    result_details['programmatic_score'] = score
    
    # =================================================================
    # VLM VERIFICATION - Using trajectory frames
    # =================================================================
    
    # Try to import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        has_vlm_utils = True
    except ImportError:
        has_vlm_utils = False
        logger.warning("Could not import VLM utilities")
    
    vlm_trajectory_score = 0
    vlm_content_score = 0
    
    if query_vlm and has_vlm_utils:
        # =============================================================
        # CRITERION 6 & 7: Trajectory-based VLM verification (30 points)
        # =============================================================
        
        # Sample trajectory frames
        try:
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            result_details['trajectory_frames_count'] = len(trajectory_frames) if trajectory_frames else 0
        except Exception as e:
            logger.warning(f"Failed to sample trajectory frames: {e}")
            trajectory_frames = []
        
        if trajectory_frames and len(trajectory_frames) >= 2:
            traj_vlm_result = _query_vlm_safe(
                query_vlm, 
                TRAJECTORY_VERIFICATION_PROMPT, 
                images=trajectory_frames
            )
            
            if traj_vlm_result:
                result_details['trajectory_vlm'] = traj_vlm_result
                
                ge_visible = traj_vlm_result.get('google_earth_visible', False)
                italy_visible = traj_vlm_result.get('italy_region_visible', False)
                path_evidence = traj_vlm_result.get('path_creation_evidence', False)
                movie_maker = traj_vlm_result.get('movie_maker_evidence', False)
                meaningful = traj_vlm_result.get('meaningful_workflow', False)
                
                # Score trajectory evidence
                traj_criteria = sum([ge_visible, italy_visible, path_evidence, 
                                    movie_maker, meaningful])
                
                if traj_criteria >= 4:
                    vlm_trajectory_score = 15
                    feedback_parts.append("✅ Trajectory shows complete workflow")
                elif traj_criteria >= 3:
                    vlm_trajectory_score = 12
                    feedback_parts.append("✅ Trajectory shows most workflow steps")
                elif traj_criteria >= 2:
                    vlm_trajectory_score = 8
                    feedback_parts.append("⚠️ Trajectory shows partial workflow")
                elif traj_criteria >= 1:
                    vlm_trajectory_score = 4
                    feedback_parts.append("⚠️ Trajectory shows limited evidence")
                else:
                    feedback_parts.append("❌ Trajectory doesn't show expected workflow")
        else:
            feedback_parts.append("⚠️ Insufficient trajectory frames for VLM analysis")
        
        # =============================================================
        # CRITERION 8: Video content VLM verification (15 points)
        # =============================================================
        
        # Copy extracted video frames from container
        video_frames = []
        frame_names = ['frame_start.png', 'frame_middle.png', 'frame_end.png']
        
        for frame_name in frame_names:
            temp_frame = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(f"/tmp/task_evidence/frames/{frame_name}", temp_frame.name)
                if os.path.exists(temp_frame.name) and os.path.getsize(temp_frame.name) > 1000:
                    video_frames.append(temp_frame.name)
            except Exception as e:
                logger.debug(f"Could not copy {frame_name}: {e}")
                if os.path.exists(temp_frame.name):
                    os.unlink(temp_frame.name)
        
        result_details['video_frames_copied'] = len(video_frames)
        
        if video_frames:
            content_vlm_result = _query_vlm_safe(
                query_vlm,
                VIDEO_CONTENT_PROMPT,
                images=video_frames
            )
            
            if content_vlm_result:
                result_details['content_vlm'] = content_vlm_result
                
                aerial = content_vlm_result.get('aerial_perspective', False)
                coastal = content_vlm_result.get('coastal_geography', False)
                real_terrain = content_vlm_result.get('real_terrain_imagery', False)
                amalfi = content_vlm_result.get('amalfi_coast_features', False)
                confidence = content_vlm_result.get('confidence', 'low')
                
                content_criteria = sum([aerial, coastal, real_terrain])
                
                if content_criteria >= 3:
                    vlm_content_score = 15
                    feedback_parts.append("✅ Video shows aerial coastal flythrough")
                elif content_criteria >= 2:
                    vlm_content_score = 12
                    feedback_parts.append("✅ Video shows most expected features")
                elif content_criteria >= 1:
                    vlm_content_score = 7
                    feedback_parts.append("⚠️ Video shows some expected features")
                else:
                    feedback_parts.append("❌ Video content doesn't match expectations")
                
                # Bonus for Amalfi Coast identification
                if amalfi and confidence in ['medium', 'high']:
                    vlm_content_score = min(vlm_content_score + 10, 25)
                    feedback_parts.append("✅ Amalfi Coast features identified")
            
            # Clean up temp frames
            for frame_path in video_frames:
                try:
                    os.unlink(frame_path)
                except:
                    pass
        else:
            feedback_parts.append("⚠️ No video frames available for content analysis")
    else:
        feedback_parts.append("⚠️ VLM verification not available")
    
    # Add VLM scores
    score += vlm_trajectory_score + vlm_content_score
    
    result_details['vlm_trajectory_score'] = vlm_trajectory_score
    result_details['vlm_content_score'] = vlm_content_score
    
    # =================================================================
    # FINAL SCORING
    # =================================================================
    
    result_details['final_score'] = score
    
    # Key criteria for pass
    key_criteria_met = (
        output_exists and 
        (file_created_during_task or score >= 70) and  # Anti-gaming or high score
        (video_width > 0 or video_duration > 0)  # Some valid video metadata
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Final feedback summary
    feedback_summary = f"Score: {score}/100"
    if passed:
        feedback_summary += " - PASSED"
    else:
        feedback_summary += " - FAILED"
    
    feedback_parts.insert(0, feedback_summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }