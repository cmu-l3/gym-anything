#!/usr/bin/env python3
"""
Verifier for export_slice_image task.

VERIFICATION STRATEGY:
Uses multiple independent signals to prevent gaming:

1. File existence and validity (programmatic) - 45 points
   - Output file exists at expected path (20 pts)
   - Valid PNG format with reasonable dimensions (15 pts)
   - File size indicates actual content (10 pts)

2. Anti-gaming timestamp check (programmatic) - 10 points
   - File was created/modified during task execution

3. VLM content verification (visual) - 45 points
   - Uses TRAJECTORY frames to verify work was done
   - Final image shows brain anatomy (20 pts)
   - Lateral ventricles are visible (25 pts)

Pass threshold: 70 points with file existence confirmed
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _copy_file_from_container(copy_from_env, container_path: str, suffix: str = '') -> Tuple[bool, str, Optional[str]]:
    """
    Copy a file from the container to a temporary location.
    
    Returns: (success, temp_path, error_message)
    """
    if not copy_from_env:
        return False, '', 'copy_from_env not available'
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        copy_from_env(container_path, temp_path)
        if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
            return True, temp_path, None
        else:
            return False, temp_path, 'File empty or not found'
    except Exception as e:
        return False, temp_path, str(e)


def _verify_png_image(image_path: str, min_width: int = 256, min_height: int = 256, min_size_kb: float = 30) -> Dict[str, Any]:
    """
    Verify that a file is a valid PNG image with acceptable dimensions.
    
    Returns dict with: valid, width, height, format, size_kb, error
    """
    result = {
        'valid': False,
        'width': 0,
        'height': 0,
        'format': 'unknown',
        'size_kb': 0,
        'error': None
    }
    
    try:
        from PIL import Image
        
        # Check file size
        size_bytes = os.path.getsize(image_path)
        result['size_kb'] = size_bytes / 1024
        
        # Open and validate image
        img = Image.open(image_path)
        result['width'] = img.width
        result['height'] = img.height
        result['format'] = img.format
        
        # Check if PNG
        if img.format != 'PNG':
            result['error'] = f'Not PNG format (got {img.format})'
            img.close()
            return result
        
        # Check dimensions
        if img.width < min_width or img.height < min_height:
            result['error'] = f'Image too small ({img.width}x{img.height} < {min_width}x{min_height})'
            img.close()
            return result
        
        # Check file size
        if result['size_kb'] < min_size_kb:
            result['error'] = f'File too small ({result["size_kb"]:.1f}KB < {min_size_kb}KB)'
            img.close()
            return result
        
        result['valid'] = True
        img.close()
        
    except Exception as e:
        result['error'] = str(e)
    
    return result


def _vlm_verify_brain_content(query_vlm, image_path: str) -> Dict[str, Any]:
    """
    Use VLM to verify that the image shows brain anatomy with ventricles.
    
    Returns dict with: brain_visible, ventricles_visible, confidence, reasoning
    """
    result = {
        'brain_visible': False,
        'ventricles_visible': False,
        'axial_orientation': False,
        'confidence': 'low',
        'reasoning': 'VLM verification not performed'
    }
    
    if not query_vlm or not os.path.exists(image_path):
        return result
    
    prompt = """You are analyzing a medical image that should be an exported axial slice from a brain MRI.

Examine this image carefully and determine:

1. BRAIN_ANATOMY: Does this image show brain tissue? Look for:
   - Gray matter (darker gray at the periphery)
   - White matter (lighter gray in the interior)
   - General brain structure (not a blank image, not just noise)

2. VENTRICLES: Are the lateral ventricles visible? The lateral ventricles appear as:
   - Dark (black) fluid-filled cavities
   - Located in the center of the brain
   - Often butterfly-shaped or crescent-shaped
   - Bilateral (appearing on both left and right sides)

3. ORIENTATION: Does this appear to be an axial slice (viewing from above/below)?
   - Axial shows the brain as if looking down from the top of the head
   - The front (nose) would be at top or bottom
   - Both hemispheres visible side by side

