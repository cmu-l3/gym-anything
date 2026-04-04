#!/usr/bin/env python3
"""
Verifier for GIMP 45-degree rotation task.
Checks if image was rotated by exactly 45 degrees using multiple detection methods.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")

# Try to import optional libraries for advanced detection
try:
    from scipy.ndimage import rotate as scipy_rotate
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False
    logging.warning("SciPy not available, using basic rotation detection")

try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logging.warning("OpenCV not available, using basic edge detection")

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SKIMAGE = True
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
        HAS_SKIMAGE = True
    except ImportError:
        HAS_SKIMAGE = False
        logging.warning("scikit-image not available, using basic similarity")

logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def detect_rotation_by_template_matching(original_img, result_img):
    """
    Detect rotation angle using template matching with reference rotations.
    """
    if not HAS_SKIMAGE:
        logging.debug("SSIM not available for template matching")
        return None, 0.0
    
    # Convert to same mode and size
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Test different rotation angles around 45°
    test_angles = [42, 43, 44, 45, 46, 47, 48]
    best_angle = None
    best_similarity = 0.0
    
    for angle in test_angles:
        try:
            # Create reference rotation
            reference = original_img.rotate(angle, expand=True, fillcolor=(128, 128, 128))
            
            # Resize to match result if needed
            if reference.size != result_img.size:
                reference = reference.resize(result_img.size)
            
            # Calculate SSIM
            ref_array = np.array(reference)
            res_array = np.array(result_img)
            
            if ref_array.shape != res_array.shape:
                continue
            
            try:
                # Try newer SSIM API first
                similarity = ssim(ref_array, res_array, channel_axis=2)
            except TypeError:
                # Fall back to older API
                similarity = ssim(ref_array, res_array, multichannel=True)
            
            if similarity > best_similarity:
                best_similarity = similarity
                best_angle = angle
                
        except Exception as e:
            logging.debug(f"Template matching failed for angle {angle}: {e}")
            continue
    
    return best_angle, best_similarity


def detect_rotation_by_edge_analysis(original_img, result_img):
    """
    Detect rotation by analyzing dominant edge orientations.
    """
    def get_dominant_edge_angles(img):
        """Extract dominant edge orientations from an image."""
        if img.mode != 'L':
            img = img.convert('L')
        
        img_array = np.array(img)
        
        if HAS_CV2:
            # Use OpenCV for better edge detection
            edges = cv2.Canny(img_array, 50, 150)
            
            # Find lines using Hough transform
            lines = cv2.HoughLines(edges, 1, np.pi/180, threshold=100)
            
            if lines is not None:
                angles = []
                for rho, theta in lines[:, 0]:
                    angle_deg = np.degrees(theta)
                    angles.append(angle_deg)
                
                if angles:
                    # Find the most common angle
                    angles = np.array(angles)
                    # Convert to 0-180 range
                    angles = angles % 180
                    hist, bins = np.histogram(angles, bins=18)  # 10-degree bins
                    dominant_angle = bins[np.argmax(hist)]
                    return dominant_angle
        
        # Fallback: simple gradient-based edge detection
        # Calculate gradients
        grad_x = np.gradient(img_array, axis=1)
        grad_y = np.gradient(img_array, axis=0)
        
        # Calculate angle at each pixel
        angles = np.arctan2(grad_y, grad_x)
        angles_deg = np.degrees(angles)
        
        # Find most common angle (mode)
        angles_deg = angles_deg.flatten()
        angles_deg = angles_deg[np.abs(grad_x.flatten()) + np.abs(grad_y.flatten()) > 10]  # Filter weak edges
        
        if len(angles_deg) > 0:
            hist, bins = np.histogram(angles_deg, bins=36)  # 10-degree bins
            dominant_angle = bins[np.argmax(hist)]
            return dominant_angle % 180
        
        return None
    
    # Get dominant angles from both images
    orig_angle = get_dominant_edge_angles(original_img)
    result_angle = get_dominant_edge_angles(result_img)
    
    if orig_angle is not None and result_angle is not None:
        # Calculate rotation difference
        angle_diff = (result_angle - orig_angle) % 360
        if angle_diff > 180:
            angle_diff -= 360
        return angle_diff
    
    return None


def detect_rotation_by_corner_analysis(original_img, result_img):
    """
    Detect rotation by analyzing corner positions (simple geometric approach).
    """
    if original_img.size != result_img.size:
        return None
    
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Find center of mass to detect rotation
    y_coords, x_coords = np.mgrid[0:orig_array.shape[0], 0:orig_array.shape[1]]
    
    # Weight by intensity difference from mean
    orig_weights = np.abs(orig_array - np.mean(orig_array))
    result_weights = np.abs(result_array - np.mean(result_array))
    
    # Calculate centers of mass
    orig_center_x = np.sum(x_coords * orig_weights) / np.sum(orig_weights)
    orig_center_y = np.sum(y_coords * orig_weights) / np.sum(orig_weights)
    
    result_center_x = np.sum(x_coords * result_weights) / np.sum(result_weights)
    result_center_y = np.sum(y_coords * result_weights) / np.sum(result_weights)
    
    # This is a simple heuristic - for 45° rotation, we expect some shift in center
    center_shift = np.sqrt((result_center_x - orig_center_x)**2 + (result_center_y - orig_center_y)**2)
    
    # For 45° rotation, expect moderate center shift due to canvas expansion
    if 10 < center_shift < 100:  # Heuristic range
        return 45  # Likely rotated
    else:
        return 0   # Likely not rotated significantly


def validate_45_degree_rotation(detected_angle, method_confidence=0.5):
    """
    Validate if detected angle represents a successful 45-degree rotation.
    """
    if detected_angle is None:
        return False, 0, "No rotation detected"
    
    # Normalize angle to 0-360 range
    normalized = detected_angle % 360
    
    # Check if close to 45° (allowing both +45° and -45° which becomes 315°)
    distance_to_45 = min(abs(normalized - 45), abs(normalized - 315))
    
    if distance_to_45 <= 1:
        return True, 100, "Perfect 45° rotation"
    elif distance_to_45 <= 3:
        return True, 90, "Excellent 45° rotation (within ±3°)"
    elif distance_to_45 <= 5:
        return True, 75, "Good 45° rotation (within ±5°)"
    elif distance_to_45 <= 8:
        return False, 60, f"Rotation detected but angle off by {distance_to_45:.1f}°"
    else:
        return False, 0, f"Incorrect rotation angle (detected ~{normalized:.1f}°)"


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different (rotated)."""
    if original_img.size != result_img.size:
        # Size difference suggests canvas expansion from rotation
        return True, "Canvas size changed (likely due to rotation)"
    
    # Convert to arrays for comparison
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Check if enough pixels changed significantly
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    meaningfully_changed = change_percentage > 20  # At least 20% of pixels changed
    
    return meaningfully_changed, f"Pixels changed: {change_percentage:.1f}%"


def check_45_rotation(traj, env_info, task_info):
    """
    Main verifier function for 45-degree rotation task.
    
    Uses multiple detection methods to determine if image was rotated by 45 degrees:
    1. Template matching with SSIM
    2. Edge orientation analysis
    3. Corner/geometry analysis
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container paths
        container_original = "/home/ga/Desktop/rotation_image.jpg"
        possible_results = [
            "/home/ga/Desktop/rotated_45.jpg",
            "/home/ga/Desktop/rotated_45.png",
            "/home/ga/Desktop/rotated_45.jpeg",
            "/home/ga/Desktop/rotation_image_rotated.jpg",
            "/home/ga/Desktop/rotation_edited.jpg"
        ]
        
        # Define host paths
        host_original = temp_path / "original.jpg"
        host_result = temp_path / "result.jpg"
        
        # Copy original image
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original image: {error}"
            }
        
        # Try to find result image
        result_found = False
        result_container_path = None
        for result_path in possible_results:
            success, error = copy_file_from_container(copy_from_env, result_path, host_result)
            if success:
                result_found = True
                result_container_path = result_path
                logging.debug(f"Found result image at: {result_path}")
                break
        
        if not result_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Result image not found. Tried: {[Path(p).name for p in possible_results]}"
            }
        
        try:
            # Load images
            original_image = Image.open(host_original)
            result_image = Image.open(host_result)
            
            logging.debug(f"Original size: {original_image.size}, Result size: {result_image.size}")
            
            # Check if image was meaningfully changed
            changed, change_info = check_meaningful_change(original_image, result_image)
            
            # Method 1: Template matching
            template_angle, template_confidence = detect_rotation_by_template_matching(original_image, result_image)
            
            # Method 2: Edge analysis
            edge_angle = detect_rotation_by_edge_analysis(original_image, result_image)
            
            # Method 3: Corner analysis
            corner_angle = detect_rotation_by_corner_analysis(original_image, result_image)
            
            feedback_parts = []
            feedback_parts.append(f"Original size: {original_image.size}")
            feedback_parts.append(f"Result size: {result_image.size}")
            feedback_parts.append(f"Found result at: {Path(result_container_path).name}")
            feedback_parts.append(change_info)
            
            # Analyze detection results
            detected_angles = []
            if template_angle is not None:
                detected_angles.append(template_angle)
                feedback_parts.append(f"Template match: {template_angle}° (confidence: {template_confidence:.3f})")
            
            if edge_angle is not None:
                detected_angles.append(edge_angle)
                feedback_parts.append(f"Edge analysis: {edge_angle:.1f}°")
            
            if corner_angle is not None:
                detected_angles.append(corner_angle)
                feedback_parts.append(f"Corner analysis: {corner_angle}°")
            
            # Determine final angle (prefer template matching if confidence is high)
            final_angle = None
            if template_angle is not None and template_confidence > 0.8:
                final_angle = template_angle
                feedback_parts.append(f"Using template result: {final_angle}°")
            elif detected_angles:
                # Use average of detected angles
                final_angle = np.mean(detected_angles)
                feedback_parts.append(f"Average detected angle: {final_angle:.1f}°")
            
            # Validate the rotation
            if final_angle is not None:
                is_valid, score, validation_msg = validate_45_degree_rotation(final_angle)
                feedback_parts.append(validation_msg)
                
                # Additional check: image must be meaningfully changed
                if is_valid and not changed:
                    is_valid = False
                    score = 0
                    feedback_parts.append("❌ No significant image changes detected")
                
                return {
                    "passed": is_valid,
                    "score": score,
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                feedback_parts.append("❌ Could not detect rotation angle")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
                
        except Exception as e:
            logging.error(f"Error in 45-degree rotation verification: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: {str(e)}"
            }


if __name__ == "__main__":
    # Test the verifier
    result = check_45_rotation([], {}, {})
    print(f"Test result: {result}")