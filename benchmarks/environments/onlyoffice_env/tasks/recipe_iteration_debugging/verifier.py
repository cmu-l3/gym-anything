#!/usr/bin/env python3
"""
Verifier for Recipe Iteration Debugging task
Verifies systematic recipe troubleshooting analysis
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


def verify_recipe_debugging_log(traj, env_info, task_info):
    """
    Verify that recipe troubleshooting analysis was completed correctly.

    Scoring breakdown:
    - Data Completeness (30 points): Missing data for attempts 4-6 filled
    - Analysis Quality (40 points): Variable analysis section with pattern identification
    - Synthesis Quality (30 points): Conclusions and specific recommendations

    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/Cookie_Troubleshooting_Log.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_recipe_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        sheet_name = "Troubleshooting Log"
        
        # Initialize scoring
        data_score = 0  # Max 30
        analysis_score = 0  # Max 40
        synthesis_score = 0  # Max 30
        feedback_parts = []

        # ================================================================
        # A. DATA COMPLETENESS CHECK (30 points)
        # ================================================================
        
        # Define columns to check (C through H are the core variable columns)
        # Row 5 = Attempt 4, Row 6 = Attempt 5, Row 7 = Attempt 6
        attempts_to_check = [
            (5, 4),  # Row 5, Attempt 4
            (6, 5),  # Row 6, Attempt 5
            (7, 6),  # Row 7, Attempt 6
        ]
        
        # Core columns: C=Flour, D=Butter, E=Sugar, F=Mixing, G=Oven, H=Baking
        core_columns = ['C', 'D', 'E', 'F', 'G', 'H']
        
        filled_count = 0
        total_cells_to_check = len(attempts_to_check) * len(core_columns)
        
        for row_num, attempt_num in attempts_to_check:
            for col in core_columns:
                cell_ref = f"{col}{row_num}"
                cell_value = get_cell_value(wb, sheet_name, cell_ref)
                
                # Check if cell is filled (not None, not empty, not "???")
                if cell_value is not None:
                    cell_str = str(cell_value).strip()
                    if cell_str and "???" not in cell_str and len(cell_str) > 0:
                        filled_count += 1
                        logger.debug(f"Cell {cell_ref} filled: {cell_str}")
                    else:
                        logger.debug(f"Cell {cell_ref} not properly filled: {cell_str}")
                else:
                    logger.debug(f"Cell {cell_ref} is None")
        
        # Calculate data completeness score
        if total_cells_to_check > 0:
            completeness_ratio = filled_count / total_cells_to_check
            data_score = completeness_ratio * 30
            
            if completeness_ratio >= 0.9:
                feedback_parts.append(f"✅ Excellent data completion ({filled_count}/{total_cells_to_check} cells)")
            elif completeness_ratio >= 0.7:
                feedback_parts.append(f"⚠️ Good data completion ({filled_count}/{total_cells_to_check} cells)")
            else:
                feedback_parts.append(f"❌ Incomplete data ({filled_count}/{total_cells_to_check} cells filled)")
        
        # ================================================================
        # B. ANALYSIS QUALITY CHECK (40 points)
        # ================================================================
        
        # Get all data from sheet to scan for analysis sections
        all_data = get_sheet_data(wb, sheet_name, max_rows=100, max_cols=13)
        
        # Flatten all cell values for text searching
        all_text_lower = ""
        for row in all_data:
            for cell in row:
                if cell is not None:
                    all_text_lower += str(cell).lower() + " "
        
        # Check for analysis section keywords
        analysis_keywords = [
            'variable analysis', 'variable comparison', 'comparison',
            'pattern', 'correlation', 'analysis'
        ]
        
        analysis_section_found = False
        for keyword in analysis_keywords:
            if keyword in all_text_lower:
                analysis_section_found = True
                logger.debug(f"Found analysis keyword: {keyword}")
                break
        
        if analysis_section_found:
            analysis_score += 20
            feedback_parts.append("✅ Analysis section present")
        else:
            feedback_parts.append("❌ Missing variable analysis section")
        
        # Check for identification of specific variables
        variable_mentions = 0
        variables_to_check = [
            ('flour', 'bread flour', 'all-purpose'),
            ('temperature', 'temp', 'oven'),
            ('butter', 'salted', 'unsalted'),
            ('mixing', 'time'),
            ('sugar', 'ratio')
        ]
        
        for var_group in variables_to_check:
            for var in var_group:
                if var in all_text_lower:
                    variable_mentions += 1
                    logger.debug(f"Found variable mention: {var}")
                    break  # Count each variable group only once
        
        if variable_mentions >= 3:
            analysis_score += 20
            feedback_parts.append(f"✅ Strong variable analysis ({variable_mentions} variables identified)")
        elif variable_mentions >= 1:
            analysis_score += 10
            feedback_parts.append(f"⚠️ Basic variable analysis ({variable_mentions} variables identified)")
        else:
            feedback_parts.append("❌ No clear variable identification")
        
        # ================================================================
        # C. SYNTHESIS & RECOMMENDATION QUALITY (30 points)
        # ================================================================
        
        # Check for conclusions section
        conclusion_keywords = [
            'conclusion', 'finding', 'likely cause', 'root cause',
            'discovered', 'determined', 'identified cause'
        ]
        
        conclusion_found = False
        for keyword in conclusion_keywords:
            if keyword in all_text_lower:
                conclusion_found = True
                logger.debug(f"Found conclusion keyword: {keyword}")
                break
        
        if conclusion_found:
            synthesis_score += 10
            feedback_parts.append("✅ Conclusions section present")
        else:
            feedback_parts.append("⚠️ No clear conclusions section")
        
        # Check for recommendation section
        recommendation_keywords = [
            'recommendation', 'attempt 7', 'attempt #7', 'next attempt',
            'should try', 'suggest', 'next time'
        ]
        
        recommendation_found = False
        for keyword in recommendation_keywords:
            if keyword in all_text_lower:
                recommendation_found = True
                logger.debug(f"Found recommendation keyword: {keyword}")
                break
        
        if recommendation_found:
            synthesis_score += 10
            feedback_parts.append("✅ Recommendation section present")
        else:
            feedback_parts.append("❌ Missing recommendation for attempt #7")
        
        # Check for specific values (indicating concrete recommendations)
        specific_value_patterns = [
            r'\d+\s*°f',  # Temperature with °F
            r'\d+\s*degrees',  # Temperature with "degrees"
            r'\d+\s*min',  # Time with "min"
            r'bread flour',  # Specific flour type
            r'all-purpose',  # Specific flour type
            r'unsalted',  # Specific butter type
            r'salted',  # Specific butter type
            r'325',  # Specific temperature
            r'350',  # Specific temperature
            r'375',  # Specific temperature
        ]
        
        has_specific_values = False
        for pattern in specific_value_patterns:
            if re.search(pattern, all_text_lower):
                has_specific_values = True
                logger.debug(f"Found specific value pattern: {pattern}")
                break
        
        if has_specific_values:
            synthesis_score += 10
            feedback_parts.append("✅ Specific, actionable recommendations")
        else:
            feedback_parts.append("⚠️ Recommendations lack specific values")
        
        # ================================================================
        # FINAL SCORING
        # ================================================================
        
        total_score = data_score + analysis_score + synthesis_score
        passed = total_score >= 70
        
        # Add detailed breakdown
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: Data={data_score:.1f}, Analysis={analysis_score:.1f}, Synthesis={synthesis_score:.1f}, Total={total_score:.1f}")
        
        return {
            "passed": passed,
            "score": int(round(total_score)),
            "feedback": feedback,
            "details": {
                "data_completeness_score": int(round(data_score)),
                "analysis_quality_score": int(round(analysis_score)),
                "synthesis_quality_score": int(round(synthesis_score)),
                "cells_filled": filled_count,
                "total_cells": total_cells_to_check,
                "analysis_section_found": analysis_section_found,
                "variables_identified": variable_mentions,
                "recommendation_found": recommendation_found
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        cleanup_temp_dir(temp_dir)
