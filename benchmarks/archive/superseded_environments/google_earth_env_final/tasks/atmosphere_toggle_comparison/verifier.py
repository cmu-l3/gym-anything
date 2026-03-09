#!/usr/bin/env python3
"""
Verifier for atmosphere_toggle_comparison task.

VERIFICATION STRATEGY:
Uses hybrid verification (programmatic + VLM on trajectory frames)

Programmatic checks:
1. File 1 exists and is valid image (15 points)
2. File 2 exists and is valid image (15 points)  
3. Both files created during task - anti-gaming (10 points)
4. Images are different from each other - anti-gaming (part of atmosphere check)

VLM checks (using TRAJECTORY frames, not just final):
5. Location verification - shows Mount Everest/Himalayan terrain (20 points)
6. Viewpoint consistency - both images show same geographic view (20 points)
7. Atmosphere difference - visible difference in sky/atmosphere rendering (20 points)

Pass threshold: 70 points with atmosphere difference detected
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_atmosphere_toggle_comparison(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that atmosphere comparison screenshots were created correctly.
    
    Uses multiple independent signals to prevent gaming:
    - Programmatic file checks
    - Timestamp verification
    - Image difference detection
    - VLM trajectory analysis
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: First file exists and valid (15 points)
    # ================================================================
    file1_info = result.get('file1', {})
    file1_exists = file1_info.get('exists', False)
    file1_size = file1_info.get('size_bytes', 0)
    min_size = metadata.get('min_file_size_kb', 100) * 1024
    
    if file1_exists and file1_size >= min_size:
        score += 15
        feedback_parts.append(f"✅ File 1 exists ({file1_size/1024:.1f}KB)")
        details['file1_valid'] = True
    elif file1_exists:
        score += 8
        feedback_parts.append(f"⚠️ File 1 exists but small ({file1_size/1024:.1f}KB)")
        details['file1_valid'] = False
    else:
        feedback_parts.append("❌ File 1 (with atmosphere) not found")
        details['file1_valid'] = False
    
    # ================================================================
    # CRITERION 2: Second file exists and valid (15 points)
    # ================================================================
    file2_info = result.get('file2', {})
    file2_exists = file2_info.get('exists', False)
    file2_size = file2_info.get('size_bytes', 0)
    
    if file2_exists and file2_size >= min_size:
        score += 15
        feedback_parts.append(f"✅ File 2 exists ({file2_size/1024:.1f}KB)")
        details['file2_valid'] = True
    elif file2_exists:
        score += 8
        feedback_parts.append(f"⚠️ File 2 exists but small ({file2_size/1024:.1f}KB)")
        details['file2_valid'] = False
    else:
        feedback_parts.append("❌ File 2 (without atmosphere) not found")
        details['file2_valid'] = False
    
    # ================================================================
    # CRITERION 3: Files created during task - anti-gaming (10 points)
    # ================================================================
    file1_created = file1_info.get('created_during_task', False)
    file2_created = file2_info.get('created_during_task', False)
    
    if file1_created and file2_created:
        score += 10
        feedback_parts.append("✅ Both files created during task")
        details['timestamps_valid'] = True
    elif file1_created or file2_created:
        score += 5
        feedback_parts.append("⚠️ Only one file created during task")
        details['timestamps_valid'] = False
    else:
        feedback_parts.append("❌ Files not created during task (possible pre-existing)")
        details['timestamps_valid'] = False
    
    # ================================================================
    # CRITERION 4: Images are different - anti-gaming check
    # ================================================================
    comparison = result.get('comparison', {})
    images_different = comparison.get('images_different', False)
    pixel_diff = comparison.get('pixel_difference', 0)
    
    if images_different:
        details['images_different'] = True
        details['pixel_difference'] = pixel_diff
    else:
        feedback_parts.append("⚠️ Images appear identical - atmosphere may not have been toggled")
        details['images_different'] = False
    
    # ================================================================
    # VLM VERIFICATION (60 points total)
    # ================================================================
    vlm_score = 0
    vlm_details = {}
    
    if query_vlm and file1_exists and file2_exists:
        # Copy the output images for VLM analysis
        temp_file1 = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_file2 = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        
        try:
            copy_from_env(file1_info.get('path', ''), temp_file1.name)
            copy_from_env(file2_info.get('path', ''), temp_file2.name)
            
            # Also get trajectory frames for process verification
            trajectory_frames = _get_trajectory_frames(traj, n=5)
            
            # ============================================================
            # VLM Check 1: Location verification (20 points)
            # ============================================================
            location_result = _verify_location(query_vlm, temp_file1.name, temp_file2.name)
            vlm_details['location'] = location_result
            
            if location_result.get('correct', False):
                loc_score = 20 if location_result.get('confidence') == 'high' else 15
                vlm_score += loc_score
                feedback_parts.append("✅ Location: Mount Everest/Himalayas confirmed")
            else:
                feedback_parts.append("❌ Location: Not clearly Mount Everest area")
            
            # ============================================================
            # VLM Check 2: Viewpoint consistency (20 points)
            # ============================================================
            viewpoint_result = _verify_viewpoint_match(query_vlm, temp_file1.name, temp_file2.name)
            vlm_details['viewpoint'] = viewpoint_result
            
            if viewpoint_result.get('match', False):
                vp_score = 20 if viewpoint_result.get('confidence') == 'high' else 15
                vlm_score += vp_score
                feedback_parts.append("✅ Viewpoints match between images")
            else:
                feedback_parts.append("❌ Viewpoints do not match")
            
            # ============================================================
            # VLM Check 3: Atmosphere difference (20 points)
            # ============================================================
            atmo_result = _verify_atmosphere_difference(query_vlm, temp_file1.name, temp_file2.name)
            vlm_details['atmosphere'] = atmo_result
            
            if atmo_result.get('difference_detected', False):
                atmo_score = 20 if atmo_result.get('confidence') == 'high' else 15
                vlm_score += atmo_score
                feedback_parts.append("✅ Atmosphere difference visible between images")
                details['atmosphere_toggled'] = True
            else:
                feedback_parts.append("❌ No clear atmosphere difference detected")
                details['atmosphere_toggled'] = False
            
            # ============================================================
            # Trajectory verification (bonus validation)
            # ============================================================
            if trajectory_frames:
                process_result = _verify_process_via_trajectory(query_vlm, trajectory_frames)
                vlm_details['process'] = process_result
                if process_result.get('workflow_observed', False):
                    feedback_parts.append("✅ Workflow progression observed in trajectory")
            
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {e}")
        finally:
            for tf in [temp_file1, temp_file2]:
                if os.path.exists(tf.name):
                    os.unlink(tf.name)
    
    elif not query_vlm:
        feedback_parts.append("⚠️ VLM not available for visual verification")
    else:
        feedback_parts.append("⚠️ Cannot perform VLM verification - files missing")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    details['vlm_details'] = vlm_details
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = 100
    pass_threshold = 70
    
    # Key criteria: files exist AND atmosphere was toggled
    key_criteria_met = (
        details.get('file1_valid', False) and 
        details.get('file2_valid', False) and
        (details.get('atmosphere_toggled', False) or details.get('images_different', False))
    )
    
    passed = score >= pass_threshold and key_criteria_met
    
    # Adjust pass status based on evidence
    if score >= pass_threshold and not key_criteria_met:
        feedback_parts.append(f"⚠️ Score {score} meets threshold but key criteria not met")
        passed = False
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


def _get_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """
    Extract trajectory frames for process verification.
    Returns list of frame paths sampled across the trajectory.
    """
    frames = []
    try:
        # Try to get frames from trajectory
        episode_dir = traj.get('episode_dir', '')
        all_frames = traj.get('frames', [])
        
        if all_frames and len(all_frames) > 0:
            # Sample n frames evenly across trajectory
            step = max(1, len(all_frames) // n)
            frames = [all_frames[i] for i in range(0, len(all_frames), step)][:n]
        elif episode_dir:
            # Try to find frames in episode directory
            import glob
            frame_paths = sorted(glob.glob(os.path.join(episode_dir, 'frame_*.png')))
            if frame_paths:
                step = max(1, len(frame_paths) // n)
                frames = [frame_paths[i] for i in range(0, len(frame_paths), step)][:n]
    except Exception as e:
        logger.warning(f"Could not get trajectory frames: {e}")
    
    return frames


def _verify_location(query_vlm, file1_path: str, file2_path: str) -> Dict[str, Any]:
    """Verify both images show Mount Everest/Himalayan region."""
    prompt = """Analyze these two Google Earth screenshots.

