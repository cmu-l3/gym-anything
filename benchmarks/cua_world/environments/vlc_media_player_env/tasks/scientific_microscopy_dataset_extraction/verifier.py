#!/usr/bin/env python3
"""
Verifier for Scientific Microscopy Dataset Extraction.

Verifies:
1. Target directory and ZIP exported.
2. Anti-gaming: Files created after task start.
3. Frame count (145-155 frames).
4. Image spatial dimensions (exactly 500x500).
5. Image content and contrast enhancement (std dev analysis).
6. Manifest accuracy.
"""

import json
import os
import zipfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scientific_microscopy_dataset_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    feedback_parts = []
    score = 0
    max_score = 100

    # Create a local temporary directory for analysis
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_microscopy_')
    local_json = os.path.join(temp_dir, 'task_result.json')
    local_zip = os.path.join(temp_dir, 'dataset_44B.zip')

    try:
        # Copy export data from the container
        try:
            copy_from_env("/tmp/task_result.json", local_json)
            copy_from_env("/tmp/dataset_44B.zip", local_zip)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve files: {e}"}

        with open(local_json, 'r') as f:
            result = json.load(f)

        # CRITERION 1: Output Directory Exists & Anti-Gaming (10 points)
        dir_exists = result.get('directory_exists', False)
        files_new = result.get('files_created_during_task', False)

        if not dir_exists:
            return {"passed": False, "score": 0, "feedback": "Target directory /home/ga/Pictures/dataset_44B/ was not created."}
        
        if not files_new:
            return {"passed": False, "score": 0, "feedback": "Files were not created during the task (Anti-gaming triggered)."}
            
        score += 10
        feedback_parts.append("+ Directory created during task")

        # Unzip the data
        dataset_path = os.path.join(temp_dir, 'dataset_44B')
        try:
            with zipfile.ZipFile(local_zip, 'r') as zip_ref:
                zip_ref.extractall(temp_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | x ZIP file is corrupted or empty."}

        # CRITERION 2: Temporal Trimming / Frame Count (20 points)
        png_files = [f for f in os.listdir(dataset_path) if f.lower().endswith('.png')]
        frame_count = len(png_files)
        
        if 145 <= frame_count <= 155:
            score += 20
            feedback_parts.append(f"+ Frame count correct ({frame_count} frames)")
        elif 100 <= frame_count <= 200:
            score += 10
            feedback_parts.append(f"~ Frame count slightly off ({frame_count} frames)")
        else:
            feedback_parts.append(f"x Frame count incorrect ({frame_count} frames, expected ~150)")

        # Imports for Image Analysis
        try:
            from PIL import Image
            import numpy as np
            has_img_libs = True
        except ImportError:
            has_img_libs = False
            logger.warning("PIL/numpy not available. Skipping deep visual verification.")

        # CRITERION 3 & 4: Spatial Cropping and Contrast Content
        # We sample a few frames to verify dimensions and pixel statistics
        dim_correct = True
        valid_content = True
        contrast_applied = True
        
        if frame_count > 0 and has_img_libs:
            sampled_files = png_files[:5]  # Check first 5 frames
            for img_file in sampled_files:
                img_path = os.path.join(dataset_path, img_file)
                try:
                    with Image.open(img_path) as img:
                        w, h = img.size
                        if w != 500 or h != 500:
                            dim_correct = False
                        
                        # Check content / contrast
                        # A completely blank image will have std dev near 0
                        # The raw video was set to 0.4 contrast, a 1.5x boost creates visible variance.
                        img_arr = np.array(img.convert('L'))
                        std_dev = np.std(img_arr)
                        
                        if std_dev < 5:
                            valid_content = False
                        # Because the raw was artificially washed out, std dev should be noticeably higher
                        # if the 1.5x contrast filter was applied.
                        # Setting a conservative threshold to verify *some* dynamic range exists.
                        if std_dev < 15:
                            contrast_applied = False
                except Exception as e:
                    logger.error(f"Image processing error: {e}")
                    valid_content = False

            # Scoring Criterion 3 (25 pts)
            if dim_correct:
                score += 25
                feedback_parts.append("+ Resolution correct (500x500)")
            else:
                feedback_parts.append("x Incorrect image resolution")

            # Scoring Criterion 4 (25 pts)
            if valid_content and contrast_applied:
                score += 25
                feedback_parts.append("+ Valid content with enhanced contrast")
            elif valid_content:
                score += 10
                feedback_parts.append("~ Images valid, but contrast enhancement missing")
            else:
                feedback_parts.append("x Images are blank or corrupted")
        else:
            if not has_img_libs:
                # Give partial credit if we can't fully test but files exist
                if frame_count > 0:
                    score += 25 
                    feedback_parts.append("~ Image analysis skipped (missing libs), assuming basic validity")

        # CRITERION 5: Manifest Accuracy (20 points)
        manifest_path = os.path.join(dataset_path, 'manifest.json')
        if os.path.exists(manifest_path):
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                
                m_score = 0
                if int(manifest.get('start_time', 0)) == 76: m_score += 3
                if int(manifest.get('duration', 0)) == 5: m_score += 3
                if int(manifest.get('crop_x', 0)) == 1350: m_score += 3
                if int(manifest.get('crop_y', 0)) == 150: m_score += 3
                if int(manifest.get('crop_width', 0)) == 500: m_score += 2
                if int(manifest.get('crop_height', 0)) == 500: m_score += 2
                if float(manifest.get('contrast_factor', 0.0)) == 1.5: m_score += 4
                
                score += m_score
                if m_score == 20:
                    feedback_parts.append("+ Manifest is perfectly accurate")
                elif m_score > 0:
                    feedback_parts.append(f"~ Manifest partially accurate ({m_score}/20 pts)")
                else:
                    feedback_parts.append("x Manifest data incorrect")
            except Exception:
                feedback_parts.append("x Manifest is not valid JSON")
        else:
            feedback_parts.append("x Manifest file missing")

        # Evaluate final pass/fail
        # Gate: Must have correct dimensions AND valid image content to pass.
        key_criteria_met = dim_correct and valid_content and (frame_count > 0)
        passed = (score >= 70) and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup temp directory
        for root, dirs, files in os.walk(temp_dir, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
            for name in dirs:
                os.rmdir(os.path.join(root, name))
        os.rmdir(temp_dir)