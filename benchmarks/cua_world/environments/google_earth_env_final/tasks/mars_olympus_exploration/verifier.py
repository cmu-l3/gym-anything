#!/usr/bin/env python3
"""
Verifier for Mars Olympus Exploration task.

VERIFICATION STRATEGY:
1. File-based checks (from exported JSON via copy_from_env)
2. Color analysis (Mars has distinctive reddish terrain)
3. VLM trajectory verification (uses MULTIPLE frames, not just final)

SCORING:
- Mars view active (25 pts): Color analysis indicates Mars terrain
- Olympus region visible (25 pts): VLM confirms volcanic feature
- Caldera visible (20 pts): VLM confirms caldera/crater structure
- Screenshot saved (20 pts): Valid output file exists and was created during task
- Image quality (10 pts): Appropriate dimensions and file size

ANTI-GAMING:
- File must be created DURING task (timestamp check)
- Color analysis checks for Mars-like reddish hue
- VLM trajectory analysis prevents pre-placed screenshots
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

# Trajectory process verification - uses MULTIPLE frames
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent attempting to navigate Google Earth Pro to Mars and find Olympus Mons.

The screenshots are in chronological order (earliest to latest).

For successful completion, the agent should:
1. Start in Google Earth Pro showing Earth
2. Switch to Mars view (via View > Explore > Mars menu or planet icon)
3. Navigate to Olympus Mons (search or manual navigation)
4. Save a screenshot of the feature

Analyze this sequence and determine:

1. MARS_VIEW_SHOWN: At any point, does the view show Mars surface (reddish-brown terrain, Martian landscape) instead of Earth (blue oceans, green land)?

2. NAVIGATION_OCCURRED: Do the frames show progression through different views/locations? (Not just the same static view)

3. VOLCANIC_FEATURE_VISIBLE: Is a large volcanic/caldera feature visible at any point? Olympus Mons has:
   - A massive circular caldera (depression at the summit)
   - Shield volcano shape (gentle slopes)
   - Approximately 600km diameter

4. MENU_OR_SEARCH_USED: Is there evidence of menu navigation or search functionality being used?

Respond in JSON format:
{
    "mars_view_shown": true/false,
    "navigation_occurred": true/false,
    "volcanic_feature_visible": true/false,
    "menu_or_search_used": true/false,
    "stages_observed": ["list what you see happening"],
    "confidence": "low"/"medium"/"high",
    "reasoning": "describe the progression across frames"
}
"""

# Final screenshot quality check
FINAL_SCREENSHOT_PROMPT = """You are verifying a screenshot that should show Olympus Mons on Mars from Google Earth Pro.

Analyze this image and determine:

1. IS_MARS_SURFACE: Does this show Mars terrain (reddish-brown surface, no blue water, no green vegetation)?

2. IS_GOOGLE_EARTH: Does this look like Google Earth Pro interface (satellite/terrain imagery, possibly with UI elements)?

3. SHOWS_VOLCANIC_FEATURE: Is there a large volcanic caldera or shield volcano visible? Olympus Mons features:
   - Large circular depression (caldera) at the summit
   - Massive shield volcano shape
   - The caldera is about 80km across with nested collapse pits

4. IMAGE_QUALITY: Is the image clear enough to identify features? (not too zoomed out, not blurry)

Respond in JSON format:
{
    "is_mars_surface": true/false,
    "is_google_earth": true/false,
    "shows_volcanic_feature": true/false,
    "caldera_visible": true/false,
    "image_quality_adequate": true/false,
    "confidence": "low"/"medium"/"high",
    "feature_description": "describe what you see in the image"
}
"""


def verify_mars_olympus_exploration(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Mars Olympus Exploration task completion.
    
    Uses multi-signal verification:
    1. File existence and timestamp checks
    2. Color analysis for Mars terrain
    3. VLM trajectory verification
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    # Get helper functions
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    scores = {
        'mars_view_active': 0,
        'olympus_region_visible': 0,
        'caldera_visible': 0,
        'screenshot_saved': 0,
        'image_quality': 0
    }
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Check output file existence and validity
    # ================================================================
    output_info = result.get('output', {})
    output_exists = output_info.get('exists', False)
    output_size = output_info.get('size_bytes', 0)
    file_created_during_task = output_info.get('created_during_task', False)
    
    min_size_kb = metadata.get('min_file_size_kb', 50)
    min_size_bytes = min_size_kb * 1024
    
    if output_exists and output_size >= min_size_bytes:
        if file_created_during_task:
            scores['screenshot_saved'] = 20
            feedback_parts.append(f"✅ Screenshot saved ({output_size/1024:.1f}KB, created during task)")
        else:
            scores['screenshot_saved'] = 5  # Partial credit - file exists but suspicious
            feedback_parts.append(f"⚠️ Screenshot exists but may predate task")
    elif output_exists:
        scores['screenshot_saved'] = 5
        feedback_parts.append(f"⚠️ Screenshot too small ({output_size/1024:.1f}KB)")
    else:
        feedback_parts.append("❌ No screenshot file found")
    
    details['file_check'] = {
        'exists': output_exists,
        'size_bytes': output_size,
        'created_during_task': file_created_during_task
    }
    
    # ================================================================
    # STEP 3: Color analysis for Mars terrain detection
    # ================================================================
    image_info = result.get('image', {})
    red_dominance = image_info.get('red_dominance', 0)
    avg_red = image_info.get('avg_red', 0)
    avg_blue = image_info.get('avg_blue', 0)
    image_width = image_info.get('width', 0)
    image_height = image_info.get('height', 0)
    
    # Mars terrain typically has red > blue (reddish-brown color)
    # Threshold of 10+ indicates likely Mars surface
    likely_mars_by_color = red_dominance > 10 and avg_red > 100
    
    details['color_analysis'] = {
        'red_dominance': red_dominance,
        'avg_red': avg_red,
        'avg_blue': avg_blue,
        'likely_mars': likely_mars_by_color
    }
    
    if likely_mars_by_color:
        scores['mars_view_active'] += 15  # Partial points from color analysis
        feedback_parts.append(f"✅ Color analysis suggests Mars surface (red dominance: {red_dominance:.1f})")
    else:
        feedback_parts.append(f"⚠️ Color analysis inconclusive (red dominance: {red_dominance:.1f})")
    
    # Image quality check
    if image_width >= 800 and image_height >= 600:
        scores['image_quality'] = 10
        feedback_parts.append(f"✅ Good image dimensions ({image_width}x{image_height})")
    elif image_width > 0 and image_height > 0:
        scores['image_quality'] = 5
        feedback_parts.append(f"⚠️ Small image dimensions ({image_width}x{image_height})")
    
    # ================================================================
    # STEP 4: VLM Trajectory Verification (CRITICAL - prevents gaming)
    # ================================================================
    vlm_trajectory_result = None
    vlm_final_result = None
    
    if query_vlm:
        # Import trajectory frame sampling
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames (multiple frames across the episode)
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            details['trajectory_frames_count'] = len(trajectory_frames) if trajectory_frames else 0
            details['has_final_screenshot'] = final_screenshot is not None
            
            # VLM check on trajectory (process verification)
            if trajectory_frames and len(trajectory_frames) >= 2:
                logger.info(f"Running VLM trajectory verification with {len(trajectory_frames)} frames")
                vlm_trajectory_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                details['vlm_trajectory'] = vlm_trajectory_result
                
                if vlm_trajectory_result and vlm_trajectory_result.get('success'):
                    parsed = vlm_trajectory_result.get('parsed', {})
                    
                    # Mars view shown in trajectory
                    if parsed.get('mars_view_shown'):
                        scores['mars_view_active'] = 25  # Full points
                        feedback_parts.append("✅ VLM confirms Mars view in trajectory")
                    
                    # Volcanic feature visible
                    if parsed.get('volcanic_feature_visible'):
                        scores['olympus_region_visible'] = 25
                        feedback_parts.append("✅ VLM confirms volcanic feature visible")
                    
                    # Navigation occurred (anti-gaming)
                    if parsed.get('navigation_occurred'):
                        feedback_parts.append("✅ VLM confirms navigation activity")
                    else:
                        feedback_parts.append("⚠️ Limited navigation activity detected")
            
            # VLM check on final screenshot (content verification)
            if final_screenshot:
                logger.info("Running VLM final screenshot verification")
                vlm_final_result = query_vlm(
                    prompt=FINAL_SCREENSHOT_PROMPT,
                    image=final_screenshot
                )
                details['vlm_final'] = vlm_final_result
                
                if vlm_final_result and vlm_final_result.get('success'):
                    parsed = vlm_final_result.get('parsed', {})
                    
                    # Check for caldera
                    if parsed.get('caldera_visible'):
                        scores['caldera_visible'] = 20
                        feedback_parts.append("✅ VLM confirms caldera visible")
                    elif parsed.get('shows_volcanic_feature'):
                        scores['caldera_visible'] = 10
                        feedback_parts.append("⚠️ Volcanic feature visible but caldera unclear")
                    
                    # Confidence adjustment
                    confidence = parsed.get('confidence', 'low')
                    details['vlm_confidence'] = confidence
                    
        except ImportError as e:
            logger.warning(f"Could not import VLM utilities: {e}")
            feedback_parts.append("⚠️ VLM verification unavailable")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for verification")
    
    # ================================================================
    # STEP 5: Application state check
    # ================================================================
    app_info = result.get('application', {})
    ge_running = app_info.get('google_earth_running', False)
    window_title = app_info.get('window_title', '')
    
    if ge_running:
        feedback_parts.append("✅ Google Earth Pro was running")
    else:
        feedback_parts.append("⚠️ Google Earth Pro not detected")
    
    # Check if window title indicates Mars mode
    if 'mars' in window_title.lower():
        feedback_parts.append("✅ Window title indicates Mars mode")
    
    details['app_state'] = {
        'running': ge_running,
        'window_title': window_title
    }
    
    # ================================================================
    # STEP 6: Calculate final score and pass/fail
    # ================================================================
    total_score = sum(scores.values())
    details['scores'] = scores
    
    # Pass criteria:
    # - Score >= 70
    # - Mars view must be confirmed (by color OR VLM)
    # - Screenshot must exist and be created during task
    mars_confirmed = scores['mars_view_active'] >= 15
    screenshot_valid = scores['screenshot_saved'] >= 15
    
    passed = (total_score >= 70) and mars_confirmed and screenshot_valid
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {total_score}/100"
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": details
    }