Respond in JSON format:
{
    "brain_anatomy_visible": true/false,
    "ventricles_visible": true/false,
    "appears_axial": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you see in the image"
}"""

    try:
        vlm_result = query_vlm(prompt=prompt, image=image_path)
        
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            result['brain_visible'] = parsed.get('brain_anatomy_visible', False)
            result['ventricles_visible'] = parsed.get('ventricles_visible', False)
            result['axial_orientation'] = parsed.get('appears_axial', False)
            result['confidence'] = parsed.get('confidence', 'low')
            result['reasoning'] = parsed.get('reasoning', 'No reasoning provided')
        else:
            result['reasoning'] = f"VLM query failed: {vlm_result.get('error', 'unknown error')}"
            
    except Exception as e:
        result['reasoning'] = f"VLM exception: {str(e)}"
    
    return result


def _vlm_verify_trajectory(query_vlm, sample_trajectory_frames, traj) -> Dict[str, Any]:
    """
    Use VLM to verify the agent performed actual work by examining trajectory frames.
    
    Returns dict with: work_performed, slicer_used, navigation_visible, confidence
    """
    result = {
        'work_performed': False,
        'slicer_visible': False,
        'navigation_visible': False,
        'export_action_visible': False,
        'confidence': 'low',
        'reasoning': 'Trajectory verification not performed'
    }
    
    if not query_vlm or not sample_trajectory_frames:
        return result
    
    try:
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        
        if not frames or len(frames) < 2:
            result['reasoning'] = 'Insufficient trajectory frames'
            return result
        
        prompt = """You are analyzing a sequence of screenshots showing an agent working in 3D Slicer medical imaging software.

The task was to export an axial brain slice image showing the lateral ventricles.

Examine these screenshots in order (earliest to latest) and determine:

1. SLICER_VISIBLE: Is 3D Slicer application visible in any frames?
   - Look for the characteristic Slicer interface with slice views (red/yellow/green borders)
   - Medical imaging data displayed

2. NAVIGATION_PERFORMED: Did the agent navigate/scroll through slices?
   - Look for different slice positions across frames
   - Changes in the displayed anatomy

3. EXPORT_ACTION: Is there evidence of export/capture action?
   - Screen Capture module dialog
   - File save dialog
   - Right-click context menu

4. MEANINGFUL_WORK: Did the agent perform meaningful work (not just idle)?
   - State changes between frames
   - UI interactions visible

Respond in JSON format:
{
    "slicer_visible": true/false,
    "navigation_performed": true/false,
    "export_action_visible": true/false,
    "meaningful_work_done": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}"""

        vlm_result = query_vlm(prompt=prompt, images=frames)
        
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            result['slicer_visible'] = parsed.get('slicer_visible', False)
            result['navigation_visible'] = parsed.get('navigation_performed', False)
            result['export_action_visible'] = parsed.get('export_action_visible', False)
            result['work_performed'] = parsed.get('meaningful_work_done', False)
            result['confidence'] = parsed.get('confidence', 'low')
            result['reasoning'] = parsed.get('observations', 'No observations')
        else:
            result['reasoning'] = f"VLM trajectory query failed: {vlm_result.get('error', 'unknown')}"
            
    except Exception as e:
        result['reasoning'] = f"Trajectory VLM exception: {str(e)}"
    
    return result


def verify_export_slice_image(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the export_slice_image task.
    
    Multi-criteria scoring:
    - File exists and is valid PNG: 35 points
    - Created during task (anti-gaming): 10 points  
    - VLM: Brain anatomy visible: 20 points
    - VLM: Ventricles visible: 25 points
    - VLM: Trajectory shows work: 10 points
    
    Total: 100 points
    Pass threshold: 70 points with file existence
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification framework error: copy_from_env not available"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/SlicerData/Exports/ventricles_axial.png')
    min_size_kb = metadata.get('min_file_size_kb', 30)
    min_width = metadata.get('min_image_width', 256)
    min_height = metadata.get('min_image_height', 256)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # STEP 1: Copy and read result JSON from container
    # ================================================================
    success, result_path, error = _copy_file_from_container(
        copy_from_env, '/tmp/task_result.json', '.json'
    )
    
    result = {}
    if success:
        try:
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse result JSON: {e}")
    else:
        logger.warning(f"Could not copy result JSON: {error}")
    
    if os.path.exists(result_path):
        os.unlink(result_path)
    
    details['export_result'] = result
    
    # ================================================================
    # CRITERION 1: File exists (20 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 20
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("OUTPUT FILE NOT FOUND")
        # Early exit - no file means task fundamentally incomplete
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Valid PNG with acceptable dimensions (15 points)
    # ================================================================
    # Copy the exported image for verification
    success, image_path, error = _copy_file_from_container(
        copy_from_env, '/tmp/exported_slice.png', '.png'
    )
    
    image_valid = False
    if success:
        png_check = _verify_png_image(image_path, min_width, min_height, min_size_kb)
        details['png_validation'] = png_check
        
        if png_check['valid']:
            score += 15
            feedback_parts.append(f"Valid PNG ({png_check['width']}x{png_check['height']}, {png_check['size_kb']:.1f}KB)")
            image_valid = True
        elif png_check['format'] == 'PNG':
            # It's PNG but failed other checks
            score += 8
            feedback_parts.append(f"PNG format but {png_check['error']}")
        else:
            feedback_parts.append(f"Invalid image: {png_check['error']}")
    else:
        feedback_parts.append(f"Could not copy image for validation: {error}")
        # Try using result data
        if result.get('image_format') == 'PNG':
            score += 5
            feedback_parts.append("PNG format (from metadata)")
    
    # ================================================================
    # CRITERION 3: Created during task - anti-gaming (10 points)
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if file_created:
        score += 10
        feedback_parts.append("File created during task")
        details['timestamp_check'] = 'created'
    elif file_modified:
        score += 7
        feedback_parts.append("File modified during task")
        details['timestamp_check'] = 'modified'
    else:
        feedback_parts.append("WARNING: File may pre-exist (not created during task)")
        details['timestamp_check'] = 'pre-existing'
    
    # ================================================================
    # CRITERION 4: VLM - Brain anatomy visible (20 points)
    # ================================================================
    vlm_content_result = {'brain_visible': False, 'ventricles_visible': False}
    
    if query_vlm and image_valid and os.path.exists(image_path):
        vlm_content_result = _vlm_verify_brain_content(query_vlm, image_path)
        details['vlm_content'] = vlm_content_result
        
        if vlm_content_result['brain_visible']:
            score += 20
            feedback_parts.append("VLM: Brain anatomy confirmed")
        else:
            feedback_parts.append(f"VLM: Brain not detected ({vlm_content_result['reasoning'][:50]})")
    else:
        feedback_parts.append("VLM content check skipped")
        details['vlm_content'] = {'skipped': True, 'reason': 'VLM not available or image invalid'}
    
    # ================================================================
    # CRITERION 5: VLM - Ventricles visible (25 points)
    # ================================================================
    if vlm_content_result.get('ventricles_visible', False):
        score += 25
        feedback_parts.append("VLM: Ventricles visible")
    elif vlm_content_result.get('brain_visible', False):
        # Brain visible but no ventricles - partial credit
        score += 10
        feedback_parts.append("VLM: Brain visible but ventricles unclear")
    else:
        feedback_parts.append("VLM: Ventricles not confirmed")
    
    # ================================================================
    # CRITERION 6: Trajectory verification (10 points)
    # ================================================================
    if query_vlm and sample_trajectory_frames:
        traj_result = _vlm_verify_trajectory(query_vlm, sample_trajectory_frames, traj)
        details['vlm_trajectory'] = traj_result
        
        if traj_result.get('work_performed', False):
            score += 10
            feedback_parts.append("Trajectory: Work verified")
        elif traj_result.get('slicer_visible', False):
            score += 5
            feedback_parts.append("Trajectory: Slicer visible")
        else:
            feedback_parts.append(f"Trajectory: {traj_result.get('reasoning', 'unclear')[:40]}")
    else:
        feedback_parts.append("Trajectory check skipped")
        details['vlm_trajectory'] = {'skipped': True}
    
    # Clean up temp file
    if image_path and os.path.exists(image_path):
        os.unlink(image_path)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria for passing: file exists + (created during task OR VLM confirms brain)
    key_criteria_met = (
        output_exists and 
        (file_created or file_modified or vlm_content_result.get('brain_visible', False))
    )
    
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }