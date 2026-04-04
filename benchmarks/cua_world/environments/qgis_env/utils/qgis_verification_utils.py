#!/usr/bin/env python3
"""
QGIS verification utilities.
Shared functions for verifying QGIS task completion.
"""

import os
import json
import tempfile
import shutil
import zipfile
from xml.etree import ElementTree as ET


def setup_verification_environment(copy_from_env, remote_path, file_type='json'):
    """
    Set up verification environment by copying file from container.

    Args:
        copy_from_env: Function to copy files from container
        remote_path: Path in the container
        file_type: Type of file ('json', 'xml', 'zip', 'image')

    Returns:
        tuple: (success, file_info_dict, error_message)
    """
    temp_dir = tempfile.mkdtemp()
    local_path = os.path.join(temp_dir, os.path.basename(remote_path))

    try:
        copy_from_env(remote_path, local_path)

        file_info = {
            'temp_dir': temp_dir,
            'local_path': local_path,
            'size_bytes': os.path.getsize(local_path),
            'data': {}
        }

        if file_type == 'json':
            with open(local_path, 'r') as f:
                file_info['data'] = json.load(f)
        elif file_type == 'xml':
            tree = ET.parse(local_path)
            file_info['data'] = {'root': tree.getroot()}
        elif file_type == 'zip':
            with zipfile.ZipFile(local_path, 'r') as zf:
                file_info['data'] = {'namelist': zf.namelist()}
        elif file_type == 'image':
            try:
                from PIL import Image
                img = Image.open(local_path)
                file_info['data'] = {
                    'size': img.size,
                    'format': img.format,
                    'mode': img.mode,
                    'size_kb': os.path.getsize(local_path) / 1024
                }
            except ImportError:
                file_info['data'] = {
                    'size_kb': os.path.getsize(local_path) / 1024
                }

        return True, file_info, None

    except Exception as e:
        cleanup_verification_environment(temp_dir)
        return False, None, str(e)


def cleanup_verification_environment(temp_dir):
    """Clean up temporary verification directory."""
    if temp_dir and os.path.exists(temp_dir):
        try:
            shutil.rmtree(temp_dir)
        except Exception:
            pass


def verify_qgis_project_exists(copy_from_env, project_path):
    """
    Verify that a QGIS project file exists and is valid.

    Args:
        copy_from_env: Function to copy files from container
        project_path: Path to the project file in container

    Returns:
        tuple: (exists, is_valid, project_info)
    """
    if project_path.endswith('.qgz'):
        file_type = 'zip'
    elif project_path.endswith('.qgs'):
        file_type = 'xml'
    else:
        file_type = 'json'

    success, file_info, error = setup_verification_environment(
        copy_from_env, project_path, file_type
    )

    if not success:
        return False, False, {'error': error}

    project_info = {
        'size_bytes': file_info['size_bytes'],
        'path': project_path
    }

    is_valid = False

    if file_type == 'xml':
        # Check for QGIS project XML structure
        root = file_info['data'].get('root')
        if root is not None and root.tag == 'qgis':
            is_valid = True
            # Extract some project info
            project_info['version'] = root.get('version', 'unknown')
            layers = root.findall('.//maplayer')
            project_info['layer_count'] = len(layers)
    elif file_type == 'zip':
        # QGZ files contain a .qgs file inside
        namelist = file_info['data'].get('namelist', [])
        if any(name.endswith('.qgs') for name in namelist):
            is_valid = True
            project_info['contents'] = namelist

    cleanup_verification_environment(file_info['temp_dir'])

    return True, is_valid, project_info


def verify_layer_exists(copy_from_env, project_path, layer_name=None, layer_type=None):
    """
    Verify that a layer exists in a QGIS project.

    Args:
        copy_from_env: Function to copy files from container
        project_path: Path to the project file
        layer_name: Expected layer name (optional)
        layer_type: Expected layer type (optional, e.g., 'vector', 'raster')

    Returns:
        tuple: (found, layer_info)
    """
    success, file_info, error = setup_verification_environment(
        copy_from_env, project_path, 'xml'
    )

    if not success:
        return False, {'error': error}

    root = file_info['data'].get('root')
    if root is None:
        cleanup_verification_environment(file_info['temp_dir'])
        return False, {'error': 'Invalid XML'}

    layers = root.findall('.//maplayer')
    layer_info = {
        'total_layers': len(layers),
        'layers': []
    }

    found = False
    for layer in layers:
        name_elem = layer.find('layername')
        lname = name_elem.text if name_elem is not None else 'unknown'
        ltype = layer.get('type', 'unknown')

        layer_info['layers'].append({
            'name': lname,
            'type': ltype
        })

        # Check if this matches our criteria
        name_match = (layer_name is None or lname == layer_name or
                     layer_name.lower() in lname.lower())
        type_match = (layer_type is None or ltype == layer_type)

        if name_match and type_match:
            found = True

    cleanup_verification_environment(file_info['temp_dir'])
    return found, layer_info


def verify_screenshot_exists(copy_from_env, screenshot_path):
    """
    Verify that a screenshot exists and has reasonable quality.

    Args:
        copy_from_env: Function to copy files from container
        screenshot_path: Path to the screenshot in container

    Returns:
        tuple: (exists, quality_ok, image_info)
    """
    success, file_info, error = setup_verification_environment(
        copy_from_env, screenshot_path, 'image'
    )

    if not success:
        return False, False, {'error': error}

    image_data = file_info.get('data', {})
    size_kb = image_data.get('size_kb', 0)

    # Consider quality OK if file is at least 10KB
    quality_ok = size_kb > 10

    cleanup_verification_environment(file_info['temp_dir'])

    return True, quality_ok, image_data
