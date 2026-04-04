#!/usr/bin/env python3
"""
Verifier for screen_overlay_compass task.

TASK: Create a Screen Overlay in Google Earth Pro that displays a compass rose
image fixed to the bottom-right corner of the screen.

VERIFICATION STRATEGY:
1. KML file exists at expected path (10 pts)
2. KML contains ScreenOverlay (NOT GroundOverlay) (20 pts)
3. Image source is correct compass rose (15 pts)
4. Positioned in right portion of screen (x > 0.7) (15 pts)
5. Positioned in bottom portion of screen (y < 0.3) (10 pts)
6. Named appropriately (contains compass/legend) (10 pts)
7. VLM trajectory verification - shows workflow progression (20 pts)

Pass threshold: 60 points AND must have ScreenOverlay (not GroundOverlay)
"""

import json
import tempfile
import os
import re
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_screen_overlay_compass(traj, env_info, task_info):
    """
    Verify that a Screen Overlay with compass rose was created correctly.
    
    Uses multiple verification signals:
    - Programmatic KML analysis
    - Timestamp anti-gaming checks
    - VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/compass_overlay.kml')
    expected_screen_x_min = metadata.get('expected_screen_x_min', 0.7)
    expected_screen_y_max = metadata.get('expected_screen_y_max', 0.3)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        feedback_parts.append(f"⚠️ Could not read export result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Try to copy and analyze the KML file directly
    # ================================================================
    kml_content = ""
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output_path, temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        details['kml_file_copied'] = True
        details['kml_size'] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        details['kml_file_copied'] = False
        # Try to get from base64 in result
        kml_base64 = result.get('kml_content_base64', '')
        if kml_base64:
            try:
                kml_content = base64.b64decode(kml_base64).decode('utf-8')
                details['kml_from_base64'] = True
            except:
                pass
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_info = result.get('output_file', {})
    file_exists = output_info.get('exists', False) or len(kml_content) > 0
    
    if file_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ KML file NOT found at expected path")
        details['file_exists'] = False
        # Early return - nothing else to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (anti-gaming) (5 bonus pts)
    # ================================================================
    created_during_task = output_info.get('created_during_task', False)
    if created_during_task:
        score += 5
        feedback_parts.append("✅ File created during task")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠️ File may have existed before task")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Contains ScreenOverlay (NOT GroundOverlay) (20 points)
    # This is a KEY criterion - wrong overlay type is a failure
    # ================================================================
    kml_analysis = result.get('kml_analysis', {})
    
    has_screen_overlay = kml_analysis.get('has_screen_overlay', False)
    has_ground_overlay = kml_analysis.get('has_ground_overlay', False)
    
    # Also check directly from KML content
    if kml_content:
        if '<ScreenOverlay' in kml_content:
            has_screen_overlay = True
        if '<GroundOverlay' in kml_content:
            has_ground_overlay = True
    
    details['has_screen_overlay'] = has_screen_overlay
    details['has_ground_overlay'] = has_ground_overlay
    
    if has_screen_overlay and not has_ground_overlay:
        score += 20
        feedback_parts.append("✅ Correct: ScreenOverlay used")
    elif has_ground_overlay:
        feedback_parts.append("❌ WRONG: GroundOverlay used instead of ScreenOverlay")
        # This is a critical failure - return early with low score
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | ScreenOverlay is required, not GroundOverlay",
            "details": details
        }
    else:
        feedback_parts.append("❌ No ScreenOverlay element found in KML")
    
    # ================================================================
    # CRITERION 4: Correct compass image source (15 points)
    # ================================================================
    has_wikipedia_image = kml_analysis.get('has_wikipedia_image', False)
    
    # Also check directly
    if kml_content:
        if 'wikipedia' in kml_content.lower() or 'wikimedia' in kml_content.lower():
            has_wikipedia_image = True
        if 'Brosen_windrose' in kml_content or 'windrose' in kml_content.lower():
            has_wikipedia_image = True
        # Check for any image URL in href
        if re.search(r'<href>[^<]*\.(png|jpg|svg)', kml_content, re.IGNORECASE):
            # Has some image, give partial credit
            if not has_wikipedia_image:
                score += 8
                feedback_parts.append("⚠️ Has an image, but not the specified compass rose")
    
    if has_wikipedia_image:
        score += 15
        feedback_parts.append("✅ Correct compass rose image source")
        details['correct_image'] = True
    else:
        details['correct_image'] = False
    
    # ================================================================
    # CRITERION 5: Positioned in right portion of screen (15 points)
    # ================================================================
    screen_x_str = kml_analysis.get('screen_x_value', '')
    screen_x = None
    
    # Try to parse from KML directly
    if kml_content:
        match = re.search(r'<screenXY[^>]*x=["\']([0-9.]+)["\']', kml_content)
        if match:
            screen_x_str = match.group(1)
    
    try:
        screen_x = float(screen_x_str) if screen_x_str else None
    except:
        screen_x = None
    
    details['screen_x'] = screen_x
    
    if screen_x is not None:
        if screen_x >= expected_screen_x_min:
            score += 15
            feedback_parts.append(f"✅ Positioned right (x={screen_x:.2f})")
        elif screen_x >= 0.5:
            score += 8
            feedback_parts.append(f"⚠️ Positioned center-right (x={screen_x:.2f}), expected ≥{expected_screen_x_min}")
        else:
            feedback_parts.append(f"❌ Positioned left (x={screen_x:.2f}), expected ≥{expected_screen_x_min}")
    else:
        feedback_parts.append("❌ Could not determine X position")
    
    # ================================================================
    # CRITERION 6: Positioned in bottom portion of screen (10 points)
    # ================================================================
    screen_y_str = kml_analysis.get('screen_y_value', '')
    screen_y = None
    
    # Try to parse from KML directly
    if kml_content:
        match = re.search(r'<screenXY[^>]*y=["\']([0-9.]+)["\']', kml_content)
        if match:
            screen_y_str = match.group(1)
    
    try:
        screen_y = float(screen_y_str) if screen_y_str else None
    except:
        screen_y = None
    
    details['screen_y'] = screen_y
    
    if screen_y is not None:
        if screen_y <= expected_screen_y_max:
            score += 10
            feedback_parts.append(f"✅ Positioned bottom (y={screen_y:.2f})")
        elif screen_y <= 0.5:
            score += 5
            feedback_parts.append(f"⚠️ Positioned lower-half (y={screen_y:.2f}), expected ≤{expected_screen_y_max}")
        else:
            feedback_parts.append(f"❌ Positioned top (y={screen_y:.2f}), expected ≤{expected_screen_y_max}")
    else:
        feedback_parts.append("❌ Could not determine Y position")
    
    # ================================================================
    # CRITERION 7: Named appropriately (10 points)
    # ================================================================
    has_compass_name = kml_analysis.get('has_compass_name', False)
    
    # Also check directly
    if kml_content:
        if re.search(r'<name>[^<]*(compass|legend)[^<]*</name>', kml_content, re.IGNORECASE):
            has_compass_name = True
    
    if has_compass_name:
        score += 10
        feedback_parts.append("✅ Named appropriately (compass/legend)")
        details['proper_name'] = True
    else:
        feedback_parts.append("⚠️ Name doesn't contain 'compass' or 'legend'")
        details['proper_name'] = False
    
    # ================================================================
    # CRITERION 8: VLM Trajectory Verification (20 points)
    # Use trajectory frames to verify workflow was followed
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames (not just final screenshot!)
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames or final_screenshot:
                all_frames = (trajectory_frames or [])
                if final_screenshot and final_screenshot not in all_frames:
                    all_frames.append(final_screenshot)
                
                vlm_prompt = """You are verifying if an agent successfully created a Screen Overlay in Google Earth Pro.

The task was to create a Screen Overlay (NOT Image Overlay) with a compass rose image in the bottom-right corner.

Looking at these screenshots from the agent's workflow, determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in any of the screenshots?
2. ADD_MENU_USED: Did the agent use the Add menu (for creating overlays)?
3. SCREEN_OVERLAY_DIALOG: Is there evidence of the Screen Overlay dialog being opened/configured?
4. COMPASS_IMAGE_VISIBLE: Is a compass rose or similar navigation image visible anywhere on screen (especially in corners)?
5. PLACES_PANEL_ACTIVITY: Is there evidence of saving or organizing in the Places panel?
6. WORKFLOW_PROGRESSION: Do the frames show meaningful progression through the task (not just the same screen)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "add_menu_used": true/false,
    "screen_overlay_dialog": true/false,
    "compass_image_visible": true/false,
    "places_panel_activity": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""
                
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_frames if len(all_frames) > 1 else None,
                    image=all_frames[0] if len(all_frames) == 1 else None
                )
                
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    # Count criteria met
                    vlm_criteria = [
                        parsed.get('google_earth_visible', False),
                        parsed.get('add_menu_used', False),
                        parsed.get('screen_overlay_dialog', False),
                        parsed.get('compass_image_visible', False),
                        parsed.get('places_panel_activity', False),
                        parsed.get('workflow_progression', False)
                    ]
                    
                    criteria_met = sum(vlm_criteria)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Calculate VLM score based on criteria and confidence
                    base_vlm_score = (criteria_met / len(vlm_criteria)) * 20
                    confidence_multiplier = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    vlm_score = int(base_vlm_score * confidence_multiplier)
                    
                    score += vlm_score
                    
                    if vlm_score >= 15:
                        feedback_parts.append(f"✅ VLM: Workflow verified ({criteria_met}/6 criteria, {confidence} confidence)")
                    elif vlm_score >= 8:
                        feedback_parts.append(f"⚠️ VLM: Partial workflow evidence ({criteria_met}/6 criteria)")
                    else:
                        feedback_parts.append(f"❌ VLM: Limited workflow evidence ({criteria_met}/6 criteria)")
                    
                    details['vlm_criteria_met'] = criteria_met
                    details['vlm_confidence'] = confidence
                else:
                    feedback_parts.append("⚠️ VLM verification failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
                
        except ImportError:
            logger.warning("Could not import VLM utilities")
            feedback_parts.append("⚠️ VLM utilities not available")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Cap score at 100
    score = min(score, 100)
    
    # Determine pass/fail
    # Must have: file exists + is ScreenOverlay (not GroundOverlay) + score >= 60
    key_criteria_met = (
        file_exists and 
        has_screen_overlay and 
        not has_ground_overlay
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"✅ PASS (Score: {score}/100) | " + feedback
    else:
        if not has_screen_overlay:
            reason = "Must use ScreenOverlay (Add > Screen Overlay)"
        elif has_ground_overlay:
            reason = "Used GroundOverlay instead of ScreenOverlay"
        elif score < 60:
            reason = f"Score {score} below threshold of 60"
        else:
            reason = "Key criteria not met"
        feedback = f"❌ FAIL (Score: {score}/100) - {reason} | " + feedback
    
    details['final_score'] = score
    details['key_criteria_met'] = key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }