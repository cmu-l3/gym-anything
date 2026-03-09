#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_census_telehealth_demographic_study(traj, env_info, task_info):
    """
    Verifies the census demographic study task.
    
    Scoring Criteria (100 pts total):
    1. JSON File Validity & Freshness (10 pts)
    2. Data Accuracy (45 pts - 15 per county)
    3. Browser History Evidence (25 pts)
    4. Bookmark Verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Task Metadata (Ground Truth)
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    tolerances = metadata.get('tolerances', {'percent_absolute': 5.0, 'income_percent': 0.15})

    # Load System Result (Browser State)
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
        finally:
            f.close()
            os.unlink(f.name)

    # Load Agent Output (JSON Data)
    agent_data = {}
    agent_file_available = False
    if task_result.get('file_exists') and task_result.get('file_fresh'):
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            try:
                copy_from_env("/tmp/telehealth_pilot_data_submission.json", f.name)
                f.seek(0)
                agent_data = json.load(f)
                agent_file_available = True
            except Exception as e:
                logger.error(f"Failed to load agent output: {e}")
            finally:
                f.close()
                os.unlink(f.name)

    score = 0
    feedback = []

    # --- Criterion 1: JSON File Structure (10 pts) ---
    if agent_file_available:
        required_keys = ['sumter_fl', 'marin_ca', 'yavapai_az']
        if all(k in agent_data for k in required_keys):
            score += 10
            feedback.append("JSON file exists, is fresh, and has correct keys. (+10)")
        else:
            feedback.append("JSON file exists but missing required county keys.")
    else:
        feedback.append("JSON output file not found or not created during task.")

    # --- Criterion 2: Data Accuracy (45 pts) ---
    # Helper to check number with tolerance
    def check_val(val, expected, tolerance, is_percent=False):
        if val is None: return False
        try:
            # Handle string formatting like "59.3%" or "$70,105"
            if isinstance(val, str):
                val = val.replace('%', '').replace('$', '').replace(',', '')
            num = float(val)
            
            if is_percent:
                # Absolute tolerance for percentages (e.g. 59.3 +/- 5.0)
                return abs(num - expected) <= tolerance
            else:
                # Relative tolerance for large numbers (income)
                return abs(num - expected) <= (expected * tolerance)
        except:
            return False

    data_score = 0
    if agent_file_available:
        for county_key, expected_data in ground_truth.items():
            agent_county = agent_data.get(county_key, {})
            county_points = 0
            
            # Check 4 fields
            # 1. 65+ (pct)
            if check_val(agent_county.get('pct_65_plus'), expected_data['pct_65_plus'], tolerances['percent_absolute'], True):
                county_points += 3.75
            
            # 2. Broadband (pct)
            if check_val(agent_county.get('pct_broadband'), expected_data['pct_broadband'], tolerances['percent_absolute'], True):
                county_points += 3.75

            # 3. Income ($)
            if check_val(agent_county.get('median_income_usd'), expected_data['median_income_usd'], tolerances['income_percent'], False):
                county_points += 3.75

            # 4. Disability (pct)
            if check_val(agent_county.get('pct_disability_under_65'), expected_data['pct_disability_under_65'], tolerances['percent_absolute'], True):
                county_points += 3.75
            
            # Round up visually for scoring logic clarity (3.75 * 4 = 15)
            data_score += county_points
            
    score += int(data_score)
    if data_score > 0:
        feedback.append(f"Data accuracy score: {int(data_score)}/45.")

    # --- Criterion 3: Browser History (25 pts) ---
    hist_score = 0
    if task_result.get('history_comparison_found'):
        hist_score = 25
        feedback.append("Browser history confirms comparison of the 3 specific counties. (+25)")
    elif task_result.get('history_visits', 0) > 0:
        hist_score = 10
        feedback.append("Browser history shows visits to Census QuickFacts, but not the specific comparison view. (+10)")
    else:
        feedback.append("No browser history found for Census QuickFacts.")
    score += hist_score

    # --- Criterion 4: Bookmarks (20 pts) ---
    bm_score = 0
    if task_result.get('bookmark_folder_exists'):
        if task_result.get('bookmark_correct'):
            bm_score = 20
            feedback.append("Bookmark folder and QuickFacts bookmark found. (+20)")
        else:
            bm_score = 10
            feedback.append("Bookmark folder found, but correct bookmark missing. (+10)")
    else:
        feedback.append("Required bookmark folder 'Pilot Site Research' not found.")
    score += bm_score

    # Final Verification
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }