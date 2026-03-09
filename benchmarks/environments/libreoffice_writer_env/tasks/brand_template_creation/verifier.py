#!/usr/bin/env python3
"""Verifier for brand_template_creation."""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import zipfile


NS = {
    "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    "style": "urn:oasis:names:tc:opendocument:xmlns:style:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
    "draw": "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0",
    "fo": "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0",
    "xlink": "http://www.w3.org/1999/xlink",
}


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/brand_template_creation_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _parse_inches(value):
    if not value:
        return 0.0
    value = value.strip().lower()
    try:
        if value.endswith("in"):
            return float(value[:-2])
        if value.endswith("cm"):
            return float(value[:-2]) / 2.54
        if value.endswith("mm"):
            return float(value[:-2]) / 25.4
        if value.endswith("pt"):
            return float(value[:-2]) / 72.0
        return float(value)
    except ValueError:
        return 0.0


def _style_text_props(style_elem):
    props = style_elem.find("style:text-properties", NS)
    para = style_elem.find("style:paragraph-properties", NS)
    return {
        "font_name": props.get(f"{{{NS['style']}}}font-name", "") if props is not None else "",
        "font_size": props.get(f"{{{NS['fo']}}}font-size", "") if props is not None else "",
        "font_weight": props.get(f"{{{NS['fo']}}}font-weight", "") if props is not None else "",
        "color": props.get(f"{{{NS['fo']}}}color", "") if props is not None else "",
        "alignment": para.get(f"{{{NS['fo']}}}text-align", "") if para is not None else "",
    }


def _find_style(root, style_name):
    for style_elem in root.findall(".//style:style", NS):
        name = style_elem.get(f"{{{NS['style']}}}name", "")
        display_name = style_elem.get(f"{{{NS['style']}}}display-name", "")
        if style_name in {name, display_name}:
            return style_elem
    return None


def verify_brand_template_creation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {exc}"}

    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Template file not found."}
    if not result.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Template file was not saved during the task."}

    metadata = task_info.get("metadata", {})
    output_path = metadata.get("expected_output_path", "/home/ga/Documents/apex_letterhead.ott")
    footer_text = metadata.get("footer_text", "Apex Innovations | 123 Tech Blvd, Silicon Valley, CA")
    title_style_name = metadata.get("styles", {}).get("title", {}).get("name", "Apex Title")
    body_style_name = metadata.get("styles", {}).get("body", {}).get("name", "Apex Body")

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".ott")
    tmp.close()
    try:
        copy_from_env(output_path, tmp.name)
        with zipfile.ZipFile(tmp.name, "r") as archive:
            namelist = set(archive.namelist())
            mimetype = archive.read("mimetype").decode("utf-8", errors="replace") if "mimetype" in namelist else ""
            styles_root = ET.fromstring(archive.read("styles.xml"))
            content_root = ET.fromstring(archive.read("content.xml"))
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output template: {exc}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    if mimetype == "application/vnd.oasis.opendocument.text-template":
        score += 10
        feedback.append("Saved as ODF text template.")
    else:
        feedback.append(f"Wrong mimetype '{mimetype}'.")

    page_layout = styles_root.find(".//style:page-layout", NS)
    if page_layout is not None:
        props = page_layout.find("style:page-layout-properties", NS)
    else:
        props = None

    if props is not None:
        top = _parse_inches(props.get(f"{{{NS['fo']}}}margin-top"))
        left = _parse_inches(props.get(f"{{{NS['fo']}}}margin-left"))
        right = _parse_inches(props.get(f"{{{NS['fo']}}}margin-right"))
        bottom = _parse_inches(props.get(f"{{{NS['fo']}}}margin-bottom"))
        if abs(top - 2.0) <= 0.15 and all(abs(v - 1.0) <= 0.15 for v in [left, right, bottom]):
            score += 20
            feedback.append("Page margins match the specification.")
        else:
            feedback.append(
                f"Page margins incorrect (top={top:.2f}, left={left:.2f}, right={right:.2f}, bottom={bottom:.2f})."
            )
    else:
        feedback.append("Page layout not found in template.")

    styles_xml = ET.tostring(styles_root, encoding="unicode")
    content_xml = ET.tostring(content_root, encoding="unicode")
    if "draw:image" in styles_xml and "apex_logo" in styles_xml.lower():
        score += 20
        feedback.append("Header contains the logo image.")
    elif "draw:image" in content_xml and "apex_logo" in content_xml.lower():
        score += 20
        feedback.append("Template contains the logo image.")
    else:
        feedback.append("Logo image not detected in the template header/content.")

    footer_ok = False
    for footer in styles_root.findall(".//style:footer", NS):
        footer_text_content = "".join(footer.itertext()).strip()
        if footer_text in footer_text_content:
            footer_ok = True
            break
    if footer_ok and ("text-align=\"center\"" in styles_xml or "text-align='center'" in styles_xml):
        score += 20
        feedback.append("Footer text found and centered.")
    elif footer_ok:
        score += 12
        feedback.append("Footer text found, but centered alignment was not confirmed.")
    else:
        feedback.append("Footer text not found.")

    title_style = _find_style(styles_root, title_style_name)
    if title_style is not None:
        title_props = _style_text_props(title_style)
        font_ok = any(name in title_props["font_name"] for name in ("Liberation Sans", "Arial"))
        size_ok = title_props["font_size"].startswith("18")
        bold_ok = title_props["font_weight"] == "bold"
        color_ok = title_props["color"].lower() in {"#00008b", "#000080"}
        if font_ok and size_ok and bold_ok and color_ok:
            score += 15
            feedback.append("Apex Title style is defined correctly.")
        else:
            feedback.append(f"Apex Title style incomplete: {title_props}.")
    else:
        feedback.append("Apex Title style not found.")

    body_style = _find_style(styles_root, body_style_name)
    if body_style is not None:
        body_props = _style_text_props(body_style)
        font_ok = any(name in body_props["font_name"] for name in ("Liberation Serif", "Times New Roman"))
        size_ok = body_props["font_size"].startswith("11")
        color_ok = body_props["color"].lower() in {"#000000", "black"}
        if font_ok and size_ok and color_ok:
            score += 15
            feedback.append("Apex Body style is defined correctly.")
        else:
            feedback.append(f"Apex Body style incomplete: {body_props}.")
    else:
        feedback.append("Apex Body style not found.")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " ".join(feedback)}
