#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import csv
import statistics
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_ground_truth_means(csv_path):
    """
    Calculates the expected mean Extraversion_Score for Males (1) and Females (2)
    using the raw data and the correct reverse coding logic:
    Score = Mean(7-E1, 7-E2, E3, E4, E5)
    """
    scores_by_gender = {1: [], 2: []}
    
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    # Parse Items
                    e1 = int(row['E1'])
                    e2 = int(row['E2'])
                    e3 = int(row['E3'])
                    e4 = int(row['E4'])
                    e5 = int(row['E5'])
                    gender = int(row['gender'])
                    
                    # Apply logic
                    e1_rev = 7 - e1
                    e2_rev = 7 - e2
                    
                    score = statistics.mean([e1_rev, e2_rev, e3, e4, e5])
                    
                    if gender in scores_by_gender:
                        scores_by_gender[gender].append(score)
                except (ValueError, KeyError):
                    continue
                    
        means = {}
        if scores_by_gender[1]:
            means['Male'] = statistics.mean(scores_by_gender[1])
        if scores_by_gender[2]:
            means['Female'] = statistics.mean(scores_by_gender[2])
            
        return means
    except Exception as e:
        logger.error(f"Error calculating ground truth: {e}")
        return {}

def verify_scale_construction_gender_ttest(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the .omv output file.
    2. Correctly calculated the computed variable (verified by checking group means in results).
    3. Ran the T-Test with Effect Size.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_omv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.omv').name
    temp_csv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    score = 0
    feedback = []
    
    try:
        # 1. Load Task Result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check file existence
        if not task_result.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output .omv file not found."}
        
        score += 10
        feedback.append("Output file exists.")

        if task_result.get("file_created_during_task"):
            score += 10
            feedback.append("File created during task.")
        else:
            feedback.append("Warning: File timestamp suggests it wasn't modified during task.")

        # 2. Retrieve Data for Ground Truth Calculation
        dataset_path = task_result.get("dataset_path", "/home/ga/Documents/Jamovi/BFI25.csv")
        try:
            copy_from_env(dataset_path, temp_csv_file)
            ground_truth_means = calculate_ground_truth_means(temp_csv_file)
            logger.info(f"Ground Truth Means: {ground_truth_means}")
        except Exception as e:
            # Fallback hardcoded values if CSV copy fails (based on BFI dataset standards)
            # Typically Male ~ 4.2, Female ~ 4.4 for Extraversion with this data
            logger.warning(f"Failed to calculate dynamic ground truth: {e}")
            ground_truth_means = {'Male': 4.21, 'Female': 4.43} # Approximate fallback

        # 3. Analyze OMV File
        omv_path = task_result.get("output_path")
        try:
            copy_from_env(omv_path, temp_omv_file)
            
            with zipfile.ZipFile(temp_omv_file, 'r') as z:
                # Jamovi stores analysis results in analysis/ folder
                analysis_files = [f for f in z.namelist() if f.startswith('analysis/') and f.endswith('.json')]
                
                ttest_found = False
                means_match = False
                effect_size_found = False
                
                for af in analysis_files:
                    try:
                        data = json.loads(z.read(af).decode('utf-8'))
                        
                        # Identify T-Test
                        # The structure varies, but usually contains "ttestIS" or similar in name or type
                        # Or look for specific options structure
                        options = data.get('options', {})
                        results = data.get('results', {})
                        
                        # Check for Independent Samples T-Test signature
                        if 'ttestIS' in str(data) or (results.get('ttest') and results.get('desc')):
                            ttest_found = True
                            
                            # Check Effect Size option
                            if options.get('effectSize', False) is True:
                                effect_size_found = True
                            
                            # Verify Group Means
                            # The 'desc' (descriptives) table usually holds the means
                            # We need to traverse the results object to find the Group Descriptives table
                            # This is complex in Jamovi JSON, often nested in 'results' -> 'ttest' -> 'desc'
                            
                            # Heuristic: search for numbers matching our ground truth in the JSON string
                            # This is robust against minor schema changes
                            json_str = json.dumps(data)
                            
                            gt_male = ground_truth_means.get('Male', 0)
                            gt_female = ground_truth_means.get('Female', 0)
                            
                            # Tolerance
                            tol = 0.05
                            
                            # Check if Male mean is present
                            male_match = False
                            if any(str(round(gt_male + offset, 3)) in json_str or str(round(gt_male + offset, 2)) in json_str 
                                   for offset in [0, 0.001, -0.001]):
                                male_match = True
                                
                            # Check if Female mean is present
                            female_match = False
                            if any(str(round(gt_female + offset, 3)) in json_str or str(round(gt_female + offset, 2)) in json_str 
                                   for offset in [0, 0.001, -0.001]):
                                female_match = True
                                
                            if male_match and female_match:
                                means_match = True
                                break # Found the correct analysis
                                
                    except Exception as e:
                        logger.warning(f"Error parsing analysis file {af}: {e}")
                        continue
                
                if ttest_found:
                    score += 20
                    feedback.append("Independent Samples T-Test found.")
                else:
                    feedback.append("T-Test analysis not found in project.")

                if effect_size_found:
                    score += 10
                    feedback.append("Effect size option enabled.")
                
                if means_match:
                    score += 50
                    feedback.append("Group means match ground truth (Reverse coding applied correctly).")
                else:
                    feedback.append("Group means do NOT match. Likely failed to reverse code items E1/E2.")

        except Exception as e:
            feedback.append(f"Failed to analyze .omv file: {e}")

    finally:
        # Cleanup
        for f in [temp_result_json, temp_omv_file, temp_csv_file]:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }