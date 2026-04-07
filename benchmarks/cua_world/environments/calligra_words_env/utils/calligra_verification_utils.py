#!/usr/bin/env python3
"""Shared verification utilities for Calligra Words tasks.

Calligra Words saves documents in ODF format (.odt). We use the odfpy library
to parse ODF files for verification, with python-docx as fallback for .docx files.
"""

import json
import os
import re
import shutil
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# ODF namespaces
ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
}


def copy_and_parse_odt(copy_from_env, remote_path):
    """Copy an ODF file from the environment and parse it.

    Returns:
        tuple: (temp_dir, content_tree, styles_tree) or (None, None, None) on failure
    """
    temp_dir = tempfile.mkdtemp(prefix="calligra_verify_")
    local_path = os.path.join(temp_dir, "document.odt")

    try:
        copy_from_env(remote_path, local_path)
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return None, None, None

    if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return None, None, None

    try:
        with zipfile.ZipFile(local_path, 'r') as zf:
            content_xml = zf.read('content.xml')
            content_tree = ET.fromstring(content_xml)

            styles_tree = None
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml')
                styles_tree = ET.fromstring(styles_xml)

        return temp_dir, content_tree, styles_tree
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return None, None, None


def copy_and_parse_document(copy_from_env, remote_path):
    """Copy a document (.odt or .docx) from the environment and parse it.

    For .odt files, returns ODF XML trees.
    For .docx files, returns python-docx Document.

    Returns:
        tuple: (temp_dir, doc_object, doc_type) where doc_type is 'odt' or 'docx'
    """
    temp_dir = tempfile.mkdtemp(prefix="calligra_verify_")
    ext = os.path.splitext(remote_path)[1].lower()
    local_path = os.path.join(temp_dir, f"document{ext}")

    try:
        copy_from_env(remote_path, local_path)
    except Exception:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return None, None, None

    if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return None, None, None

    if ext == '.odt':
        try:
            with zipfile.ZipFile(local_path, 'r') as zf:
                content_xml = zf.read('content.xml')
                content_tree = ET.fromstring(content_xml)
                styles_tree = None
                if 'styles.xml' in zf.namelist():
                    styles_xml = zf.read('styles.xml')
                    styles_tree = ET.fromstring(styles_xml)
            return temp_dir, (content_tree, styles_tree), 'odt'
        except Exception:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return None, None, None
    elif ext == '.docx':
        try:
            from docx import Document
            doc = Document(local_path)
            return temp_dir, doc, 'docx'
        except Exception:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return None, None, None
    else:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return None, None, None


def cleanup_verification_temp(temp_dir):
    """Remove temporary verification directory."""
    if temp_dir and os.path.exists(temp_dir):
        shutil.rmtree(temp_dir, ignore_errors=True)


def get_odt_paragraphs(content_tree):
    """Extract all paragraphs from ODF content tree.

    Returns:
        list of dict: Each dict has 'text', 'style_name', 'outline_level'
    """
    paragraphs = []

    body = content_tree.find('.//office:body/office:text', ODF_NS)
    if body is None:
        return paragraphs

    for elem in body:
        tag = elem.tag
        if tag == f"{{{ODF_NS['text']}}}p":
            text = _get_text_content(elem)
            style = elem.get(f"{{{ODF_NS['text']}}}style-name", "")
            paragraphs.append({
                'text': text,
                'style_name': style,
                'outline_level': None,
                'element': elem,
            })
        elif tag == f"{{{ODF_NS['text']}}}h":
            text = _get_text_content(elem)
            style = elem.get(f"{{{ODF_NS['text']}}}style-name", "")
            level = elem.get(f"{{{ODF_NS['text']}}}outline-level", "1")
            paragraphs.append({
                'text': text,
                'style_name': style,
                'outline_level': int(level),
                'element': elem,
            })
        elif tag == f"{{{ODF_NS['text']}}}list":
            # Recursively extract list items
            _extract_list_items(elem, paragraphs)
        elif tag == f"{{{ODF_NS['text']}}}section":
            # Sections may contain paragraphs
            for child in elem:
                if child.tag == f"{{{ODF_NS['text']}}}p":
                    text = _get_text_content(child)
                    style = child.get(f"{{{ODF_NS['text']}}}style-name", "")
                    paragraphs.append({
                        'text': text,
                        'style_name': style,
                        'outline_level': None,
                        'element': child,
                    })

    return paragraphs


def _get_text_content(element):
    """Recursively extract text content from an ODF XML element."""
    parts = []
    if element.text:
        parts.append(element.text)
    for child in element:
        parts.append(_get_text_content(child))
        if child.tail:
            parts.append(child.tail)
    return ''.join(parts)


def _extract_list_items(list_elem, paragraphs):
    """Recursively extract items from an ODF list."""
    ns = ODF_NS['text']
    for item in list_elem.findall(f'{{{ns}}}list-item'):
        for child in item:
            if child.tag == f'{{{ns}}}p':
                text = _get_text_content(child)
                style = child.get(f'{{{ns}}}style-name', '')
                paragraphs.append({
                    'text': text,
                    'style_name': style,
                    'outline_level': None,
                    'element': child,
                    'is_list_item': True,
                })
            elif child.tag == f'{{{ns}}}list':
                _extract_list_items(child, paragraphs)


def get_odt_styles(content_tree, styles_tree=None):
    """Extract style definitions from ODF content and styles.

    Returns:
        dict: style_name -> style properties dict
    """
    styles = {}

    # Automatic styles from content.xml
    auto_styles = content_tree.find('.//office:automatic-styles', ODF_NS)
    if auto_styles is not None:
        for style in auto_styles:
            _parse_style(style, styles)

    # Named styles from styles.xml
    if styles_tree is not None:
        office_styles = styles_tree.find('.//office:styles', ODF_NS)
        if office_styles is not None:
            for style in office_styles:
                _parse_style(style, styles)
        auto_styles2 = styles_tree.find('.//office:automatic-styles', ODF_NS)
        if auto_styles2 is not None:
            for style in auto_styles2:
                _parse_style(style, styles)

    return styles


def _parse_style(style_elem, styles_dict):
    """Parse a single ODF style element into the styles dictionary."""
    ns_style = ODF_NS['style']
    ns_fo = ODF_NS['fo']

    name = style_elem.get(f'{{{ns_style}}}name', '')
    if not name:
        return

    family = style_elem.get(f'{{{ns_style}}}family', '')
    parent = style_elem.get(f'{{{ns_style}}}parent-style-name', '')
    display_name = style_elem.get(f'{{{ns_style}}}display-name', '')

    props = {
        'family': family,
        'parent': parent,
        'display_name': display_name or name,
    }

    # Text properties
    text_props = style_elem.find(f'{{{ns_style}}}text-properties')
    if text_props is not None:
        font_weight = text_props.get(f'{{{ns_fo}}}font-weight', '')
        font_style = text_props.get(f'{{{ns_fo}}}font-style', '')
        font_size = text_props.get(f'{{{ns_fo}}}font-size', '')
        font_name = text_props.get(f'{{{ns_style}}}font-name', '')
        text_decoration = text_props.get(f'{{{ns_style}}}text-underline-style', '')

        props['bold'] = font_weight == 'bold'
        props['italic'] = font_style == 'italic'
        props['font_size'] = font_size
        props['font_name'] = font_name
        props['underline'] = text_decoration not in ('', 'none')

    # Paragraph properties
    para_props = style_elem.find(f'{{{ns_style}}}paragraph-properties')
    if para_props is not None:
        alignment = para_props.get(f'{{{ns_fo}}}text-align', '')
        margin_left = para_props.get(f'{{{ns_fo}}}margin-left', '')
        margin_right = para_props.get(f'{{{ns_fo}}}margin-right', '')
        text_indent = para_props.get(f'{{{ns_fo}}}text-indent', '')
        margin_top = para_props.get(f'{{{ns_fo}}}margin-top', '')
        margin_bottom = para_props.get(f'{{{ns_fo}}}margin-bottom', '')
        line_height = para_props.get(f'{{{ns_fo}}}line-height', '')

        props['alignment'] = alignment
        props['margin_left'] = margin_left
        props['margin_right'] = margin_right
        props['text_indent'] = text_indent
        props['margin_top'] = margin_top
        props['margin_bottom'] = margin_bottom
        props['line_height'] = line_height

    # Page layout properties (for page styles)
    page_props = style_elem.find(f'{{{ns_style}}}page-layout-properties')
    if page_props is not None:
        page_width = page_props.get(f'{{{ns_fo}}}page-width', '')
        page_height = page_props.get(f'{{{ns_fo}}}page-height', '')
        margin_top = page_props.get(f'{{{ns_fo}}}margin-top', '')
        margin_bottom = page_props.get(f'{{{ns_fo}}}margin-bottom', '')
        margin_left = page_props.get(f'{{{ns_fo}}}margin-left', '')
        margin_right = page_props.get(f'{{{ns_fo}}}margin-right', '')

        props['page_width'] = page_width
        props['page_height'] = page_height
        props['page_margin_top'] = margin_top
        props['page_margin_bottom'] = margin_bottom
        props['page_margin_left'] = margin_left
        props['page_margin_right'] = margin_right

    styles_dict[name] = props


def _normalize_style_label(value):
    """Normalize ODF style identifiers for fuzzy matching."""
    if not value:
        return ""
    return value.replace('_20_', ' ').replace('_', ' ').strip().lower()


def _iter_style_chain(styles, style_name):
    """Yield a style and its parents, stopping on cycles."""
    seen = set()
    current = style_name

    while current and current not in seen:
        seen.add(current)
        style = styles.get(current)
        if not style:
            break
        yield current, style
        current = style.get('parent', '')


def _resolve_style_property(styles, style_name, prop_name):
    """Resolve a style property by walking up the parent chain."""
    for _, style in _iter_style_chain(styles, style_name):
        value = style.get(prop_name)
        if value not in ('', None):
            return value
    return ''


def _style_matches_heading_level(styles, style_name, expected_level):
    """Return True if a style chain looks like Heading N."""
    expected = f'heading {expected_level}'
    for name, style in _iter_style_chain(styles, style_name):
        for label in (name, style.get('display_name', ''), style.get('parent', '')):
            if expected in _normalize_style_label(label):
                return True
    return False


def check_heading_styles_odt(content_tree, styles_tree, expected_headings, expected_level):
    """Check if expected headings have the correct outline level in ODF.

    Args:
        content_tree: ODF content tree
        styles_tree: ODF styles tree
        expected_headings: list of heading text strings to check
        expected_level: expected outline level (1, 2, etc.)

    Returns:
        tuple: (matched_count, total_expected, details)
    """
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)
    matched = 0
    details = []

    for expected in expected_headings:
        found = False
        for para in paragraphs:
            if expected.lower().strip() in para['text'].lower().strip():
                if para['outline_level'] == expected_level or _style_matches_heading_level(
                    styles, para['style_name'], expected_level
                ):
                    matched += 1
                    details.append(f"'{expected}': Heading {expected_level} OK")
                    found = True
                elif para['outline_level'] is not None:
                    details.append(f"'{expected}': Wrong level {para['outline_level']} (expected {expected_level})")
                    found = True
                else:
                    details.append(f"'{expected}': Not a heading (plain paragraph)")
                    found = True
                break
        if not found:
            details.append(f"'{expected}': Not found in document")

    return matched, len(expected_headings), details


def check_paragraph_alignment_odt(content_tree, styles_tree, text_pattern, expected_alignment):
    """Check if paragraphs matching a text pattern have the expected alignment.

    Args:
        content_tree: ODF content tree
        styles_tree: ODF styles tree
        text_pattern: regex pattern to match paragraph text
        expected_alignment: 'center', 'justify', 'start', 'end'

    Returns:
        tuple: (matched_count, checked_count, details)
    """
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)

    matched = 0
    checked = 0

    for para in paragraphs:
        if re.search(text_pattern, para['text'], re.IGNORECASE):
            checked += 1
            alignment = _resolve_style_property(styles, para['style_name'], 'alignment')

            if alignment == expected_alignment:
                matched += 1

    return matched, checked


def detect_toc_odt(content_tree):
    """Detect if a Table of Contents exists in the ODF document.

    Returns:
        bool: True if TOC detected
    """
    ns = ODF_NS['text']

    # Method 1: Look for text:table-of-content element
    toc = content_tree.find(f'.//{{{ns}}}table-of-content')
    if toc is not None:
        return True

    # Method 2: Look for a "Table of Contents" heading followed by entries
    paragraphs = get_odt_paragraphs(content_tree)
    for i, para in enumerate(paragraphs):
        text_lower = para['text'].lower().strip()
        if text_lower in ('table of contents', 'contents', 'toc'):
            # Check if next few paragraphs look like TOC entries
            toc_like = 0
            for j in range(i + 1, min(i + 10, len(paragraphs))):
                next_text = paragraphs[j]['text'].strip()
                # TOC entries often have page numbers or tab-separated content
                if re.search(r'\d+$', next_text) or '...' in next_text:
                    toc_like += 1
            if toc_like >= 2:
                return True

    return False


def get_odt_tables(content_tree):
    """Extract tables from ODF content tree.

    Returns:
        list of dict: Each dict has 'name', 'rows' (list of list of cell text)
    """
    tables = []
    ns_table = ODF_NS['table']
    ns_text = ODF_NS['text']

    for table_elem in content_tree.iter(f'{{{ns_table}}}table'):
        table_name = table_elem.get(f'{{{ns_table}}}name', '')
        rows = []

        for row_elem in table_elem.iter(f'{{{ns_table}}}table-row'):
            cells = []
            for cell_elem in row_elem.iter(f'{{{ns_table}}}table-cell'):
                cell_text_parts = []
                for p in cell_elem.iter(f'{{{ns_text}}}p'):
                    cell_text_parts.append(_get_text_content(p))
                cells.append(' '.join(cell_text_parts))
            if cells:
                rows.append(cells)

        tables.append({'name': table_name, 'rows': rows})

    return tables


def get_odt_page_layout(styles_tree):
    """Extract page layout properties from ODF styles.

    Returns:
        dict: page layout properties or empty dict
    """
    if styles_tree is None:
        return {}

    ns_style = ODF_NS['style']
    ns_fo = ODF_NS['fo']

    result = {}

    # Find page-layout elements in automatic-styles
    for page_layout in styles_tree.iter(f'{{{ns_style}}}page-layout'):
        name = page_layout.get(f'{{{ns_style}}}name', '')
        props = page_layout.find(f'{{{ns_style}}}page-layout-properties')
        if props is not None:
            layout = {
                'name': name,
                'page_width': props.get(f'{{{ns_fo}}}page-width', ''),
                'page_height': props.get(f'{{{ns_fo}}}page-height', ''),
                'margin_top': props.get(f'{{{ns_fo}}}margin-top', ''),
                'margin_bottom': props.get(f'{{{ns_fo}}}margin-bottom', ''),
                'margin_left': props.get(f'{{{ns_fo}}}margin-left', ''),
                'margin_right': props.get(f'{{{ns_fo}}}margin-right', ''),
                'print_orientation': props.get(f'{{{ns_style}}}print-orientation', ''),
            }

            # Check for columns
            columns = props.find(f'{{{ns_style}}}columns')
            if columns is not None:
                num_cols = columns.get(f'{{{ns_fo}}}column-count',
                                       columns.get(f'{{{ns_style}}}num', '1'))
                layout['num_columns'] = int(num_cols) if num_cols else 1
            else:
                layout['num_columns'] = 1

            # Check for header/footer
            header = page_layout.find(f'{{{ns_style}}}header-style')
            footer = page_layout.find(f'{{{ns_style}}}footer-style')
            layout['has_header_style'] = header is not None
            layout['has_footer_style'] = footer is not None

            result[name] = layout

    return result


def parse_odf_measurement(value_str):
    """Parse an ODF measurement string (e.g., '2.54cm', '1in', '72pt') to inches.

    Returns:
        float: value in inches, or 0.0 if parsing fails
    """
    if not value_str:
        return 0.0

    match = re.match(r'([0-9.]+)\s*(cm|mm|in|pt|pc|px)?', value_str)
    if not match:
        return 0.0

    val = float(match.group(1))
    unit = match.group(2) or 'in'

    if unit == 'cm':
        return val / 2.54
    elif unit == 'mm':
        return val / 25.4
    elif unit == 'in':
        return val
    elif unit == 'pt':
        return val / 72.0
    elif unit == 'pc':
        return val / 6.0
    elif unit == 'px':
        return val / 96.0
    return 0.0


def check_text_bold_odt(content_tree, styles_tree, text_pattern):
    """Check if text matching pattern is bold.

    Returns:
        bool
    """
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)

    for para in paragraphs:
        if re.search(text_pattern, para['text'], re.IGNORECASE):
            if _resolve_style_property(styles, para['style_name'], 'bold'):
                return True
            # Check inline spans in the element
            elem = para.get('element')
            if elem is not None:
                for span in elem.iter(f"{{{ODF_NS['text']}}}span"):
                    span_style = span.get(f"{{{ODF_NS['text']}}}style-name", "")
                    if _resolve_style_property(styles, span_style, 'bold'):
                        return True
    return False


def check_text_italic_odt(content_tree, styles_tree, text_pattern):
    """Check if text matching pattern is italic.

    Returns:
        bool
    """
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)

    for para in paragraphs:
        if re.search(text_pattern, para['text'], re.IGNORECASE):
            if _resolve_style_property(styles, para['style_name'], 'italic'):
                return True
            elem = para.get('element')
            if elem is not None:
                for span in elem.iter(f"{{{ODF_NS['text']}}}span"):
                    span_style = span.get(f"{{{ODF_NS['text']}}}style-name", "")
                    if _resolve_style_property(styles, span_style, 'italic'):
                        return True
    return False


def check_text_font_size_odt(content_tree, styles_tree, text_pattern, min_points):
    """Check whether matching text has at least the requested point size."""
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)

    for para in paragraphs:
        if not re.search(text_pattern, para['text'], re.IGNORECASE):
            continue

        size_candidates = []

        para_size = _resolve_style_property(styles, para['style_name'], 'font_size')
        if para_size:
            size_candidates.append(parse_odf_measurement(para_size) * 72.0)

        elem = para.get('element')
        if elem is not None:
            for span in elem.iter(f"{{{ODF_NS['text']}}}span"):
                span_style = span.get(f"{{{ODF_NS['text']}}}style-name", "")
                span_size = _resolve_style_property(styles, span_style, 'font_size')
                if span_size:
                    size_candidates.append(parse_odf_measurement(span_size) * 72.0)

        if size_candidates and max(size_candidates) >= min_points:
            return True

    return False


def get_document_text_odt(content_tree):
    """Extract all text from ODF content tree.

    Returns:
        str: all document text joined by newlines
    """
    paragraphs = get_odt_paragraphs(content_tree)
    return '\n'.join(p['text'] for p in paragraphs)


def vlm_verify_screenshot(env_info, prompt_text):
    """Query VLM with a structured prompt on the final screenshot.

    Args:
        env_info: Environment info dict (contains query_vlm, get_final_screenshot)
        prompt_text: str prompt to ask VLM

    Returns:
        dict or None: VLM response parsed as JSON, or None if unavailable
    """
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if not query_vlm or not get_final_screenshot:
        return None

    try:
        episode_dir = env_info.get('episode_dir', '')
        screenshot = get_final_screenshot(episode_dir)
        if not screenshot:
            return None

        result = query_vlm(image=screenshot, prompt=prompt_text)
        if isinstance(result, str):
            # Try to parse as JSON
            json_match = re.search(r'\{[^{}]*\}', result, re.DOTALL)
            if json_match:
                return json.loads(json_match.group())
        elif isinstance(result, dict):
            return result
    except Exception:
        pass

    return None
