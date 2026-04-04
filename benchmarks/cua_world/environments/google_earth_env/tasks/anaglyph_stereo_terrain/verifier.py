#!/usr/bin/env python3
"""
Verifier for anaglyph_stereo_terrain task.

VERIFICATION STRATEGY:
This task has a highly verifiable outcome - anaglyph 3D mode creates
unmistakable red-cyan color separation that cannot be faked.

MULTI-CRITERIA SCORING (100 points total):
1. Anaglyph mode enabled (40 points) - MANDATORY
   - Detected via red-cyan color channel analysis
   - This is the PRIMARY verification signal

2. Mountainous terrain visible (20 points)
   - High image variance indicates complex terrain
   - VLM confirmation of mountain landscape

3. View properly tilted (20 points)
   - Top/bottom brightness difference indicates tilted view
   - VLM confirmation of 3D perspective

4. Settings accessed / workflow completed (20 points)
   - VLM trajectory analysis shows Options dialog interaction
   - Evidence of proper workflow progression

ANTI-GAMING MEASURES:
- Screenshots must be different (detect "do nothing")
- Timestamp checks on task duration
- Trajectory frames show actual workflow (not just final state)
- Color analysis cannot be easily spoofed
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def analyze_anaglyph_effect(image_path: str) -> Dict[str, Any]:
    """
    Detect anaglyph stereoscopic effect through color channel analysis.
    
    Anaglyph 3D creates characteristic red-cyan color separation where:
    - Terrain edges show red fringing on one side
    - Cyan (green+blue) fringing on the opposite side
    - This creates a distinctive color pattern that's easily detectable
    """
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(image_path).convert('RGB')
        arr = np.array(img)
        
        # Extract color channels
        red = arr[:, :, 0].astype(float)
        green = arr[:, :, 1].astype(float)
        blue = arr[:, :, 2].astype(float)
        
        # Cyan channel approximation
        cyan = (green + blue) / 2
        
        # Method 1: Look for red-dominant and cyan-dominant regions
        # In anaglyph, edges have pure red on one side, pure cyan on other
        red_dominant = (red > 140) & (green < 90) & (blue < 90)
        cyan_dominant = (red < 90) & ((green > 90) | (blue > 90))
        
        red_ratio = np.sum(red_dominant) / red.size
        cyan_ratio = np.sum(cyan_dominant) / cyan.size
        
        # Anaglyph score: both red and cyan should be present
        min_ratio = min(red_ratio, cyan_ratio)
        anaglyph_score = min_ratio * 1000
        
        # Method 2: Check for channel offset at edges
        # Calculate edge maps for red and cyan channels
        red_horiz_grad = np.abs(np.diff(red, axis=1))
        cyan_horiz_grad = np.abs(np.diff(cyan, axis=1))
        
        # In anaglyph, red and cyan edges should be offset
        # This creates areas where red gradient is high but cyan is low, and vice versa
        edge_product = red_horiz_grad.mean() * cyan_horiz_grad.mean()
        edge_correlation = np.corrcoef(red_horiz_grad.flatten()[:10000], 
                                        cyan_horiz_grad.flatten()[:10000])[0, 1]
        
        # Method 3: Look for systematic horizontal color shift
        # Split image into left/right and compare color balance
        mid = arr.shape[1] // 2
        left_red_mean = red[:, :mid].mean()
        right_red_mean = red[:, mid:].mean()
        left_cyan_mean = cyan[:, :mid].mean()
        right_cyan_mean = cyan[:, mid:].mean()
        
        color_shift = abs((left_red_mean - right_red_mean) - (left_cyan_mean - right_cyan_mean))
        
        # Combined detection: anaglyph if any strong signal
        is_anaglyph = (
            anaglyph_score > 1.5 or  # Significant red/cyan regions
            (edge_correlation < 0.7 and edge_product > 100) or  # Uncorrelated edges
            color_shift > 5.0  # Systematic color shift
        )
        
        return {
            'is_anaglyph': is_anaglyph,
            'anaglyph_score': float(anaglyph_score),
            'red_dominant_ratio': float(red_ratio),
            'cyan_dominant_ratio': float(cyan_ratio),
            'edge_correlation': float(edge_correlation) if not np.isnan(edge_correlation) else 0.0,
            'color_shift': float(color_shift),
            'confidence': 'high' if anaglyph_score > 3.0 else ('medium' if anaglyph_score > 1.5 else 'low')
        }
        
    except ImportError as e:
        logger.warning(f"PIL/numpy not available: {e}")
        return {'is_anaglyph': False, 'error': f'Missing dependency: {e}'}
    except Exception as e:
        logger.warning(f"Color analysis failed: {e}")
        return {'is_anaglyph': False, 'error': str(e)}


def analyze_terrain(image_path: str) -> Dict[str, Any]:
    """Check if image shows mountainous terrain (high elevation variation)."""
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(image_path).convert('L')  # Grayscale
        arr = np.array(img).astype(float)
        
        # Mountains show high local variance
        variance = np.var(arr)
        
        # Check for texture complexity using gradient magnitude
        gx = np.abs(np.diff(arr, axis=1))
        gy = np.abs(np.diff(arr, axis=0))
        gradient_mean = (gx.mean() + gy.mean()) / 2
        
        # High variance and gradient = mountainous terrain
        is_mountainous = variance > 600 and gradient_mean > 8
        
        return {
            'is_mountainous': is_mountainous,
            'variance': float(variance),
            'gradient_mean': float(gradient_mean),
            'confidence': 'high' if variance > 1000 else ('medium' if variance > 600 else 'low')
        }
    except Exception as e:
        return {'is_mountainous': False, 'error': str(e)}


def analyze_view_tilt(image_path: str) -> Dict[str, Any]:
    """Check if view appears tilted (3D perspective, not top-down)."""
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(image_path).convert('L')
        arr = np.array(img).astype(float)
        
        # Tilted views show different brightness at top vs bottom
        # Top often shows sky/horizon (lighter), bottom shows terrain (varied)
        top_third = arr[:arr.shape[0]//3, :]
        bottom_third = arr[2*arr.shape[0]//3:, :]
        
        top_mean = np.mean(top_third)
        bottom_mean = np.mean(bottom_third)
        top_var = np.var(top_third)
        bottom_var = np.var(bottom_third)
        
        brightness_diff = abs(top_mean - bottom_mean)
        variance_diff = abs(top_var - bottom_var)
        
        # Tilted if significant brightness difference OR variance difference
        is_tilted = brightness_diff > 15 or variance_diff > 200
        
        return {
            'is_tilted': is_tilted,
            'brightness_difference': float(brightness_diff),
            'variance_difference': float(variance_diff),
            'top_brightness': float(top_mean),
            'bottom_brightness': float(bottom_mean)
        }
    except Exception as e:
        return {'is_tilted': False, 'error': str(e)}


# VLM Prompts
TRAJECTORY_WORKFLOW_PROMPT = """Analyze this sequence of screenshots from a Google Earth Pro session.

The task was to: Enable Anaglyph 3D mode and navigate to Mount Everest.

Look for evidence of these workflow steps:
1. OPTIONS/SETTINGS ACCESS: Did the agent open a settings/options dialog? Look for:
   - "Options" or "Preferences" dialog window
   - Tabbed interface with "3D View" or similar tab
   - Checkboxes or dropdowns for graphics settings

2. ANAGLYPH ENABLED: Is there red-cyan color separation visible in any frame? Look for:
   - Characteristic red and cyan color fringing on terrain edges
   - 3D stereoscopic effect (images appear to have depth)

3. NAVIGATION: Did the view change to show mountains? Look for:
   - Mountain terrain with snow-capped peaks
   - High-altitude terrain (Himalayan features)
   - View position changed from default

4. VIEW MANIPULATION: Was the view tilted for 3D effect? Look for:
   - Perspective view showing terrain depth
   - Not a flat top-down orthographic view

Respond in JSON format:
{
    "options_dialog_accessed": true/false,
    "anaglyph_colors_visible": true/false,
    "mountain_terrain_shown": true/false,
    "view_tilted": true/false,
    "workflow_progression_seen": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_PROMPT = """Analyze this Google Earth Pro screenshot for anaglyph 3D mode verification.

TASK: Enable anaglyph 3D stereo view of Mount Everest.

Anaglyph 3D creates a distinctive visual effect:
- RED and CYAN color separation on terrain edges
- Objects appear to have depth when viewed with 3D glasses
- Even without glasses, the color fringing is clearly visible

Check for:
1. Is this Google Earth showing satellite/terrain imagery?
2. Is there visible RED-CYAN color separation (anaglyph effect)?
   - Look at terrain edges, mountain ridges, and sharp features
   - In anaglyph mode, you'll see distinct red on one side and cyan/blue on the other
3. Does this show mountainous terrain (possibly Himalayas/Everest)?
4. Is the view tilted to show 3D terrain perspective?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "anaglyph_effect_visible": true/false,
    "red_cyan_separation_clear": true/false,
    "mountainous_terrain": true/false,
    "view_is_tilted": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "explain what visual evidence you see"
}
"""


def verify_anaglyph_stereo_terrain(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that anaglyph 3D mode was enabled and Mount Everest terrain is displayed.
    
    Uses multiple independent verification signals:
    1. Programmatic color analysis (primary - most reliable)
    2. VLM trajectory analysis (workflow verification)
    3. VLM final screenshot analysis (content verification)
    4. Export script results (supporting evidence)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Get exported results from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['export_result'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['export_result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Get final screenshot for analysis
    # ================================================================
    final_screenshot_path = None
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_final.png", temp_screenshot.name)
        if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
            final_screenshot_path = temp_screenshot.name
            details['final_screenshot_size'] = os.path.getsize(temp_screenshot.name)
    except Exception as e:
        logger.warning(f"Could not get final screenshot: {e}")
        details['screenshot_error'] = str(e)
    
    # ================================================================
    # CRITERION 1: Anaglyph mode enabled (40 points) - MANDATORY
    # ================================================================
    anaglyph_detected = False
    anaglyph_confidence = 'none'
    
    # Method A: Programmatic color analysis (most reliable)
    if final_screenshot_path:
        anaglyph_analysis = analyze_anaglyph_effect(final_screenshot_path)
        details['anaglyph_analysis'] = anaglyph_analysis
        
        if anaglyph_analysis.get('is_anaglyph', False):
            anaglyph_detected = True
            anaglyph_confidence = anaglyph_analysis.get('confidence', 'medium')
            
            if anaglyph_confidence == 'high':
                score += 40
                feedback_parts.append("✅ Anaglyph 3D mode clearly enabled (strong red-cyan separation)")
            elif anaglyph_confidence == 'medium':
                score += 35
                feedback_parts.append("✅ Anaglyph 3D mode enabled (moderate color separation)")
            else:
                score += 30
                feedback_parts.append("✅ Anaglyph 3D mode likely enabled (weak signal)")
    
    # Method B: Check export script's color analysis
    if not anaglyph_detected and result_data.get('anaglyph_detected_in_screenshot', False):
        anaglyph_detected = True
        score += 30
        feedback_parts.append("✅ Anaglyph detected by export analysis")
    
    # Method C: Check config file
    if not anaglyph_detected and result_data.get('anaglyph_in_config') == 'true':
        score += 15
        feedback_parts.append("⚠️ Anaglyph enabled in config (visual verification inconclusive)")
    
    if not anaglyph_detected:
        feedback_parts.append("❌ Anaglyph 3D mode not detected (no red-cyan color separation)")
        details['anaglyph_failure_reason'] = 'No characteristic color separation found'
    
    # ================================================================
    # CRITERION 2: Mountainous terrain visible (20 points)
    # ================================================================
    terrain_detected = False
    
    if final_screenshot_path:
        terrain_analysis = analyze_terrain(final_screenshot_path)
        details['terrain_analysis'] = terrain_analysis
        
        if terrain_analysis.get('is_mountainous', False):
            terrain_detected = True
            if terrain_analysis.get('confidence') == 'high':
                score += 20
                feedback_parts.append("✅ Mountainous terrain clearly visible")
            else:
                score += 15
                feedback_parts.append("✅ Mountainous terrain visible")
    
    if not terrain_detected:
        feedback_parts.append("❌ Mountainous terrain not detected")
    
    # ================================================================
    # CRITERION 3: View properly tilted (20 points)
    # ================================================================
    view_tilted = False
    
    if final_screenshot_path:
        tilt_analysis = analyze_view_tilt(final_screenshot_path)
        details['tilt_analysis'] = tilt_analysis
        
        if tilt_analysis.get('is_tilted', False):
            view_tilted = True
            score += 20
            feedback_parts.append("✅ View tilted for 3D perspective")
    
    if not view_tilted:
        feedback_parts.append("❌ View not tilted (appears flat/top-down)")
    
    # ================================================================
    # CRITERION 4: Workflow verification via VLM trajectory (20 points)
    # ================================================================
    workflow_verified = False
    
    if query_vlm:
        # Get trajectory frames
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot as vlm_final
            
            frames = sample_trajectory_frames(traj, n=5)
            details['trajectory_frames_count'] = len(frames) if frames else 0
            
            if frames and len(frames) >= 2:
                # Query VLM on trajectory
                vlm_traj_result = query_vlm(
                    prompt=TRAJECTORY_WORKFLOW_PROMPT,
                    images=frames
                )
                details['vlm_trajectory_result'] = vlm_traj_result
                
                if vlm_traj_result.get('success'):
                    parsed = vlm_traj_result.get('parsed', {})
                    
                    options_accessed = parsed.get('options_dialog_accessed', False)
                    anaglyph_vlm = parsed.get('anaglyph_colors_visible', False)
                    mountain_vlm = parsed.get('mountain_terrain_shown', False)
                    progression = parsed.get('workflow_progression_seen', False)
                    
                    vlm_score = 0
                    if options_accessed:
                        vlm_score += 8
                        feedback_parts.append("✅ VLM: Options dialog accessed")
                    if anaglyph_vlm:
                        vlm_score += 6
                        # Boost anaglyph confidence if VLM also sees it
                        if not anaglyph_detected:
                            anaglyph_detected = True
                            score += 20
                            feedback_parts.append("✅ VLM confirms anaglyph colors visible")
                    if progression:
                        vlm_score += 6
                    
                    score += vlm_score
                    workflow_verified = vlm_score >= 10
            
            # Also check final screenshot with VLM
            if final_screenshot_path:
                vlm_final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot_path
                )
                details['vlm_final_result'] = vlm_final_result
                
                if vlm_final_result.get('success'):
                    final_parsed = vlm_final_result.get('parsed', {})
                    if final_parsed.get('anaglyph_effect_visible') and final_parsed.get('red_cyan_separation_clear'):
                        if not anaglyph_detected:
                            anaglyph_detected = True
                            score += 25
                            feedback_parts.append("✅ VLM confirms clear anaglyph effect")
                        
        except ImportError:
            logger.warning("VLM utilities not available")
            details['vlm_error'] = 'VLM utilities not available'
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ================================================================
    # ANTI-GAMING CHECKS
    # ================================================================
    
    # Check if screenshots are different (detect "do nothing")
    screenshots_different = result_data.get('screenshots_different', True)
    if not screenshots_different:
        score = max(0, score - 30)
        feedback_parts.append("⚠️ Screenshots unchanged - possible 'do nothing'")
        details['anti_gaming_flag'] = 'screenshots_identical'
    
    # Check if Google Earth was running
    ge_running = result_data.get('google_earth_running', False)
    if not ge_running:
        score = max(0, score - 20)
        feedback_parts.append("⚠️ Google Earth not running at task end")
    
    # Check task duration (too fast = suspicious)
    task_duration = result_data.get('task_duration_seconds', 0)
    if task_duration < 10:
        score = max(0, score - 15)
        feedback_parts.append(f"⚠️ Task completed suspiciously fast ({task_duration}s)")
        details['anti_gaming_flag'] = 'too_fast'
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Cap score at 100
    score = min(100, max(0, score))
    
    # Determine pass/fail
    # MUST have anaglyph detected (primary criterion) AND score >= 60
    passed = anaglyph_detected and score >= 60
    
    # Clean up temp files
    if final_screenshot_path and os.path.exists(final_screenshot_path):
        try:
            os.unlink(final_screenshot_path)
        except:
            pass
    
    # Build final feedback
    feedback = " | ".join(feedback_parts) if feedback_parts else "No verification criteria met"
    
    if passed:
        feedback = f"✅ PASSED (Score: {score}/100) | " + feedback
    else:
        if not anaglyph_detected:
            feedback = f"❌ FAILED: Anaglyph 3D not detected (Score: {score}/100) | " + feedback
        else:
            feedback = f"❌ FAILED: Score below threshold (Score: {score}/100) | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }