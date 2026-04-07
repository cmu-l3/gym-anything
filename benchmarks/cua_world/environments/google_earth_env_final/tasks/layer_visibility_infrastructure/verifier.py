#!/usr/bin/env python3
"""
Verifier for layer_visibility_infrastructure task.

MULTI-SIGNAL VERIFICATION:
1. Output file exists and is valid PNG (15 points)
2. File was created during task execution (10 points) - anti-gaming
3. File size reasonable for screenshot (5 points)
4. VLM: Shows San Francisco (20 points)
5. VLM: 3D buildings visible (20 points)
6. VLM: Roads visible (10 points)
7. VLM: Labels minimized (15 points)
8. VLM: 3D perspective/tilted view (5 points)

Pass threshold: 60 points with file created AND shows San Francisco
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring layer visibility in Google Earth Pro.

The task was to:
1. Navigate to San Francisco, California
2. Enable 3D Buildings layer
3. Enable Roads layer
4. Disable Borders and Labels layer
5. Disable Places layer
6. Tilt view for 3D perspective
7. Save a screenshot

Examine these trajectory frames (chronologically ordered, earliest to latest) and determine:

1. WORKFLOW_PROGRESS: Did the agent show meaningful progression through the task? (navigation, layer panel interaction, view adjustment)
2. SEARCH_PERFORMED: At any point, did the agent appear to use the search functionality?
3. LAYER_PANEL_INTERACTION: At any point, is the Layers panel visible or being interacted with?
4. SAN_FRANCISCO_REACHED: At any point, does the view show San Francisco (urban area, bay, distinctive grid)?

Respond in JSON format:
{
    "workflow_progress": true/false,
    "search_performed": true/false,
    "layer_panel_interaction": true/false,
    "san_francisco_reached": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observed across the frames"
}
"""

FINAL_OUTPUT_VERIFICATION_PROMPT = """You are verifying a screenshot saved from Google Earth Pro showing San Francisco infrastructure.

The task requirements were:
- Show San Francisco, California
- 3D Buildings layer enabled (buildings should have height/depth)
- Roads layer enabled (street network visible)
- Borders and Labels layer DISABLED (minimal text/labels)
- Places layer DISABLED (no POI icons/markers)
- Tilted 3D perspective view (not top-down)

Examine this screenshot and evaluate each criterion:

1. SHOWS_SAN_FRANCISCO: Is this San Francisco? Look for distinctive bay area geography, urban grid, recognizable features (Golden Gate Bridge area, downtown skyline, bay).

2. 3D_BUILDINGS_VISIBLE: Are 3D buildings visible (buildings shown with actual height and depth, casting shadows, not flat 2D)?

3. ROADS_VISIBLE: Is the road/street network visible (lines showing streets and transportation routes)?

4. LABELS_MINIMIZED: Is the image mostly FREE of text labels for place names, streets, landmarks? A clean visualization should have minimal overlaid text.

5. PERSPECTIVE_TILTED: Is the view tilted to show a 3D perspective (camera angled to show building heights) rather than straight-down orthographic view?

Respond in JSON format:
{
    "shows_san_francisco": true/false,
    "buildings_3d_visible": true/false,
    "roads_visible": true/false,
    "labels_minimized": true/false,
    "perspective_tilted": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observe"
}
"""


def verify_layer_visibility_infrastructure(traj, env_info, task_info):
    """
    Verify infrastructure layer analysis task completion.
    
    Uses file-based checks combined with VLM verification on both
    trajectory frames and the final output image.
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
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/sf_infrastructure.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['task_result'] = result
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
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    image_valid = result.get('image_valid', False)
    image_format = result.get('image_format', 'unknown')
    
    if output_exists and image_valid:
        score += 15
        feedback_parts.append(f"✅ Output file exists ({image_format})")
    elif output_exists:
        score += 8
        feedback_parts.append(f"⚠️ Output file exists but may be invalid ({image_format})")
    else:
        feedback_parts.append("❌ Output file NOT found")
        # Can't verify much without the output file
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
        feedback_parts.append("✅ File created during task execution")
    else:
        feedback_parts.append("❌ File not created during task (possible pre-existing or gaming)")
    
    # ================================================================
    # CRITERION 3: File size reasonable (5 points)
    # ================================================================
    file_size_bytes = result.get('output_size_bytes', 0)
    file_size_kb = file_size_bytes / 1024
    
    if file_size_kb >= min_file_size_kb:
        score += 5
        feedback_parts.append(f"✅ File size OK ({file_size_kb:.1f}KB)")
    elif file_size_kb >= 50:
        score += 3
        feedback_parts.append(f"⚠️ File size borderline ({file_size_kb:.1f}KB)")
    else:
        feedback_parts.append(f"❌ File too small ({file_size_kb:.1f}KB)")
    
    # ================================================================
    # STEP 2: Copy output image for VLM verification
    # ================================================================
    output_image_path = None
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        # Try the copy in /tmp first (more reliable)
        copy_from_env("/tmp/sf_infrastructure_output.png", temp_output.name)
        output_image_path = temp_output.name
    except Exception as e:
        logger.warning(f"Could not copy output from /tmp: {e}")
        try:
            copy_from_env(expected_output_path, temp_output.name)
            output_image_path = temp_output.name
        except Exception as e2:
            logger.warning(f"Could not copy output from expected path: {e2}")
    
    # ================================================================
    # VLM VERIFICATION
    # ================================================================
    vlm_score = 0
    
    if query_vlm and output_image_path and os.path.exists(output_image_path):
        # ============================================================
        # CRITERION 4-8: VLM verification on output image
        # ============================================================
        try:
            vlm_result = query_vlm(
                prompt=FINAL_OUTPUT_VERIFICATION_PROMPT,
                image=output_image_path
            )
            result_details['vlm_output_result'] = vlm_result
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                confidence = parsed.get('confidence', 'low')
                confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                
                # Criterion 4: Shows San Francisco (20 points)
                if parsed.get('shows_san_francisco', False):
                    points = int(20 * confidence_mult)
                    vlm_score += points
                    feedback_parts.append(f"✅ Shows San Francisco ({points}pts)")
                else:
                    feedback_parts.append("❌ San Francisco not identified")
                
                # Criterion 5: 3D buildings visible (20 points)
                if parsed.get('buildings_3d_visible', False):
                    points = int(20 * confidence_mult)
                    vlm_score += points
                    feedback_parts.append(f"✅ 3D buildings visible ({points}pts)")
                else:
                    feedback_parts.append("❌ 3D buildings not visible")
                
                # Criterion 6: Roads visible (10 points)
                if parsed.get('roads_visible', False):
                    points = int(10 * confidence_mult)
                    vlm_score += points
                    feedback_parts.append(f"✅ Roads visible ({points}pts)")
                else:
                    feedback_parts.append("❌ Roads not visible")
                
                # Criterion 7: Labels minimized (15 points)
                if parsed.get('labels_minimized', False):
                    points = int(15 * confidence_mult)
                    vlm_score += points
                    feedback_parts.append(f"✅ Labels minimized ({points}pts)")
                else:
                    feedback_parts.append("❌ Too many labels visible")
                
                # Criterion 8: 3D perspective (5 points)
                if parsed.get('perspective_tilted', False):
                    points = int(5 * confidence_mult)
                    vlm_score += points
                    feedback_parts.append(f"✅ 3D perspective ({points}pts)")
                else:
                    feedback_parts.append("❌ Not tilted perspective")
                
                # Add VLM reasoning to details
                result_details['vlm_reasoning'] = parsed.get('reasoning', '')
            else:
                feedback_parts.append(f"⚠️ VLM output verification failed: {vlm_result.get('error', 'unknown')}")
        
        except Exception as e:
            logger.error(f"VLM output verification error: {e}")
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
        
        # ============================================================
        # TRAJECTORY VERIFICATION (bonus confidence)
        # ============================================================
        try:
            # Import trajectory frame sampling
            from gym_anything.vlm import sample_trajectory_frames
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            if trajectory_frames and len(trajectory_frames) > 0:
                traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                result_details['vlm_trajectory_result'] = traj_result
                
                if traj_result.get('success'):
                    traj_parsed = traj_result.get('parsed', {})
                    
                    # Trajectory verification is supplementary - adds confidence
                    workflow_good = traj_parsed.get('workflow_progress', False)
                    sf_reached = traj_parsed.get('san_francisco_reached', False)
                    
                    if workflow_good and sf_reached:
                        result_details['trajectory_verification'] = 'passed'
                    else:
                        result_details['trajectory_verification'] = 'partial'
        
        except ImportError:
            logger.warning("Could not import trajectory frame sampling")
        except Exception as e:
            logger.warning(f"Trajectory verification error: {e}")
    
    else:
        feedback_parts.append("⚠️ VLM verification not available")
    
    # Clean up temp files
    if output_image_path and os.path.exists(output_image_path):
        try:
            os.unlink(output_image_path)
        except:
            pass
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score += vlm_score
    
    # Key criteria for passing
    key_criteria_met = (
        output_exists and 
        file_created_during_task and
        vlm_score >= 20  # At least San Francisco identified
    )
    
    # Pass threshold: 60 points with key criteria
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {score}/100"
    
    result_details['file_checks'] = {
        'output_exists': output_exists,
        'file_created_during_task': file_created_during_task,
        'file_size_kb': file_size_kb,
        'image_valid': image_valid
    }
    result_details['vlm_score'] = vlm_score
    result_details['key_criteria_met'] = key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result_details
    }