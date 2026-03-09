#!/usr/bin/env python3
"""
Verifier for create_mip_visualization task.

VERIFICATION STRATEGY (Multi-Signal with Anti-Gaming):

Programmatic Checks (65 points):
1. Screenshot exists at expected path (15 pts)
2. Valid PNG format with reasonable size (10 pts)
3. File created/modified DURING task - timestamp check (15 pts)
4. Image has high color variety - indicates real content (10 pts)
5. Slicer state: slab mode active with Max type (15 pts)

VLM Trajectory Verification (35 points):
6. Process verification via trajectory frames (20 pts):
   - Agent navigated to coronal view
   - Enabled slab/MIP mode
   - Shows progression of work
7. Final screenshot shows MIP characteristics (15 pts):
   - Branching vessel structures visible
   - Not single-slice appearance

Pass threshold: 60 points AND (file created during task OR slab mode confirmed)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a Maximum Intensity Projection (MIP) task in 3D Slicer medical imaging software.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful MIP creation, the agent should:
1. Have CT chest data visible in slice views (grayscale medical images)
2. Select/focus the coronal (green) slice view
3. Enable slab mode (configure slab settings in slice controller)
4. Set slab type to "Max" (MIP)
5. Adjust slab thickness
6. Save a screenshot

Look for evidence of:
- 3D Slicer interface with medical imaging data displayed
- Slice view controls/menus being accessed
- Slab mode configuration (thickness slider, type dropdown)
- Changes in the slice view appearance (MIP shows vessels as continuous bright structures)
- File save dialog or screenshot capture

Assess:
1. SLICER_WITH_DATA: Is 3D Slicer visible with CT chest data loaded?
2. SLICE_CONTROLS_ACCESSED: Are slice view controls/settings being manipulated?
3. MIP_CONFIGURATION_VISIBLE: Is there evidence of slab/MIP settings being configured?
4. VIEW_CHANGED: Does the slice view appearance change across frames (indicating MIP activation)?
5. MEANINGFUL_PROGRESSION: Do frames show real state changes, not just the same screen?

Respond in JSON format:
{
    "slicer_with_data": true/false,
    "slice_controls_accessed": true/false,
    "mip_configuration_visible": true/false,
    "view_changed": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the trajectory frames"
}
"""

MIP_CONTENT_PROMPT = """You are analyzing a screenshot that should show a Maximum Intensity Projection (MIP) visualization of a chest CT scan.

A proper coronal MIP of the chest should show:
1. VESSELS AS BRANCHING STRUCTURES: Pulmonary vessels appear as bright, branching tree-like structures extending through the lung fields (not as small dots)
2. BOTH LUNG FIELDS: The coronal view shows left and right lungs side by side
3. DEPTH PROJECTION: Unlike a single slice, MIP shows vessels traced over depth, so they appear continuous and branch-like
4. RIBS/SPINE: May appear as bright structures at edges

Single-slice appearance (NOT MIP):
- Vessels appear as small discrete dots or short segments
- Less continuous vessel visualization
- More "flat" appearance

Analyze this image:
1. IS_MIP_VISUALIZATION: Does this appear to be a Maximum Intensity Projection (vessels as branching structures)?
2. IS_CORONAL_VIEW: Is this a coronal (front-to-back) orientation showing both lung fields?
3. VESSELS_VISIBLE: Are pulmonary vessels clearly visible as branching structures?
4. IS_CHEST_CT: Does this appear to be chest CT data (lungs, ribs visible)?

Respond in JSON format:
{
    "is_mip_visualization": true/false,
    "is_coronal_view": true/false,
    "vessels_visible": true/false,
    "is_chest_ct": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see - specifically whether vessels appear as dots (single slice) or branching structures (MIP)"
}
"""


def _vlm_query(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Execute VLM query and return parsed result."""
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown') if result else 'no result'}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def verify_create_mip_visualization(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify MIP visualization task completion.
    
    Uses multiple independent signals:
    1. File existence and properties
    2. Timestamp-based anti-gaming
    3. Slicer internal state (if queryable)
    4. VLM trajectory verification
    5. VLM content analysis
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/SlicerData/Exports/chest_mip_coronal.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    min_slab_thickness = metadata.get('min_slab_thickness_mm', 30)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('screenshot_exists', 15)
    w_valid = weights.get('valid_png_format', 10)
    w_created = weights.get('created_during_task', 15)
    w_mip_mode = weights.get('mip_mode_active', 25)
    w_orientation = weights.get('coronal_orientation', 15)
    w_thickness = weights.get('adequate_slab_thickness', 10)
    w_vlm = weights.get('vlm_confirms_mip', 10)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/mip_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
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
            "feedback": f"Invalid JSON in result: {e}"
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
    
    details['export_result'] = result
    
    # ================================================================
    # CRITERION 1: Screenshot exists (15 pts)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += w_exists
        feedback_parts.append("Screenshot exists")
    else:
        feedback_parts.append("Screenshot NOT found")
        # Check for alternative outputs
        alt_outputs = result.get('alternative_outputs', '').strip()
        if alt_outputs:
            score += w_exists // 2
            feedback_parts.append(f"(alt outputs found: {alt_outputs})")
    
    # ================================================================
    # CRITERION 2: Valid PNG with reasonable size (10 pts)
    # ================================================================
    if output_exists:
        file_size_kb = result.get('output_size_bytes', 0) / 1024
        image_format = result.get('image_format', 'unknown')
        image_colors = result.get('image_colors', 0)
        
        details['file_size_kb'] = file_size_kb
        details['image_format'] = image_format
        details['image_colors'] = image_colors
        
        if image_format in ['PNG', 'JPEG', 'BMP']:
            if file_size_kb >= min_file_size_kb:
                score += w_valid
                feedback_parts.append(f"Valid {image_format} ({file_size_kb:.0f}KB)")
            elif file_size_kb >= min_file_size_kb / 2:
                score += w_valid // 2
                feedback_parts.append(f"Small {image_format} ({file_size_kb:.0f}KB)")
            else:
                feedback_parts.append(f"Very small file ({file_size_kb:.0f}KB)")
        else:
            feedback_parts.append(f"Unknown format: {image_format}")
    
    # ================================================================
    # CRITERION 3: File created during task - anti-gaming (15 pts)
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if file_created:
        score += w_created
        feedback_parts.append("File created during task")
        details['timing_verified'] = True
    elif file_modified:
        score += w_created * 3 // 4
        feedback_parts.append("File modified during task")
        details['timing_verified'] = True
    else:
        feedback_parts.append("File NOT created during task")
        details['timing_verified'] = False
    
    # ================================================================
    # CRITERION 4: Slicer state - MIP mode active (25 pts)
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    slab_mode_str = str(result.get('slab_mode_active', 'unknown')).lower()
    slab_mode_active = slab_mode_str == 'true'
    slab_type = result.get('slab_type', 'unknown')
    slab_thickness = float(result.get('slab_thickness_mm', 0))
    
    details['slicer_running'] = slicer_running
    details['slab_mode_active'] = slab_mode_active
    details['slab_type'] = slab_type
    details['slab_thickness_mm'] = slab_thickness
    
    if not slicer_running:
        feedback_parts.append("Slicer not running")
    else:
        if slab_mode_active and slab_type.lower() == 'max':
            score += w_mip_mode
            feedback_parts.append(f"MIP mode confirmed (type={slab_type})")
        elif slab_mode_active:
            score += w_mip_mode // 2
            feedback_parts.append(f"Slab mode active (type={slab_type}, not Max)")
        elif slab_mode_str == 'unknown':
            # Cannot query state - rely on other signals
            feedback_parts.append("Slab state unknown")
        else:
            feedback_parts.append("Slab mode not active")
    
    # ================================================================
    # CRITERION 5: Coronal orientation (15 pts)
    # Infer from image dimensions and Slicer state
    # ================================================================
    # Coronal views are typically wider than tall for chest CT
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    
    # For coronal chest, width > height typically (or similar)
    if image_width > 0 and image_height > 0:
        aspect = image_width / image_height
        if 0.7 < aspect < 1.5:  # Reasonable aspect for coronal view
            score += w_orientation
            feedback_parts.append(f"Reasonable aspect ratio ({aspect:.2f})")
        else:
            score += w_orientation // 2
            feedback_parts.append(f"Unusual aspect ({aspect:.2f})")
    else:
        feedback_parts.append("Cannot verify orientation")
    
    # ================================================================
    # CRITERION 6: Adequate slab thickness (10 pts)
    # ================================================================
    if slab_thickness >= min_slab_thickness:
        score += w_thickness
        feedback_parts.append(f"Slab thickness OK ({slab_thickness:.0f}mm)")
    elif slab_thickness > 0:
        score += w_thickness // 2
        feedback_parts.append(f"Thin slab ({slab_thickness:.0f}mm < {min_slab_thickness}mm)")
    elif slab_mode_str == 'unknown':
        # Give benefit of doubt if we couldn't query state
        pass
    else:
        feedback_parts.append("Slab thickness unknown/zero")
    
    # ================================================================
    # VLM VERIFICATION (if available)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            
            if trajectory_frames:
                logger.info(f"VLM: Analyzing {len(trajectory_frames)} trajectory frames")
                
                # Process verification
                process_result = _vlm_query(
                    query_vlm,
                    TRAJECTORY_PROCESS_PROMPT,
                    images=trajectory_frames
                )
                
                if process_result:
                    details['vlm_process'] = process_result
                    
                    # Score based on process verification
                    if process_result.get('meaningful_progression', False):
                        vlm_score += 8
                    if process_result.get('slicer_with_data', False):
                        vlm_score += 4
                    if process_result.get('mip_configuration_visible', False):
                        vlm_score += 4
                    if process_result.get('view_changed', False):
                        vlm_score += 4
                    
                    logger.info(f"VLM process score: {vlm_score}/20")
            
            # Content verification on final screenshot
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                content_result = _vlm_query(
                    query_vlm,
                    MIP_CONTENT_PROMPT,
                    image=final_screenshot
                )
                
                if content_result:
                    details['vlm_content'] = content_result
                    
                    content_score = 0
                    if content_result.get('is_mip_visualization', False):
                        content_score += 6
                    if content_result.get('is_coronal_view', False):
                        content_score += 3
                    if content_result.get('vessels_visible', False):
                        content_score += 3
                    if content_result.get('is_chest_ct', False):
                        content_score += 3
                    
                    vlm_score += min(content_score, 15)
                    logger.info(f"VLM content score: {content_score}/15")
            
            # Add VLM score (capped at weight)
            vlm_score = min(vlm_score, w_vlm + 25)  # Allow some extra for trajectory
            score += vlm_score
            
            if vlm_score >= 15:
                feedback_parts.append(f"VLM confirms MIP ({vlm_score}pts)")
            elif vlm_score > 0:
                feedback_parts.append(f"VLM partial ({vlm_score}pts)")
            else:
                feedback_parts.append("VLM could not confirm")
                
        except ImportError as e:
            logger.warning(f"VLM utilities not available: {e}")
            feedback_parts.append("VLM unavailable")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM error: {str(e)[:30]}")
    else:
        # No VLM available - award partial points based on image analysis
        if output_exists:
            image_colors = result.get('image_colors', 0)
            if image_colors > 1000:
                # High color variety suggests real content
                score += w_vlm // 2
                feedback_parts.append("High color variety (likely real content)")
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    max_score = 100
    score = min(score, max_score)
    
    # Key criteria for passing:
    # - File was created during task (anti-gaming)
    # - Either MIP mode confirmed OR VLM confirms MIP appearance
    timing_ok = details.get('timing_verified', False)
    mip_confirmed = (slab_mode_active and slab_type.lower() == 'max')
    vlm_confirmed = (vlm_score >= 15)
    
    key_criteria_met = timing_ok and (mip_confirmed or vlm_confirmed or (output_exists and score >= 50))
    
    passed = score >= 60 and key_criteria_met
    
    # Override: if we have strong evidence but missed timing check
    if score >= 75 and (mip_confirmed or vlm_confirmed) and output_exists:
        passed = True
        feedback_parts.append("(high confidence override)")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }