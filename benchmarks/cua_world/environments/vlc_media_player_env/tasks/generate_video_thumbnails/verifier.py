#!/usr/bin/env python3
"""
Verifier for Generate Video Thumbnails task
"""

import sys
import os
import logging
import json
from pathlib import Path
from typing import Any, Dict, List, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

try:
    from vlc_verification_utils import verify_image_quality, PIL_AVAILABLE, CV2_AVAILABLE
    if PIL_AVAILABLE:
        from PIL import Image
    if CV2_AVAILABLE:
        import cv2
        import numpy as np
except ImportError as e:
    logging.error(f"Failed to import verification utils: {e}")
    # Continue without these - will skip some checks

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_image_diversity(image_paths: List[Path], similarity_threshold: float = 0.95) -> Tuple[bool, str]:
    """
    Verify that images are not all identical (represent different timestamps).
    
    Args:
        image_paths: List of image file paths
        similarity_threshold: If images are more similar than this, consider them duplicates
        
    Returns:
        Tuple of (is_diverse, feedback_message)
    """
    if not CV2_AVAILABLE or not PIL_AVAILABLE:
        logger.warning("OpenCV or PIL not available, skipping diversity check")
        return True, "Diversity check skipped (missing libraries)"
    
    try:
        if len(image_paths) < 2:
            return True, "Not enough images to check diversity"
        
        # Load and resize images for comparison (check up to 6 images)
        images = []
        valid_paths = []
        for path in sorted(image_paths)[:6]:
            try:
                img = cv2.imread(str(path))
                if img is None:
                    logger.warning(f"Could not load image: {path}")
                    continue
                # Resize to small size for fast comparison
                img_small = cv2.resize(img, (64, 64))
                images.append(img_small)
                valid_paths.append(path)
            except Exception as e:
                logger.warning(f"Error loading {path}: {e}")
                continue
        
        if len(images) < 2:
            return True, "Not enough valid images to check diversity"
        
        # Compare first image with others
        reference = images[0]
        similarities = []
        different_count = 0
        
        for i, img in enumerate(images[1:], 1):
            # Calculate MSE (Mean Squared Error)
            mse = np.mean((reference.astype(float) - img.astype(float)) ** 2)
            max_mse = 255.0 ** 2  # Maximum possible MSE for 8-bit images
            similarity = 1.0 - (mse / max_mse)
            similarities.append(similarity)
            
            logger.info(f"Image 0 vs Image {i} similarity: {similarity:.3f}")
            
            if similarity < similarity_threshold:
                different_count += 1
        
        # Check if any images are different enough
        if not similarities:
            return True, "Could not compute similarities"
        
        min_similarity = min(similarities)
        avg_similarity = sum(similarities) / len(similarities)
        
        logger.info(f"Similarity stats - min: {min_similarity:.3f}, avg: {avg_similarity:.3f}, different: {different_count}/{len(similarities)}")
        
        if min_similarity > similarity_threshold and different_count == 0:
            return False, f"All thumbnails appear identical (min_similarity={min_similarity:.3f}). Images may be from same timestamp."
        
        return True, f"Images show diversity (min_sim={min_similarity:.3f}, avg_sim={avg_similarity:.3f}, different={different_count})"
        
    except Exception as e:
        logger.warning(f"Error checking image diversity: {e}", exc_info=True)
        return True, f"Diversity check failed but continuing: {e}"


def verify_generate_video_thumbnails(traj, env_info, task_info):
    """
    Verify the video thumbnail extraction task.
    
    Args:
        traj: Trajectory information (unused)
        env_info: Environment information including copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        Dict with verification results including passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    result = {
        'passed': False,
        'score': 0,
        'feedback': [],
        'details': {}
    }
    
    criteria_met = 0
    total_criteria = 4  # Count, valid images, diversity, completion
    feedback_parts = []
    
    export_dir = "/tmp/vlc_thumbnails_export"
    
    # Load metadata
    metadata_path = Path(export_dir) / 'task_metadata.json'
    metadata = {}
    if metadata_path.exists():
        try:
            with open(metadata_path, 'r') as f:
                metadata = json.load(f)
            logger.info(f"Loaded metadata: {metadata}")
        except Exception as e:
            logger.warning(f"Could not load metadata: {e}")
    
    expected_count = metadata.get('expected_count', 12)
    
    # Get all image files from export directory
    image_extensions = {'.png', '.jpg', '.jpeg', '.bmp'}
    image_files = []
    
    export_path = Path(export_dir)
    if export_path.exists():
        for f in export_path.iterdir():
            if f.is_file() and f.suffix.lower() in image_extensions:
                image_files.append(f)
    
    actual_count = len(image_files)
    result['details']['image_count'] = actual_count
    result['details']['expected_count'] = expected_count
    
    logger.info(f"Found {actual_count} image files (expected {expected_count})")
    
    # Criterion 1: Check count
    if actual_count == 0:
        feedback_parts.append("❌ No thumbnail images found")
        feedback_parts.append("💡 Hint: Use VLC's scene filter to extract frames")
        result['feedback'] = feedback_parts
        return result
    
    count_score = 0
    if actual_count == expected_count:
        count_score = 1.5  # Extra weight for exact match
        feedback_parts.append(f"✅ Correct number of thumbnails: {actual_count}")
    elif abs(actual_count - expected_count) <= 2:
        count_score = 1.0
        feedback_parts.append(f"⚠️ Close to target: {actual_count} thumbnails (expected {expected_count})")
    elif actual_count < expected_count:
        count_score = 0.5
        feedback_parts.append(f"⚠️ Found {actual_count} thumbnails, expected {expected_count}")
    else:
        count_score = 0.5
        feedback_parts.append(f"⚠️ Found {actual_count} thumbnails, expected exactly {expected_count}")
        feedback_parts.append("💡 Hint: Adjust scene-ratio to control extraction frequency")
    
    criteria_met += count_score
    
    # Criterion 2: Verify image quality
    valid_images = 0
    invalid_images = []
    
    for img_file in image_files:
        try:
            # Check file size
            size_kb = img_file.stat().st_size / 1024
            if size_kb < 5:
                invalid_images.append(img_file.name)
                continue
            
            # Try to open as image
            if PIL_AVAILABLE:
                try:
                    img = Image.open(str(img_file))
                    img.verify()
                    # Re-open for size check (verify closes the file)
                    img = Image.open(str(img_file))
                    width, height = img.size
                    if width >= 100 and height >= 100:
                        valid_images += 1
                    else:
                        invalid_images.append(img_file.name)
                except Exception as e:
                    logger.warning(f"Invalid image {img_file.name}: {e}")
                    invalid_images.append(img_file.name)
            else:
                # No PIL, just count as valid if size is OK
                valid_images += 1
        except Exception as e:
            logger.warning(f"Error checking {img_file}: {e}")
            invalid_images.append(img_file.name)
    
    result['details']['valid_images'] = valid_images
    result['details']['invalid_images'] = invalid_images
    
    if valid_images == actual_count and actual_count > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ All {valid_images} images are valid")
    elif valid_images > 0:
        criteria_met += 0.5
        feedback_parts.append(f"⚠️ {valid_images}/{actual_count} images are valid")
        if invalid_images:
            feedback_parts.append(f"   Invalid: {invalid_images[:3]}")
    else:
        feedback_parts.append("❌ No valid images found")
    
    # Criterion 3: Check image diversity (not all identical)
    if valid_images >= 2:
        is_diverse, diversity_msg = verify_image_diversity(sorted(image_files)[:10])
        result['details']['diversity_check'] = diversity_msg
        
        if is_diverse:
            criteria_met += 1
            feedback_parts.append(f"✅ Content diversity verified: {diversity_msg}")
        else:
            feedback_parts.append(f"❌ {diversity_msg}")
            feedback_parts.append("💡 Hint: Ensure scene-ratio extracts frames throughout the video")
    elif valid_images == 1:
        feedback_parts.append("⚠️ Only 1 image, cannot check diversity")
    
    # Criterion 4: Completion marker
    completion_file = export_path / 'task_completed.txt'
    if completion_file.exists():
        criteria_met += 0.5
        feedback_parts.append("✅ Task completion marker found")
    else:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate final score
    # Max possible: 1.5 (count) + 1 (valid) + 1 (diversity) + 0.5 (completion) = 4
    score = int((criteria_met / total_criteria) * 100)
    result['score'] = score
    result['feedback'] = feedback_parts
    
    # Determine pass/fail
    # Need: correct count OR close count, valid images, and reasonable score
    if actual_count == expected_count and valid_images == expected_count and score >= 75:
        result['passed'] = True
        feedback_parts.append("🎉 Task completed successfully!")
    elif actual_count == expected_count and valid_images >= expected_count * 0.9:
        result['passed'] = True
        feedback_parts.append("✅ Task completed with minor issues")
    elif score >= 60:
        result['passed'] = False
        feedback_parts.append("⚠️ Task partially completed - check requirements")
    else:
        result['passed'] = False
        feedback_parts.append("❌ Task incomplete - see feedback above")
    
    logger.info(f"Verification result: passed={result['passed']}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return result
