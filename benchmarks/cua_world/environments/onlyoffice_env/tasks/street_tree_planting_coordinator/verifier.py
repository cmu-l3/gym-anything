#!/usr/bin/env python3
"""
Verifier for Street Tree Planting Coordinator task
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


def verify_tree_planting_plan(traj, env_info, task_info):
    """
    Verify that tree planting plan is complete and respects constraints.

    Scoring breakdown:
    - Constraint compliance: 35 points (critical)
    - Assignment completeness: 20 points
    - Calculations present: 20 points
    - Documentation: 15 points
    - Logical consistency: 10 points
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/StreetTreePlanting.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_tree_')

    try:
        # Copy and parse the workbook
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load workbook: {error}"}

        # Verify all required sheets exist
        required_sheets = ["TreeSpecies", "Sites", "Volunteers", "Master Plan"]
        missing_sheets = [s for s in required_sheets if s not in wb.sheetnames]
        if missing_sheets:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Missing required sheets: {', '.join(missing_sheets)}"
            }

        # Load reference data
        species_data = load_species_data(wb)
        sites_data = load_sites_data(wb)
        volunteers_data = load_volunteers_data(wb)
        
        # Load master plan
        plan_data = load_master_plan(wb)

        # Initialize scoring components
        score_components = {
            'constraint_compliance': 0,  # max 35
            'assignments_complete': 0,   # max 20
            'calculations_accurate': 0,  # max 20
            'documentation': 0,          # max 15
            'logical_consistency': 0     # max 10
        }
        
        feedback_parts = []

        # ====================================================================
        # A. CONSTRAINT COMPLIANCE (35 points) - CRITICAL
        # ====================================================================
        
        # Check overhead wire violations
        overhead_violations = check_overhead_wire_constraint(plan_data, sites_data, species_data)
        
        # Check pollen allergy violations
        pollen_violations = check_pollen_constraint(plan_data, sites_data, species_data)
        
        # Check sidewalk/root system violations
        sidewalk_violations = check_sidewalk_constraint(plan_data, sites_data, species_data)
        
        # Check inventory violations
        inventory_violations, inventory_usage = check_inventory_constraint(plan_data, species_data)
        
        # Score constraint compliance
        critical_violations = overhead_violations + pollen_violations
        minor_violations = sidewalk_violations + inventory_violations
        
        if critical_violations == 0 and minor_violations == 0:
            score_components['constraint_compliance'] = 35
            feedback_parts.append("✅ All constraints satisfied (35/35)")
        elif critical_violations == 0 and minor_violations <= 2:
            score_components['constraint_compliance'] = 28
            feedback_parts.append(f"✅ Critical constraints met, {minor_violations} minor violations (28/35)")
        elif critical_violations <= 1:
            score_components['constraint_compliance'] = 20
            feedback_parts.append(f"⚠️ {critical_violations} critical violation(s), {minor_violations} minor (20/35)")
        else:
            score_components['constraint_compliance'] = 10
            feedback_parts.append(f"❌ {critical_violations} critical violations, {minor_violations} minor (10/35)")
        
        # Add specific violation details
        if overhead_violations > 0:
            feedback_parts.append(f"❌ {overhead_violations} overhead wire violations (tall tree under wires)")
        if pollen_violations > 0:
            feedback_parts.append(f"❌ {pollen_violations} pollen allergy violations")
        if sidewalk_violations > 0:
            feedback_parts.append(f"⚠️ {sidewalk_violations} sidewalk/root violations")
        if inventory_violations > 0:
            feedback_parts.append(f"⚠️ {inventory_violations} species over-assigned")

        # ====================================================================
        # B. ASSIGNMENT COMPLETENESS (20 points)
        # ====================================================================
        
        sites_with_species = sum(1 for p in plan_data if p.get('species') and p['species'] not in ['', None, '[empty]'])
        sites_with_volunteers = sum(1 for p in plan_data if p.get('volunteer') and p['volunteer'] not in ['', None, '[empty]'])
        
        species_completeness = (sites_with_species / 12) * 10
        volunteer_completeness = (sites_with_volunteers / 12) * 10
        
        score_components['assignments_complete'] = int(species_completeness + volunteer_completeness)
        
        if sites_with_species == 12 and sites_with_volunteers == 12:
            feedback_parts.append("✅ All sites have species and care captains (20/20)")
        elif sites_with_species >= 10 and sites_with_volunteers >= 10:
            feedback_parts.append(f"✅ Most sites assigned: {sites_with_species}/12 species, {sites_with_volunteers}/12 volunteers ({score_components['assignments_complete']}/20)")
        else:
            feedback_parts.append(f"⚠️ Incomplete: {sites_with_species}/12 species, {sites_with_volunteers}/12 volunteers ({score_components['assignments_complete']}/20)")
        
        # Check volunteer load balance
        volunteer_load = check_volunteer_load_balance(plan_data, volunteers_data)
        overloaded = [v for v, count in volunteer_load.items() if count > 3]
        if overloaded:
            feedback_parts.append(f"⚠️ Volunteers overloaded (>3 trees): {', '.join(overloaded)}")

        # ====================================================================
        # C. CALCULATIONS PRESENT (20 points)
        # ====================================================================
        
        watering_calcs = sum(1 for p in plan_data if p.get('watering') and isinstance(p['watering'], (int, float)) and p['watering'] > 0)
        
        if watering_calcs >= 12:
            score_components['calculations_accurate'] = 20
            feedback_parts.append("✅ All watering calculations present (20/20)")
        elif watering_calcs >= 10:
            score_components['calculations_accurate'] = 16
            feedback_parts.append(f"✅ Most watering calculations present: {watering_calcs}/12 (16/20)")
        elif watering_calcs >= 6:
            score_components['calculations_accurate'] = 10
            feedback_parts.append(f"⚠️ Some watering calculations: {watering_calcs}/12 (10/20)")
        else:
            score_components['calculations_accurate'] = 5
            feedback_parts.append(f"❌ Few watering calculations: {watering_calcs}/12 (5/20)")
        
        # Verify watering values are reasonable (1000-2000 gallons per tree)
        reasonable_watering = sum(1 for p in plan_data if isinstance(p.get('watering'), (int, float)) and 1000 <= p['watering'] <= 2000)
        if reasonable_watering < watering_calcs and watering_calcs > 0:
            feedback_parts.append(f"⚠️ Some watering values seem unreasonable (expected 1000-2000 gallons/tree)")

        # ====================================================================
        # D. DOCUMENTATION QUALITY (15 points)
        # ====================================================================
        
        rationale_count = sum(1 for p in plan_data if p.get('rationale') and isinstance(p['rationale'], str) and len(p['rationale'].strip()) > 10)
        
        if rationale_count >= 10:
            score_components['documentation'] = 15
            feedback_parts.append(f"✅ Good documentation: {rationale_count}/12 sites have rationale (15/15)")
        elif rationale_count >= 8:
            score_components['documentation'] = 12
            feedback_parts.append(f"✅ Adequate documentation: {rationale_count}/12 sites (12/15)")
        elif rationale_count >= 5:
            score_components['documentation'] = 8
            feedback_parts.append(f"⚠️ Minimal documentation: {rationale_count}/12 sites (8/15)")
        else:
            score_components['documentation'] = 3
            feedback_parts.append(f"❌ Poor documentation: {rationale_count}/12 sites (3/15)")
        
        # Check if rationale references actual constraints
        relevant_rationale = count_relevant_rationale(plan_data, sites_data)
        if relevant_rationale >= rationale_count * 0.7:
            feedback_parts.append("✅ Rationale references actual constraints")
        elif relevant_rationale > 0:
            feedback_parts.append("⚠️ Some rationale doesn't reference site constraints")

        # ====================================================================
        # E. LOGICAL CONSISTENCY (10 points)
        # ====================================================================
        
        # Check species diversity (should use at least 4 different species)
        unique_species = len(set(p.get('species') for p in plan_data if p.get('species') and p['species'] not in ['', None, '[empty]']))
        
        diversity_points = min(5, unique_species)
        score_components['logical_consistency'] += diversity_points
        
        if unique_species >= 4:
            feedback_parts.append(f"✅ Good species diversity: {unique_species} species used")
        else:
            feedback_parts.append(f"⚠️ Low species diversity: only {unique_species} species used")
        
        # Check preference matching (at least 50% of stated preferences honored)
        preference_sites = [s for s in sites_data if s['preference'] and 'no preference' not in s['preference'].lower()]
        if len(preference_sites) > 0:
            preferences_honored = count_preferences_honored(plan_data, sites_data, species_data)
            if preferences_honored / len(preference_sites) >= 0.5:
                score_components['logical_consistency'] += 5
                feedback_parts.append(f"✅ Resident preferences considered: {preferences_honored}/{len(preference_sites)} honored")
            else:
                score_components['logical_consistency'] += 2
                feedback_parts.append(f"⚠️ Few preferences honored: {preferences_honored}/{len(preference_sites)}")
        else:
            score_components['logical_consistency'] += 5  # Give full points if no preferences to check

        # ====================================================================
        # FINAL SCORING
        # ====================================================================
        
        total_score = sum(score_components.values())
        passed = total_score >= 70
        
        # Add summary
        feedback_parts.insert(0, f"Total Score: {total_score}/100 ({', '.join(f'{k.replace('_', ' ').title()}: {v}' for k, v in score_components.items())})")
        
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def load_species_data(wb):
    """Load tree species reference data"""
    ws = wb["TreeSpecies"]
    species = {}
    
    for row in range(2, 10):  # 8 species
        name = ws.cell(row=row, column=1).value
        if name:
            species[name.strip().lower()] = {
                'name': name.strip(),
                'height': ws.cell(row=row, column=2).value or 0,
                'spread': ws.cell(row=row, column=3).value or '',
                'roots': ws.cell(row=row, column=4).value or '',
                'drought': ws.cell(row=row, column=5).value or '',
                'pollen': ws.cell(row=row, column=6).value or '',
                'available': ws.cell(row=row, column=7).value or 0
            }
    
    return species


def load_sites_data(wb):
    """Load planting site data"""
    ws = wb["Sites"]
    sites = []
    
    for row in range(2, 14):  # 12 sites
        site_id = ws.cell(row=row, column=1).value
        if site_id:
            sites.append({
                'site_id': str(site_id).strip(),
                'address': ws.cell(row=row, column=2).value or '',
                'overhead_wires': str(ws.cell(row=row, column=3).value or '').strip().lower() == 'yes',
                'sidewalk_width': float(ws.cell(row=row, column=4).value or 0),
                'preference': ws.cell(row=row, column=5).value or ''
            })
    
    return sites


def load_volunteers_data(wb):
    """Load volunteer data"""
    ws = wb["Volunteers"]
    volunteers = {}
    
    for row in range(2, 9):  # 7 volunteers
        name = ws.cell(row=row, column=1).value
        if name:
            volunteers[name.strip().lower()] = {
                'name': name.strip(),
                'email': ws.cell(row=row, column=2).value or '',
                'phone': ws.cell(row=row, column=3).value or '',
                'availability': ws.cell(row=row, column=4).value or ''
            }
    
    return volunteers


def load_master_plan(wb):
    """Load master plan data"""
    ws = wb["Master Plan"]
    plan = []
    
    for row in range(2, 14):  # 12 sites
        site_id = ws.cell(row=row, column=1).value
        species = ws.cell(row=row, column=3).value
        volunteer = ws.cell(row=row, column=4).value
        phone = ws.cell(row=row, column=5).value
        watering = ws.cell(row=row, column=6).value
        rationale = ws.cell(row=row, column=7).value
        
        plan.append({
            'site_id': str(site_id).strip() if site_id else '',
            'species': species.strip() if isinstance(species, str) else species,
            'volunteer': volunteer.strip() if isinstance(volunteer, str) else volunteer,
            'phone': phone,
            'watering': watering,
            'rationale': rationale.strip() if isinstance(rationale, str) else ''
        })
    
    return plan


def check_overhead_wire_constraint(plan_data, sites_data, species_data):
    """Check for overhead wire violations"""
    violations = 0
    
    for plan_entry, site_entry in zip(plan_data, sites_data):
        if site_entry['overhead_wires'] and plan_entry.get('species'):
            species_name = str(plan_entry['species']).strip().lower()
            species_info = species_data.get(species_name)
            
            if species_info:
                height = species_info.get('height', 0)
                if height >= 25:  # Violation: tall tree under wires
                    violations += 1
                    logger.info(f"Overhead wire violation at {site_entry['site_id']}: {species_info['name']} ({height}ft) under wires")
    
    return violations


def check_pollen_constraint(plan_data, sites_data, species_data):
    """Check for pollen allergy violations"""
    violations = 0
    
    for plan_entry, site_entry in zip(plan_data, sites_data):
        preference = site_entry['preference'].lower()
        if 'pollen allergy' in preference or 'allergy' in preference:
            species_name = str(plan_entry.get('species', '')).strip().lower()
            species_info = species_data.get(species_name)
            
            if species_info:
                pollen = species_info.get('pollen', '').lower()
                if 'high' in pollen or 'moderate' in pollen:
                    violations += 1
                    logger.info(f"Pollen violation at {site_entry['site_id']}: {species_info['name']} has {pollen} pollen")
    
    return violations


def check_sidewalk_constraint(plan_data, sites_data, species_data):
    """Check for sidewalk/root system violations"""
    violations = 0
    
    for plan_entry, site_entry in zip(plan_data, sites_data):
        sidewalk_width = site_entry['sidewalk_width']
        if sidewalk_width < 5.0 and plan_entry.get('species'):
            species_name = str(plan_entry['species']).strip().lower()
            species_info = species_data.get(species_name)
            
            if species_info:
                roots = species_info.get('roots', '').lower()
                if 'aggressive' in roots:
                    violations += 1
                    logger.info(f"Sidewalk violation at {site_entry['site_id']}: aggressive roots on narrow sidewalk ({sidewalk_width}ft)")
    
    return violations


def check_inventory_constraint(plan_data, species_data):
    """Check if any species is over-assigned"""
    violations = 0
    usage = {}
    
    for plan_entry in plan_data:
        species_name = str(plan_entry.get('species', '')).strip().lower()
        if species_name and species_name in species_data:
            usage[species_name] = usage.get(species_name, 0) + 1
    
    for species_name, count in usage.items():
        available = species_data[species_name]['available']
        if count > available:
            violations += 1
            logger.info(f"Inventory violation: {species_data[species_name]['name']} assigned {count} times but only {available} available")
    
    return violations, usage


def check_volunteer_load_balance(plan_data, volunteers_data):
    """Count how many sites each volunteer is assigned to"""
    volunteer_load = {}
    
    for plan_entry in plan_data:
        volunteer = str(plan_entry.get('volunteer', '')).strip().lower()
        if volunteer and volunteer != '[empty]':
            volunteer_load[volunteer] = volunteer_load.get(volunteer, 0) + 1
    
    return volunteer_load


def count_relevant_rationale(plan_data, sites_data):
    """Count how many rationale entries reference actual site constraints"""
    relevant_count = 0
    
    keywords = ['overhead', 'wire', 'sidewalk', 'narrow', 'pollen', 'allergy', 
                'shade', 'flowering', 'preference', 'constraint', 'root', 'height']
    
    for plan_entry in plan_data:
        rationale = str(plan_entry.get('rationale', '')).lower()
        if any(keyword in rationale for keyword in keywords):
            relevant_count += 1
    
    return relevant_count


def count_preferences_honored(plan_data, sites_data, species_data):
    """Count how many resident preferences were honored"""
    honored = 0
    
    for plan_entry, site_entry in zip(plan_data, sites_data):
        preference = site_entry['preference'].lower()
        if not preference or 'no preference' in preference:
            continue
        
        species_name = str(plan_entry.get('species', '')).strip().lower()
        species_info = species_data.get(species_name)
        
        if not species_info:
            continue
        
        # Check various preference types
        if 'shade' in preference:
            if species_info['height'] >= 20:  # Tall trees provide shade
                honored += 1
                continue
        
        if 'flowering' in preference or 'flower' in preference:
            if any(name in species_info['name'].lower() for name in ['maple', 'dogwood', 'redbud', 'serviceberry']):
                honored += 1
                continue
        
        if 'low maintenance' in preference:
            if 'high' in species_info['drought'].lower():
                honored += 1
                continue
        
        if 'fast' in preference or 'big' in preference:
            if species_info['height'] >= 35:
                honored += 1
                continue
        
        if 'small' in preference:
            if species_info['height'] <= 20:
                honored += 1
                continue
    
    return honored