Do BOTH images show the Mount Everest region or Himalayan mountain range?

Look for:
- High-altitude snow-capped mountain peaks
- Himalayan terrain characteristics (rugged, high elevation)
- The distinctive shape of Mount Everest if visible

Answer in JSON format:
{
    "shows_everest_region": true/false,
    "both_images_same_region": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the images"
}
"""
    try:
        result = query_vlm(prompt=prompt, images=[file1_path, file2_path])
        if result.get('success'):
            parsed = result.get('parsed', {})
            return {
                'correct': parsed.get('shows_everest_region', False) and parsed.get('both_images_same_region', False),
                'confidence': parsed.get('confidence', 'low'),
                'raw': parsed
            }
    except Exception as e:
        logger.warning(f"Location verification failed: {e}")
    
    return {'correct': False, 'confidence': 'low', 'error': 'VLM query failed'}


def _verify_viewpoint_match(query_vlm, file1_path: str, file2_path: str) -> Dict[str, Any]:
    """Verify both images show the same viewpoint."""
    prompt = """Compare these two Google Earth screenshots.

Do both images show the SAME geographic viewpoint?
- Are the mountains in the same positions within the frame?
- Is the viewing angle the same?
- Is the altitude/zoom level approximately the same?

The images may have different sky colors (that's expected), but the terrain/geography should be identical.

Answer in JSON format:
{
    "viewpoints_match": true/false,
    "terrain_alignment": "identical"/"similar"/"different",
    "confidence": "low"/"medium"/"high",
    "observations": "describe viewpoint comparison"
}
"""
    try:
        result = query_vlm(prompt=prompt, images=[file1_path, file2_path])
        if result.get('success'):
            parsed = result.get('parsed', {})
            return {
                'match': parsed.get('viewpoints_match', False),
                'alignment': parsed.get('terrain_alignment', 'unknown'),
                'confidence': parsed.get('confidence', 'low'),
                'raw': parsed
            }
    except Exception as e:
        logger.warning(f"Viewpoint verification failed: {e}")
    
    return {'match': False, 'confidence': 'low', 'error': 'VLM query failed'}


def _verify_atmosphere_difference(query_vlm, file1_path: str, file2_path: str) -> Dict[str, Any]:
    """Verify visible difference in atmosphere rendering between images."""
    prompt = """Compare the SKY and ATMOSPHERIC effects in these two Google Earth screenshots.

Google Earth's atmosphere layer affects:
- Sky color (blue gradient when ON, black/dark when OFF)
- Atmospheric haze at the horizon
- Overall color warmth of the terrain

Analyze:
1. Does one image have a blue sky with atmospheric haze?
2. Does the other image have a dark/black sky with sharper horizon?
3. Is there a clear visual difference in atmosphere rendering?

Answer in JSON format:
{
    "atmosphere_difference_visible": true/false,
    "image1_has_atmosphere": true/false,
    "image2_has_atmosphere": true/false,
    "sky_difference": "describe the sky difference",
    "confidence": "low"/"medium"/"high",
    "observations": "detailed comparison"
}
"""
    try:
        result = query_vlm(prompt=prompt, images=[file1_path, file2_path])
        if result.get('success'):
            parsed = result.get('parsed', {})
            diff_detected = parsed.get('atmosphere_difference_visible', False)
            # Also check if one has atmosphere and one doesn't
            img1_atmo = parsed.get('image1_has_atmosphere', False)
            img2_atmo = parsed.get('image2_has_atmosphere', False)
            if img1_atmo != img2_atmo:
                diff_detected = True
            
            return {
                'difference_detected': diff_detected,
                'image1_atmosphere': img1_atmo,
                'image2_atmosphere': img2_atmo,
                'confidence': parsed.get('confidence', 'low'),
                'raw': parsed
            }
    except Exception as e:
        logger.warning(f"Atmosphere verification failed: {e}")
    
    return {'difference_detected': False, 'confidence': 'low', 'error': 'VLM query failed'}


def _verify_process_via_trajectory(query_vlm, trajectory_frames: list) -> Dict[str, Any]:
    """Verify workflow progression using trajectory frames."""
    if not trajectory_frames or len(trajectory_frames) < 2:
        return {'workflow_observed': False, 'reason': 'Insufficient trajectory frames'}
    
    prompt = """Analyze this sequence of screenshots showing an agent's workflow in Google Earth.

The agent's task was to:
1. Navigate to Mount Everest
2. Take a screenshot with atmosphere enabled
3. Toggle atmosphere off (View > Atmosphere)
4. Take a second screenshot

Look for evidence of:
- Navigation to a mountain location
- Google Earth interface interactions
- Menu access (View menu)
- Screenshot saving dialogs
- Different atmospheric states

Answer in JSON format:
{
    "workflow_observed": true/false,
    "navigation_seen": true/false,
    "menu_interaction_seen": true/false,
    "state_changes_observed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe the workflow progression"
}
"""
    try:
        result = query_vlm(prompt=prompt, images=trajectory_frames)
        if result.get('success'):
            parsed = result.get('parsed', {})
            return {
                'workflow_observed': parsed.get('workflow_observed', False),
                'navigation_seen': parsed.get('navigation_seen', False),
                'menu_interaction_seen': parsed.get('menu_interaction_seen', False),
                'confidence': parsed.get('confidence', 'low'),
                'raw': parsed
            }
    except Exception as e:
        logger.warning(f"Process verification failed: {e}")
    
    return {'workflow_observed': False, 'error': 'VLM query failed'}


if __name__ == "__main__":
    # For testing
    print("Atmosphere toggle comparison verifier loaded")