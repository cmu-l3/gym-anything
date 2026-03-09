#!/usr/bin/env python3
"""
Verifier for MIP Vessel Visualization task.

VERIFICATION STRATEGY:
1. MIP image file exists (15 points)
2. Image quality (size/dimensions) (15 points)
3. VLM: Vessel (aorta) is visible (20 points)
4. VLM: Coronal/AP projection (10 points)
5. VLM: Image has MIP appearance (10 points)
6. Parameters file exists (10 points)
7. Window/Level in clinical range (10 points)
8. Slab thickness documented (5 points)
9. Timestamp valid (anti-gaming) (5 points)

Pass threshold: 60 points with vessel visible criterion met

Uses trajectory frames for VLM verification to ensure work was actually done.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mip_vessel_visualization(traj, env_info, task_info):
    """
    Verify MIP vessel visualization task completion.
    
    Uses copy_from_env to read result files from container.
    Uses VLM with trajectory frames to verify visual outputs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata for scoring weights and thresholds
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    window_range = metadata.get('window_range', {'min': 300, 'max': 800})
    level_range = metadata.get('level_range', {'min': 100, 'max': 300})
    slab_range = metadata.get('slab_thickness_range', {'min': 50, 'max': 200})
    min_image_size_kb = metadata.get('min_image_size_kb', 100)
    
    # Default weights
    w_mip_exists = weights.get('mip_image_exists', 15)
    w_image_quality = weights.get('image_quality', 15)
    w_vessel_visible = weights.get('vessel_visible', 20)
    w_coronal = weights.get('coronal_projection', 10)
    w_mip_appearance = weights.get('mip_appearance', 10)
    w_params_exists = weights.get('params_file_exists', 10)
    w_window_level = weights.get('window_level_appropriate', 10)
    w_slab = weights.get('slab_thickness_documented', 5)
    w_timestamp = weights.get('timestamp_valid', 5)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # LOAD RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/mip_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info(f"Loaded result: {result}")
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("⚠ Slicer was not running")
    
    # ================================================================
    # CRITERION 1: MIP Image Exists (15 points)
    # ================================================================
    mip_exists = result.get('mip_image_exists', False)
    details['mip_exists'] = mip_exists
    
    if mip_exists:
        score += w_mip_exists
        feedback_parts.append(f"✓ MIP image file exists (+{w_mip_exists})")
    else:
        feedback_parts.append("✗ MIP image file not found")
        # Cannot continue meaningful verification without the image
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Image Quality (15 points)
    # ================================================================
    mip_size_bytes = result.get('mip_image_size_bytes', 0)
    mip_size_kb = mip_size_bytes / 1024
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    image_format = result.get('image_format', 'unknown')
    
    details['image_size_kb'] = mip_size_kb
    details['image_dimensions'] = f"{image_width}x{image_height}"
    details['image_format'] = image_format
    
    # Check file size (rendered image should be substantial)
    if mip_size_kb >= min_image_size_kb:
        score += w_image_quality
        feedback_parts.append(f"✓ Image quality OK ({mip_size_kb:.1f}KB, {image_width}x{image_height}) (+{w_image_quality})")
    elif mip_size_kb >= 50:
        partial = w_image_quality // 2
        score += partial
        feedback_parts.append(f"~ Image is small ({mip_size_kb:.1f}KB) (+{partial})")
    else:
        feedback_parts.append(f"✗ Image too small ({mip_size_kb:.1f}KB)")
    
    # ================================================================
    # CRITERION 3-5: VLM Visual Verification (40 points total)
    # ================================================================
    vessel_visible = False
    query_vlm = env_info.get('query_vlm')
    
    # Copy MIP image from container for VLM verification
    temp_mip = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    mip_image_path = None
    try:
        copy_from_env("/tmp/aorta_mip.png", temp_mip.name)
        mip_image_path = temp_mip.name
        logger.info(f"Copied MIP image for VLM verification: {mip_image_path}")
    except Exception as e:
        logger.warning(f"Could not copy MIP image for VLM: {e}")
    
    # Get trajectory frames for verification (proves work was done)
    trajectory_frames = []
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        trajectory_frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            trajectory_frames.append(final_screenshot)
        logger.info(f"Got {len(trajectory_frames)} trajectory frames for VLM")
    except ImportError:
        logger.warning("Could not import trajectory frame utilities")
    except Exception as e:
        logger.warning(f"Could not get trajectory frames: {e}")
    
    if query_vlm and mip_image_path and os.path.exists(mip_image_path):
        # ============================================================
        # VLM Query 1: Is vessel (aorta) visible? (20 points)
        # ============================================================
        vessel_prompt = """Examine this medical imaging visualization carefully.

Is there a bright, tubular vessel structure (like an aorta - a large blood vessel) clearly visible in the image?

Look for:
- A bright white or light gray tubular structure
- Vertically oriented vessel (running top to bottom)
- Cylindrical/tube-like appearance

This should be a Maximum Intensity Projection (MIP) showing vessels as bright structures against darker background.

Answer ONLY 'yes' or 'no'."""
        
        try:
            vessel_result = query_vlm(prompt=vessel_prompt, image=mip_image_path)
            logger.info(f"Vessel visibility VLM result: {vessel_result}")
            
            if vessel_result.get('success', False):
                response_text = vessel_result.get('response', vessel_result.get('parsed', {}).get('answer', ''))
                if isinstance(response_text, dict):
                    response_text = str(response_text)
                
                if 'yes' in response_text.lower():
                    score += w_vessel_visible
                    vessel_visible = True
                    feedback_parts.append(f"✓ Vessel (aorta) is clearly visible (+{w_vessel_visible})")
                    details['vessel_visible'] = True
                else:
                    feedback_parts.append("✗ Vessel not clearly visible in image")
                    details['vessel_visible'] = False
            else:
                feedback_parts.append(f"~ VLM vessel check failed: {vessel_result.get('error', 'unknown')}")
                details['vessel_visible'] = 'unknown'
        except Exception as e:
            logger.error(f"VLM vessel query failed: {e}")
            feedback_parts.append(f"~ Could not verify vessel visibility: {e}")
            details['vessel_visible'] = 'error'
        
        # ============================================================
        # VLM Query 2: Is it coronal/AP projection? (10 points)
        # ============================================================
        projection_prompt = """Examine this medical imaging visualization of blood vessels.

Does this appear to be a CORONAL (front-to-back / AP / anteroposterior) view?

In a coronal view:
- You would see the vessel running vertically (top to bottom)
- It's as if you're looking at the patient from the front
- The aorta would appear as a vertical tube

Answer ONLY 'yes' or 'no'."""
        
        try:
            projection_result = query_vlm(prompt=projection_prompt, image=mip_image_path)
            logger.info(f"Projection VLM result: {projection_result}")
            
            if projection_result.get('success', False):
                response_text = projection_result.get('response', projection_result.get('parsed', {}).get('answer', ''))
                if isinstance(response_text, dict):
                    response_text = str(response_text)
                
                if 'yes' in response_text.lower():
                    score += w_coronal
                    feedback_parts.append(f"✓ Coronal projection confirmed (+{w_coronal})")
                    details['coronal_projection'] = True
                else:
                    feedback_parts.append("~ Projection may not be coronal")
                    details['coronal_projection'] = False
            else:
                feedback_parts.append(f"~ VLM projection check failed")
                details['coronal_projection'] = 'unknown'
        except Exception as e:
            logger.error(f"VLM projection query failed: {e}")
            feedback_parts.append(f"~ Could not verify projection angle: {e}")
        
        # ============================================================
        # VLM Query 3: Does it look like MIP? (10 points)
        # ============================================================
        mip_prompt = """Examine this medical imaging visualization.

Does this appear to be a Maximum Intensity Projection (MIP) or similar volume rendering technique, rather than a simple 2D slice view?

MIP characteristics:
- Vessels appear as projected/thick bright structures (not thin lines)
- Has some sense of depth/thickness visible
- Bright structures (like vessels or bones) stand out against darker background
- NOT a flat 2D slice through tissue

Answer ONLY 'yes' or 'no'."""
        
        try:
            mip_result = query_vlm(prompt=mip_prompt, image=mip_image_path)
            logger.info(f"MIP appearance VLM result: {mip_result}")
            
            if mip_result.get('success', False):
                response_text = mip_result.get('response', mip_result.get('parsed', {}).get('answer', ''))
                if isinstance(response_text, dict):
                    response_text = str(response_text)
                
                if 'yes' in response_text.lower():
                    score += w_mip_appearance
                    feedback_parts.append(f"✓ Image has MIP characteristics (+{w_mip_appearance})")
                    details['mip_appearance'] = True
                else:
                    feedback_parts.append("~ Image may not be a proper MIP")
                    details['mip_appearance'] = False
            else:
                feedback_parts.append("~ VLM MIP check failed")
                details['mip_appearance'] = 'unknown'
        except Exception as e:
            logger.error(f"VLM MIP query failed: {e}")
            feedback_parts.append(f"~ Could not verify MIP rendering: {e}")
    else:
        feedback_parts.append("~ VLM verification not available or image not found")
        details['vlm_available'] = False
    
    # Clean up temp MIP file
    if mip_image_path and os.path.exists(mip_image_path):
        try:
            os.unlink(mip_image_path)
        except:
            pass
    
    # ================================================================
    # CRITERION 6: Parameters File Exists (10 points)
    # ================================================================
    params_exists = result.get('params_file_exists', False)
    details['params_exists'] = params_exists
    
    if params_exists:
        score += w_params_exists
        feedback_parts.append(f"✓ Parameters file exists (+{w_params_exists})")
    else:
        feedback_parts.append("✗ Parameters file not found")
    
    # ================================================================
    # CRITERION 7: Window/Level Appropriate (10 points)
    # ================================================================
    window_width = result.get('window_width', 0)
    window_level = result.get('window_level', 0)
    
    details['window_width'] = window_width
    details['window_level'] = window_level
    
    window_ok = window_range['min'] <= window_width <= window_range['max']
    level_ok = level_range['min'] <= window_level <= level_range['max']
    
    if window_ok and level_ok:
        score += w_window_level
        feedback_parts.append(f"✓ Window/Level in clinical range (W:{window_width}, L:{window_level}) (+{w_window_level})")
    elif window_width > 0 and window_level > 0:
        partial = w_window_level // 2
        score += partial
        feedback_parts.append(f"~ Window/Level documented but outside optimal range (W:{window_width}, L:{window_level}) (+{partial})")
    else:
        feedback_parts.append("✗ Window/Level not properly documented")
    
    # ================================================================
    # CRITERION 8: Slab Thickness Documented (5 points)
    # ================================================================
    slab_thickness = result.get('slab_thickness', 0)
    details['slab_thickness'] = slab_thickness
    
    if slab_range['min'] < slab_thickness < slab_range['max']:
        score += w_slab
        feedback_parts.append(f"✓ Slab thickness reasonable ({slab_thickness}mm) (+{w_slab})")
    elif slab_thickness > 0:
        partial = w_slab // 2
        score += partial
        feedback_parts.append(f"~ Slab thickness documented but unusual ({slab_thickness}mm) (+{partial})")
    else:
        feedback_parts.append("✗ Slab thickness not documented")
    
    # ================================================================
    # CRITERION 9: Image Timestamp Valid - Anti-gaming (5 points)
    # ================================================================
    mip_created_during_task = result.get('mip_created_during_task', False)
    details['created_during_task'] = mip_created_during_task
    
    if mip_created_during_task:
        score += w_timestamp
        feedback_parts.append(f"✓ Image created during task (+{w_timestamp})")
    else:
        feedback_parts.append("✗ Image may be pre-existing (timestamp before task start)")
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    # Pass requires score >= 60 AND vessel visible
    passed = score >= 60 and vessel_visible
    
    details['final_score'] = score
    details['vessel_criterion_met'] = vessel_visible
    
    status = "PASS" if passed else "FAIL"
    feedback_parts.append(f"\n{status}: Final Score: {score}/100")
    
    if passed:
        feedback_parts.append("Task completed successfully - MIP visualization created with visible aorta")
    else:
        if not vessel_visible:
            feedback_parts.append("Key criterion not met: Vessel must be clearly visible in MIP image")
        if score < 60:
            feedback_parts.append(f"Score below threshold: {score} < 60")
        feedback_parts.append("Task not completed - review MIP settings and visibility")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }