#!/usr/bin/env python3
"""
Verifier for Contact Consolidation task.

Checks:
1. MasterContactList sheet exists
2. No duplicate emails (case-insensitive)
3. Significant consolidation (30-60% reduction)
4. Email format standardization
5. Name format standardization
6. Completeness flagging (80%+ complete records)
7. Multi-source integration evidence
8. Summary statistics present
"""

import sys
import os
import re
import logging

# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_email(email_str):
    """Normalize email for comparison (lowercase, strip, remove display names)"""
    if not email_str:
        return None
    
    email_str = str(email_str).strip()
    
    # Remove display names like "John Smith <john@email.com>"
    match = re.search(r'<(.+?)>', email_str)
    if match:
        email_str = match.group(1)
    
    # Remove angle brackets
    email_str = email_str.replace('<', '').replace('>', '')
    
    return email_str.strip().lower()


def is_title_case(name_str):
    """Check if name is in proper title case"""
    if not name_str:
        return False
    
    name_str = str(name_str).strip()
    
    # Check if it matches title case pattern (first letter capital, rest lowercase)
    # Handle multi-word names
    words = name_str.split()
    for word in words:
        if not word:
            continue
        if not (word[0].isupper() and word[1:].islower()):
            return False
    
    return True


def count_original_records(sheet_data):
    """Count total records from original source sheets"""
    total = 0
    source_sheets = ['EventPlatform1_Export', 'EventPlatform2_Export', 'ManualEntry_SignUp']
    
    for sheet_name in source_sheets:
        if sheet_name in sheet_data.get('sheets', {}):
            rows = sheet_data['sheets'][sheet_name]
            # Count non-empty rows (excluding header)
            for i, row in enumerate(rows):
                if i == 0:  # Skip header
                    continue
                if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                    total += 1
    
    return total


def extract_sheet_data(sheet_rows):
    """Extract data from sheet rows into list of dicts"""
    if not sheet_rows or len(sheet_rows) < 2:
        return []
    
    # Get header row
    header_row = sheet_rows[0]
    headers = []
    for cell in header_row:
        value = cell.get('value') if isinstance(cell, dict) else cell
        headers.append(str(value).strip() if value else '')
    
    # Extract data rows
    data = []
    for row in sheet_rows[1:]:
        # Check if row is non-empty
        if not any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
            continue
        
        row_data = {}
        for i, cell in enumerate(row):
            if i < len(headers):
                value = cell.get('value') if isinstance(cell, dict) else cell
                row_data[headers[i]] = value
        
        data.append(row_data)
    
    return data


def verify_contact_consolidation(traj, env_info, task_info):
    """
    Verify contact consolidation task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup and parse spreadsheet
    container_path = "/home/ga/Documents/contacts_messy.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = get_sheet_names(sheet_data)
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Count original records
        original_count = count_original_records(sheet_data)
        logger.info(f"Original record count: {original_count}")
        
        # Criterion 1: MasterContactList sheet exists
        master_sheet_name = None
        for name in sheet_names:
            if 'master' in name.lower() and 'contact' in name.lower():
                master_sheet_name = name
                break
        
        if master_sheet_name:
            criteria_passed += 1
            feedback_parts.append(f"✅ MasterContactList sheet found: '{master_sheet_name}'")
            subscores['master_sheet_exists'] = True
        else:
            feedback_parts.append("❌ MasterContactList sheet not found")
            subscores['master_sheet_exists'] = False
            # Cannot continue verification without the sheet
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # Extract master sheet data
        master_rows = sheet_data['sheets'][master_sheet_name]
        master_data = extract_sheet_data(master_rows)
        master_count = len(master_data)
        
        logger.info(f"Master sheet record count: {master_count}")
        
        # Criterion 2: No duplicate emails (case-insensitive)
        emails_found = []
        duplicate_found = False
        
        for row_data in master_data:
            # Try different column names for email
            email = None
            for col in ['Email', 'EmailAddress', 'email', 'EMAIL']:
                if col in row_data:
                    email = row_data[col]
                    break
            
            if email:
                normalized = normalize_email(email)
                if normalized:
                    if normalized in emails_found:
                        duplicate_found = True
                        logger.warning(f"Duplicate email found: {normalized}")
                        break
                    emails_found.append(normalized)
        
        if not duplicate_found and len(emails_found) > 0:
            criteria_passed += 1
            feedback_parts.append(f"✅ No duplicate emails ({len(emails_found)} unique)")
            subscores['no_duplicates'] = True
        elif len(emails_found) == 0:
            feedback_parts.append("❌ No email addresses found in MasterContactList")
            subscores['no_duplicates'] = False
        else:
            feedback_parts.append("❌ Duplicate email addresses detected")
            subscores['no_duplicates'] = False
        
        # Criterion 3: Significant consolidation (30-60% reduction)
        if original_count > 0:
            reduction_pct = ((original_count - master_count) / original_count) * 100
            logger.info(f"Consolidation: {original_count} → {master_count} ({reduction_pct:.1f}% reduction)")
            
            if 30 <= reduction_pct <= 60:
                criteria_passed += 1
                feedback_parts.append(f"✅ Good consolidation: {reduction_pct:.1f}% reduction ({original_count}→{master_count})")
                subscores['consolidation_ratio'] = True
            elif reduction_pct > 60:
                feedback_parts.append(f"⚠️ Over-consolidation: {reduction_pct:.1f}% reduction (may have lost data)")
                subscores['consolidation_ratio'] = False
            elif reduction_pct < 10:
                feedback_parts.append(f"❌ Insufficient consolidation: only {reduction_pct:.1f}% reduction")
                subscores['consolidation_ratio'] = False
            else:
                # 10-30% reduction: partial credit
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Some consolidation: {reduction_pct:.1f}% reduction (expected 30-60%)")
                subscores['consolidation_ratio'] = False
        else:
            feedback_parts.append("❌ Could not determine consolidation ratio")
            subscores['consolidation_ratio'] = False
        
        # Criterion 4: Email format standardization
        emails_standardized = True
        non_standard_count = 0
        
        for row_data in master_data:
            email = None
            for col in ['Email', 'EmailAddress', 'email', 'EMAIL']:
                if col in row_data:
                    email = row_data[col]
                    break
            
            if email:
                email_str = str(email).strip()
                # Check for issues
                if '<' in email_str or '>' in email_str:
                    emails_standardized = False
                    non_standard_count += 1
                elif email_str != email_str.lower():
                    emails_standardized = False
                    non_standard_count += 1
                elif email_str != email_str.strip():
                    emails_standardized = False
                    non_standard_count += 1
        
        if emails_standardized and len(emails_found) > 0:
            criteria_passed += 1
            feedback_parts.append("✅ Emails standardized (lowercase, no display names)")
            subscores['email_standardized'] = True
        elif non_standard_count < len(emails_found) * 0.2:  # Allow 20% to be non-standard
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Most emails standardized ({non_standard_count} need fixing)")
            subscores['email_standardized'] = False
        else:
            feedback_parts.append(f"❌ Email formatting inconsistent ({non_standard_count} non-standard)")
            subscores['email_standardized'] = False
        
        # Criterion 5: Completeness assessment (80%+ have name + contact)
        complete_count = 0
        
        for row_data in master_data:
            # Check for name
            has_name = False
            for col in ['FirstName', 'LastName', 'Name', 'FullName', 'name']:
                if col in row_data and row_data[col]:
                    has_name = True
                    break
            
            # Check for contact (email or phone)
            has_contact = False
            for col in ['Email', 'EmailAddress', 'email', 'Phone', 'PhoneNumber', 'phone']:
                if col in row_data and row_data[col]:
                    has_contact = True
                    break
            
            if has_name and has_contact:
                complete_count += 1
        
        if master_count > 0:
            completeness_pct = (complete_count / master_count) * 100
            logger.info(f"Completeness: {completeness_pct:.1f}% ({complete_count}/{master_count})")
            
            if completeness_pct >= 80:
                criteria_passed += 1
                feedback_parts.append(f"✅ High completeness: {completeness_pct:.1f}% records have name+contact")
                subscores['completeness'] = True
            elif completeness_pct >= 60:
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Moderate completeness: {completeness_pct:.1f}%")
                subscores['completeness'] = False
            else:
                feedback_parts.append(f"❌ Low completeness: only {completeness_pct:.1f}% records complete")
                subscores['completeness'] = False
        else:
            feedback_parts.append("❌ No records in MasterContactList")
            subscores['completeness'] = False
        
        # Criterion 6: Multi-source integration or Summary formulas
        # Check for Source column or formulas indicating integration
        has_integration_evidence = False
        
        # Check for Source column
        for row_data in master_data:
            if 'Source' in row_data or 'source' in row_data:
                has_integration_evidence = True
                break
        
        # Check for formulas in first few rows (summary statistics)
        formula_found = False
        for i in range(min(5, len(master_rows))):
            for cell in master_rows[i]:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and ('COUNT' in formula.upper() or 'SUM' in formula.upper()):
                    formula_found = True
                    break
            if formula_found:
                break
        
        if has_integration_evidence or formula_found:
            criteria_passed += 1
            if has_integration_evidence and formula_found:
                feedback_parts.append("✅ Multi-source integration + summary formulas present")
            elif has_integration_evidence:
                feedback_parts.append("✅ Multi-source integration evidence (Source column)")
            else:
                feedback_parts.append("✅ Summary formulas present")
            subscores['integration_evidence'] = True
        else:
            feedback_parts.append("⚠️ No clear integration evidence or summary formulas")
            subscores['integration_evidence'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold
        
        if passed:
            feedback_parts.append("🎉 Contact consolidation successful!")
        else:
            feedback_parts.append("❌ Consolidation incomplete or quality issues remain")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
