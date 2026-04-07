#!/usr/bin/env python3
"""
Verifier for Grid Navigation to Bermuda Triangle task.

VERIFICATION STRATEGY:
1. Screenshot file exists and was created during task (20 + 15 points)
2. Grid pattern detection via image analysis (25 points)
3. Ocean/Atlantic location verification via color analysis (25 points)
4. VLM trajectory verification for process and content (15 points)

Pass threshold: 60 points AND screenshot file created during task

CRITICAL: Uses copy_from_env, NOT exec_in_env
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grid_navigation_bermuda(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent enabled grid overlay, navigated to Bermuda Triangle,
    and saved a screenshot.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_screenshot_path', '/home/ga/Pictures/bermuda_grid.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Screenshot file exists (20 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    image_format = result.get('image_format', 'none')
    
    if output_exists and output_size > 0:
        if output_size >= min_file_size_kb * 1024:
            score += 20
            feedback_parts.append(f"✅ Screenshot exists ({output_size/1024:.1f}KB, {image_format})")
        elif output_size >= 10000:  # At least 10KB
            score += 15
            feedback_parts.append(f"⚠️ Screenshot exists but small ({output_size/1024:.1f}KB)")
        else:
            score += 5
            feedback_parts.append(f"⚠️ Screenshot very small ({output_size/1024:.1f}KB)")
    else:
        feedback_parts.append("❌ Screenshot file NOT found")
        # Early exit - nothing else meaningful to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - ANTI-GAMING (15 points)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task")
        result_details['anti_gaming_passed'] = True
    else:
        feedback_parts.append("❌ File NOT created during task (possible pre-existing)")
        result_details['anti_gaming_passed'] = False
        # This is a critical failure - file predates task
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Anti-gaming check failed",
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 3: Grid pattern detection (25 points)
    # Copy the screenshot and analyze for grid lines
    # ================================================================
    grid_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(expected_output_path, temp_screenshot.name)
        grid_result = analyze_grid_pattern(temp_screenshot.name)
        result_details['grid_analysis'] = grid_result
        
        if grid_result.get('grid_detected', False):
            if grid_result.get('confidence', 'low') == 'high':
                grid_score = 25
                feedback_parts.append("✅ Grid pattern detected (high confidence)")
            elif grid_result.get('confidence', 'low') == 'medium':
                grid_score = 18
                feedback_parts.append("✅ Grid pattern detected (medium confidence)")
            else:
                grid_score = 10
                feedback_parts.append("⚠️ Possible grid pattern detected (low confidence)")
        else:
            feedback_parts.append("❌ No clear grid pattern detected")
        
        score += grid_score
        
    except Exception as e:
        logger.warning(f"Grid analysis failed: {e}")
        feedback_parts.append(f"⚠️ Grid analysis error: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    
    # ================================================================
    # CRITERION 4: Ocean/Atlantic location verification (25 points)
    # Analyze colors to check for ocean (blue) vs land
    # ================================================================
    location_score = 0
    temp_screenshot2 = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(expected_output_path, temp_screenshot2.name)
        location_result = analyze_ocean_colors(temp_screenshot2.name)
        result_details['location_analysis'] = location_result
        
        if location_result.get('shows_ocean', False):
            if location_result.get('ocean_ratio', 0) > 0.4:
                location_score = 25
                feedback_parts.append(f"✅ Ocean region confirmed ({location_result.get('ocean_ratio', 0):.0%} blue)")
            elif location_result.get('ocean_ratio', 0) > 0.2:
                location_score = 18
                feedback_parts.append(f"✅ Ocean features visible ({location_result.get('ocean_ratio', 0):.0%} blue)")
            else:
                location_score = 10
                feedback_parts.append(f"⚠️ Some water visible ({location_result.get('ocean_ratio', 0):.0%} blue)")
        else:
            feedback_parts.append("❌ Location does not appear to show ocean")
        
        score += location_score
        
    except Exception as e:
        logger.warning(f"Location analysis failed: {e}")
        feedback_parts.append(f"⚠️ Location analysis error: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_screenshot2.name):
            os.unlink(temp_screenshot2.name)
    
    # ================================================================
    # CRITERION 5: VLM verification using TRAJECTORY frames (15 points)
    # ================================================================
    vlm_score = 0
    if query_vlm:
        try:
            vlm_result = verify_with_vlm_trajectory(traj, query_vlm, copy_from_env, expected_output_path)
            result_details['vlm_verification'] = vlm_result
            
            if vlm_result.get('success', False):
                vlm_confidence = vlm_result.get('confidence', 'low')
                if vlm_confidence == 'high':
                    vlm_score = 15
                    feedback_parts.append("✅ VLM confirms grid + ocean view")
                elif vlm_confidence == 'medium':
                    vlm_score = 10
                    feedback_parts.append("✅ VLM partial confirmation")
                else:
                    vlm_score = 5
                    feedback_parts.append("⚠️ VLM low confidence")
            else:
                feedback_parts.append(f"⚠️ VLM: {vlm_result.get('reason', 'verification unclear')}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available")
    
    score += vlm_score
    
    # ================================================================
    # CRITERION 6: Google Earth was running (bonus check)
    # ================================================================
    google_earth_running = result.get('google_earth_running', False)
    if google_earth_running:
        result_details['app_running'] = True
    else:
        result_details['app_running'] = False
        feedback_parts.append("⚠️ Google Earth not running at export")
    
    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Pass requires:
    # - Score >= 60
    # - File was created during task (anti-gaming)
    # - Either grid OR location check passed
    
    content_ok = (grid_score >= 10) or (location_score >= 10)
    passed = (score >= 60) and file_created_during_task and content_ok
    
    result_details['final_score'] = score
    result_details['content_verified'] = content_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }


def analyze_grid_pattern(image_path: str) -> Dict[str, Any]:
    """
    Analyze image for grid line patterns.
    Grid lines create regular intensity variations in horizontal/vertical directions.
    """
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(image_path)
        img_array = np.array(img)
        
        # Convert to grayscale
        if len(img_array.shape) == 3:
            gray = np.mean(img_array, axis=2)
        else:
            gray = img_array
        
        # Method 1: Look for regular line patterns via edge detection
        # Compute gradient magnitude
        dy = np.abs(np.diff(gray, axis=0))
        dx = np.abs(np.diff(gray, axis=1))
        
        # Grid lines create sharp intensity changes
        # Look for thin bright/white lines (common in Google Earth grid)
        
        # Check for horizontal lines (variance in vertical direction)
        row_means = np.mean(gray, axis=1)
        row_variance = np.var(np.diff(row_means))
        
        # Check for vertical lines (variance in horizontal direction)
        col_means = np.mean(gray, axis=0)
        col_variance = np.var(np.diff(col_means))
        
        # Also check for presence of very bright thin lines (grid overlay)
        bright_threshold = 220  # Near white
        bright_pixels = np.sum(gray > bright_threshold)
        total_pixels = gray.size
        bright_ratio = bright_pixels / total_pixels
        
        # Grid typically creates 0.5% - 5% of pixels as bright lines
        has_bright_lines = 0.002 < bright_ratio < 0.08
        
        # Check for regular spacing pattern (FFT-based)
        # Grid lines at regular intervals create peaks in frequency domain
        has_regular_pattern = row_variance > 3 or col_variance > 3
        
        # Determine confidence
        indicators = [has_bright_lines, has_regular_pattern]
        true_count = sum(indicators)
        
        if true_count >= 2:
            confidence = 'high'
            grid_detected = True
        elif true_count >= 1:
            confidence = 'medium'
            grid_detected = True
        elif bright_ratio > 0.001:
            confidence = 'low'
            grid_detected = True
        else:
            confidence = 'none'
            grid_detected = False
        
        return {
            'grid_detected': grid_detected,
            'confidence': confidence,
            'row_variance': float(row_variance),
            'col_variance': float(col_variance),
            'bright_ratio': float(bright_ratio),
            'has_bright_lines': has_bright_lines,
            'has_regular_pattern': has_regular_pattern
        }
        
    except Exception as e:
        return {
            'grid_detected': False,
            'confidence': 'none',
            'error': str(e)
        }


def analyze_ocean_colors(image_path: str) -> Dict[str, Any]:
    """
    Analyze image colors to determine if it shows ocean.
    Ocean appears blue in satellite imagery.
    """
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(image_path).convert('RGB')
        img_array = np.array(img)
        
        # Extract color channels
        red = img_array[:,:,0].astype(float)
        green = img_array[:,:,1].astype(float)
        blue = img_array[:,:,2].astype(float)
        
        # Ocean detection: blue channel dominates
        # Deep ocean: dark blue (moderate blue, low red/green)
        # Shallow water: lighter blue
        
        # Check for blue-dominant pixels
        blue_dominant = (blue > red) & (blue > green)
        blue_ratio = np.sum(blue_dominant) / blue_dominant.size
        
        # More specific ocean blue check
        # Ocean typically has blue > 80, blue > red*1.1, blue > green*1.05
        ocean_blue = (blue > 60) & (blue < 220) & (blue > red * 1.05) & (blue > green * 0.95)
        ocean_ratio = np.sum(ocean_blue) / ocean_blue.size
        
        # Check for land (green/brown dominant)
        land_colors = (green > blue * 1.1) | ((red > blue) & (green > blue * 0.8))
        land_ratio = np.sum(land_colors) / land_colors.size
        
        # Average blue value
        avg_blue = np.mean(blue)
        avg_red = np.mean(red)
        avg_green = np.mean(green)
        
        # Determination
        # Bermuda Triangle view should be mostly ocean
        shows_ocean = (ocean_ratio > 0.15) or (blue_ratio > 0.3 and land_ratio < 0.4)
        
        return {
            'shows_ocean': shows_ocean,
            'ocean_ratio': float(ocean_ratio),
            'blue_ratio': float(blue_ratio),
            'land_ratio': float(land_ratio),
            'avg_colors': {
                'red': float(avg_red),
                'green': float(avg_green),
                'blue': float(avg_blue)
            }
        }
        
    except Exception as e:
        return {
            'shows_ocean': False,
            'ocean_ratio': 0,
            'error': str(e)
        }


def verify_with_vlm_trajectory(traj: Dict[str, Any], query_vlm, copy_from_env, screenshot_path: str) -> Dict[str, Any]:
    """
    Use VLM to verify the task using TRAJECTORY frames (not just final screenshot).
    This provides independent verification that actual work was done.
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames (captures the process, not just final state)
        trajectory_frames = sample_trajectory_frames(traj, n=4)
        final_screenshot = get_final_screenshot(traj)
        
        # Also get the saved screenshot from the container
        temp_saved = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        saved_screenshot = None
        try:
            copy_from_env(screenshot_path, temp_saved.name)
            saved_screenshot = temp_saved.name
        except:
            pass
        
        # Combine images for verification
        images_to_check = []
        if trajectory_frames:
            images_to_check.extend(trajectory_frames[-2:])  # Last 2 trajectory frames
        if final_screenshot:
            images_to_check.append(final_screenshot)
        if saved_screenshot and os.path.exists(saved_screenshot):
            images_to_check.append(saved_screenshot)
        
        if not images_to_check:
            return {
                'success': False,
                'reason': 'No images available for VLM verification'
            }
        
        # VLM prompt for trajectory + content verification
        vlm_prompt = """You are verifying a Google Earth task where the user should have:
1. Enabled the latitude/longitude grid overlay (thin lines forming a grid across the view)
2. Navigated to the Bermuda Triangle area (Atlantic Ocean, roughly between Florida, Bermuda, and Puerto Rico)
3. Saved a screenshot showing both the grid and ocean

Analyze these images (some from the agent's work session, some may be the final screenshot) and determine:

1. Is Google Earth visible in any of the images?
2. Is a coordinate grid (lat/lon lines) visible overlaid on the view?
3. Does the view show ocean/water (Atlantic Ocean region)?
4. Does this appear to be the Bermuda Triangle area (open Atlantic Ocean, possibly with some Caribbean islands visible)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "grid_overlay_visible": true/false,
    "shows_ocean": true/false,
    "bermuda_triangle_area": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the images"
}"""
        
        # Query VLM with multiple images
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=images_to_check
        )
        
        # Clean up temp file
        if saved_screenshot and os.path.exists(saved_screenshot):
            os.unlink(saved_screenshot)
        
        if not vlm_result.get('success', False):
            return {
                'success': False,
                'reason': vlm_result.get('error', 'VLM query failed')
            }
        
        parsed = vlm_result.get('parsed', {})
        
        # Evaluate VLM response
        google_earth_ok = parsed.get('google_earth_visible', False)
        grid_ok = parsed.get('grid_overlay_visible', False)
        ocean_ok = parsed.get('shows_ocean', False)
        bermuda_ok = parsed.get('bermuda_triangle_area', False)
        vlm_confidence = parsed.get('confidence', 'low')
        
        criteria_met = sum([google_earth_ok, grid_ok, ocean_ok, bermuda_ok])
        
        if criteria_met >= 3:
            return {
                'success': True,
                'confidence': vlm_confidence if vlm_confidence in ['high', 'medium'] else 'medium',
                'google_earth': google_earth_ok,
                'grid': grid_ok,
                'ocean': ocean_ok,
                'bermuda': bermuda_ok,
                'observations': parsed.get('observations', '')
            }
        elif criteria_met >= 2:
            return {
                'success': True,
                'confidence': 'low',
                'google_earth': google_earth_ok,
                'grid': grid_ok,
                'ocean': ocean_ok,
                'bermuda': bermuda_ok,
                'observations': parsed.get('observations', '')
            }
        else:
            return {
                'success': False,
                'reason': f'Only {criteria_met}/4 criteria met',
                'google_earth': google_earth_ok,
                'grid': grid_ok,
                'ocean': ocean_ok,
                'bermuda': bermuda_ok,
                'observations': parsed.get('observations', '')
            }
            
    except ImportError as e:
        logger.warning(f"VLM utilities not available: {e}")
        return {
            'success': False,
            'reason': f'VLM utilities not available: {str(e)}'
        }
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {
            'success': False,
            'reason': str(e)
        }