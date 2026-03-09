#!/usr/bin/env python3
"""Shared Python utilities for PsychoPy task verification."""

import xml.etree.ElementTree as ET
import csv
import os


def parse_psyexp(filepath):
    """Parse a .psyexp XML file and return structured data.

    Returns dict with keys: routines, loops, components, settings, or None on error.
    """
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()

        result = {
            'routines': [],
            'loops': [],
            'components': [],
            'settings': {},
            'valid': True
        }

        # Extract routines
        for routine in root.iter('Routine'):
            name = routine.get('name', 'unnamed')
            components = []
            for child in routine:
                comp_type = child.tag
                comp_name = child.get('name', 'unnamed')
                components.append({'type': comp_type, 'name': comp_name})
            result['routines'].append({'name': name, 'components': components})
            result['components'].extend(components)

        # Extract loops
        for loop in root.iter('LoopInitiator'):
            loop_elem = loop.find('Param[@name="nReps"]')
            nreps = loop_elem.get('val', '') if loop_elem is not None else ''
            conds_elem = loop.find('Param[@name="conditionsFile"]')
            conds_file = conds_elem.get('val', '') if conds_elem is not None else ''
            result['loops'].append({
                'nReps': nreps,
                'conditionsFile': conds_file
            })

        # Extract settings
        settings = root.find('Settings')
        if settings is not None:
            for param in settings.findall('Param'):
                name = param.get('name', '')
                val = param.get('val', '')
                result['settings'][name] = val

        return result

    except Exception:
        return None


def validate_conditions_csv(filepath, required_columns=None, min_rows=1):
    """Validate a conditions CSV file.

    Returns dict with validation results.
    """
    result = {
        'valid': False,
        'columns': [],
        'row_count': 0,
        'missing_columns': [],
        'errors': []
    }

    if not os.path.exists(filepath):
        result['errors'].append(f'File not found: {filepath}')
        return result

    try:
        with open(filepath, 'r', newline='') as f:
            reader = csv.DictReader(f)
            result['columns'] = list(reader.fieldnames or [])
            rows = list(reader)
            result['row_count'] = len(rows)

        if required_columns:
            cols_lower = [c.lower() for c in result['columns']]
            for req in required_columns:
                if req.lower() not in cols_lower:
                    result['missing_columns'].append(req)

        if result['row_count'] < min_rows:
            result['errors'].append(f'Only {result["row_count"]} rows, need {min_rows}')

        if not result['missing_columns'] and not result['errors']:
            result['valid'] = True

    except Exception as e:
        result['errors'].append(str(e))

    return result
