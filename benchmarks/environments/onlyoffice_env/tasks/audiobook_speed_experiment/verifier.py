#!/usr/bin/env python3
"""
Verifier for Audiobook Speed Experiment task

Checks:
1. Data consolidation: ≥12 rows, sessions from notes integrated
2. Calculated columns: Baseline Time, Time Saved, Efficiency Score with formulas
3. Analysis Summary sheet: metrics calculated
4. Recommendations: present and data-backed
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_speed_string(speed_str):
    """Parse speed string like '1.5x' to float 1.5"""
    if not speed_str:
        return None
    try:
        # Remove 'x' and convert to float
        speed_str = str(speed_str).strip().lower().replace('x', '')
        return float(speed_str)
    except:
        return None


def find_column_index(headers, possible_names):
    """Find column index by matching possible header names (case insensitive)"""
    headers_lower = [str(h).lower() if h else '' for h in headers]
    for idx, header in enumerate(headers_lower):
        for name in possible_names:
            if name.lower() in header:
                return idx
    return None


def verify_audiobook_experiment(traj, env_info, task_info):
    """
    Verify audiobook speed experiment spreadsheet completion
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/audiobook_experiment_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_audiobook_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to open spreadsheet: {error}"
            }

        score = 0
        max_score = 100
        feedback = []

        # ====================================================================
        # 1. VERIFY DATA CONSOLIDATION (30 points)
        # ====================================================================
        try:
            # Find the experiment data sheet (might be named "Experiment Data" or just be first sheet)
            data_sheet = None
            if "Experiment Data" in wb.sheetnames:
                data_sheet = wb["Experiment Data"]
            else:
                data_sheet = wb.active
            
            # Count non-empty rows (rows where Book Title is not None)
            # Find book title column
            headers = [cell.value for cell in data_sheet[1]]
            book_col_idx = find_column_index(headers, ["book title", "title", "book"])
            
            if book_col_idx is None:
                feedback.append("❌ Could not find 'Book Title' column")
            else:
                row_count = 0
                books_found = []
                for row in data_sheet.iter_rows(min_row=2, max_row=100):
                    book_title = row[book_col_idx].value
                    if book_title and str(book_title).strip():
                        row_count += 1
                        books_found.append(str(book_title).lower())
                
                # Check row count
                if row_count >= 12:
                    score += 15
                    feedback.append(f"✅ Found {row_count} sessions (≥12 required)")
                elif row_count >= 10:
                    score += 10
                    feedback.append(f"⚠️ Found {row_count} sessions (12 recommended)")
                else:
                    feedback.append(f"❌ Only {row_count} sessions found, need at least 12")
                
                # Check for sessions mentioned in notes
                # Notes mentioned: "Atomic Habits" at 1.75x, "Project Hail Mary" at 1.5x, "Thinking Fast and Slow" at 1.25x
                key_books = ["project hail mary", "atomic habits"]
                found_key_books = []
                for key_book in key_books:
                    if any(key_book in book for book in books_found):
                        found_key_books.append(key_book)
                
                if len(found_key_books) >= 2:
                    score += 15
                    feedback.append("✅ Sessions from notes file integrated (found key books)")
                elif len(found_key_books) >= 1:
                    score += 10
                    feedback.append("⚠️ Some sessions from notes added, but not all")
                else:
                    feedback.append("❌ Missing sessions mentioned in notes file")
                    
        except Exception as e:
            feedback.append(f"❌ Data consolidation check failed: {e}")
            logger.error(f"Data consolidation error: {e}", exc_info=True)

        # ====================================================================
        # 2. VERIFY CALCULATED COLUMNS (25 points)
        # ====================================================================
        try:
            headers = [cell.value for cell in data_sheet[1]]
            
            # Find required calculated columns
            baseline_col = find_column_index(headers, ["baseline time", "baseline"])
            timesaved_col = find_column_index(headers, ["time saved", "saved"])
            efficiency_col = find_column_index(headers, ["efficiency score", "efficiency"])
            
            cols_found = 0
            if baseline_col is not None:
                cols_found += 1
            if timesaved_col is not None:
                cols_found += 1
            if efficiency_col is not None:
                cols_found += 1
            
            score += cols_found * 5  # 5 points per column (15 total)
            
            if cols_found == 3:
                feedback.append("✅ All calculated columns present")
            else:
                missing = []
                if baseline_col is None:
                    missing.append("Baseline Time")
                if timesaved_col is None:
                    missing.append("Time Saved")
                if efficiency_col is None:
                    missing.append("Efficiency Score")
                feedback.append(f"❌ Missing columns: {', '.join(missing)}")
            
            # Verify formulas are correct (check a few rows)
            formula_verified = False
            if baseline_col is not None and cols_found >= 1:
                # Find speed and duration columns
                speed_col = find_column_index(headers, ["speed"])
                duration_col = find_column_index(headers, ["duration"])
                
                if speed_col is not None and duration_col is not None:
                    # Check several rows for correct formula calculation
                    correct_calculations = 0
                    total_checks = 0
                    
                    for row in data_sheet.iter_rows(min_row=2, max_row=min(15, row_count + 2)):
                        speed_val = row[speed_col].value
                        duration_val = row[duration_col].value
                        baseline_val = row[baseline_col].value
                        
                        if speed_val and duration_val and baseline_val:
                            speed_num = parse_speed_string(speed_val)
                            if speed_num and isinstance(duration_val, (int, float)):
                                expected_baseline = duration_val * speed_num
                                total_checks += 1
                                # Allow 10% tolerance for rounding
                                if abs(baseline_val - expected_baseline) / expected_baseline < 0.1:
                                    correct_calculations += 1
                    
                    if total_checks > 0 and correct_calculations / total_checks >= 0.7:
                        score += 10
                        feedback.append(f"✅ Formula calculations verified correct ({correct_calculations}/{total_checks} rows)")
                        formula_verified = True
                    elif total_checks > 0:
                        score += 5
                        feedback.append(f"⚠️ Some formulas correct ({correct_calculations}/{total_checks} rows)")
                    else:
                        feedback.append("❌ Could not verify formula calculations")
            
            if not formula_verified and cols_found > 0:
                feedback.append("⚠️ Calculated columns present but could not verify formulas")
                
        except Exception as e:
            feedback.append(f"❌ Calculated columns check failed: {e}")
            logger.error(f"Calculated columns error: {e}", exc_info=True)

        # ====================================================================
        # 3. VERIFY ANALYSIS SUMMARY SHEET (25 points)
        # ====================================================================
        try:
            analysis_sheet = None
            analysis_sheet_names = ["Analysis Summary", "Analysis", "Summary"]
            
            for name in analysis_sheet_names:
                if name in wb.sheetnames:
                    analysis_sheet = wb[name]
                    break
            
            if analysis_sheet:
                score += 10
                feedback.append(f"✅ Analysis Summary sheet created ('{analysis_sheet.title}')")
                
                # Get all text content from analysis sheet
                analysis_data = []
                for row in analysis_sheet.iter_rows(max_row=50, max_col=10):
                    for cell in row:
                        if cell.value:
                            analysis_data.append(str(cell.value))
                
                analysis_text = " ".join(analysis_data).lower()
                
                # Check for key metrics
                metrics_score = 0
                
                # Metric 1: Comprehension by speed
                if ("comprehension" in analysis_text and "speed" in analysis_text) or \
                   ("1.0x" in analysis_text and "1.5x" in analysis_text):
                    metrics_score += 5
                    feedback.append("✅ Comprehension by speed analysis found")
                else:
                    feedback.append("❌ Comprehension by speed analysis missing")
                
                # Metric 2: Comprehension by genre
                if ("genre" in analysis_text or "fiction" in analysis_text) and "comprehension" in analysis_text:
                    metrics_score += 5
                    feedback.append("✅ Comprehension by genre analysis found")
                else:
                    feedback.append("❌ Comprehension by genre analysis missing")
                
                # Metric 3: Total time saved
                if "time saved" in analysis_text or "total" in analysis_text:
                    metrics_score += 5
                    feedback.append("✅ Total time saved calculation found")
                else:
                    feedback.append("❌ Total time saved calculation missing")
                
                score += metrics_score
                
            else:
                feedback.append("❌ Analysis Summary sheet not found")
                
        except Exception as e:
            feedback.append(f"❌ Analysis summary check failed: {e}")
            logger.error(f"Analysis summary error: {e}", exc_info=True)

        # ====================================================================
        # 4. VERIFY RECOMMENDATIONS (20 points)
        # ====================================================================
        try:
            if analysis_sheet:
                # Get all text content
                recommendation_data = []
                for row in analysis_sheet.iter_rows(max_row=100, max_col=15):
                    for cell in row:
                        if cell.value:
                            recommendation_data.append(str(cell.value))
                
                rec_text = " ".join(recommendation_data)
                rec_text_lower = rec_text.lower()
                
                # Check for recommendations section
                has_recommendations = any(word in rec_text_lower for word in 
                                         ["recommend", "recommendation", "optimal speed", "best speed"])
                
                if has_recommendations:
                    score += 10
                    feedback.append("✅ Recommendations section present")
                    
                    # Check for specific speeds mentioned
                    speeds_mentioned = [s for s in ["1.0x", "1.25x", "1.5x", "1.75x"] if s in rec_text]
                    if len(speeds_mentioned) >= 1:
                        score += 5
                        feedback.append(f"✅ Specific speed recommendations found ({len(speeds_mentioned)} speeds)")
                    else:
                        feedback.append("❌ No specific speed values in recommendations")
                    
                    # Check for data justification
                    has_justification = any(word in rec_text_lower for word in 
                                           ["average", "based on", "comprehension", "score", "data", "because"])
                    if has_justification:
                        score += 5
                        feedback.append("✅ Data-backed justification provided")
                    else:
                        feedback.append("❌ Recommendations lack data justification")
                        
                    # Check for annual projection
                    has_annual = any(word in rec_text_lower for word in ["year", "annual", "annually", "250 days"])
                    has_time = any(word in rec_text_lower for word in ["hour", "minute", "time"])
                    if has_annual and has_time:
                        feedback.append("✅ Annual time savings projection included")
                    elif has_annual or has_time:
                        feedback.append("⚠️ Partial annual projection (missing time/year reference)")
                    else:
                        feedback.append("⚠️ Annual projection missing or unclear")
                else:
                    feedback.append("❌ No recommendations section found")
            else:
                feedback.append("❌ Cannot check recommendations (Analysis sheet missing)")
                
        except Exception as e:
            feedback.append(f"❌ Recommendations check failed: {e}")
            logger.error(f"Recommendations error: {e}", exc_info=True)

        # Final assessment
        passed = score >= 75
        feedback_str = " | ".join(feedback)
        
        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "feedback": f"Score: {score}/{max_score}. {feedback_str}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
