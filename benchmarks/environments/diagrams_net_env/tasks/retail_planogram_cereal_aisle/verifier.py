#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import base64
import zlib
import urllib.parse
from xml.etree import ElementTree as ET

def verify_retail_planogram_cereal_aisle(traj, env_info, task_info):
    """
    Verifies the Retail Planogram task.
    
    Criteria:
    1. Output PDF exists (10 pts)
    2. Diagram modified (10 pts)
    3. Facings Count: Are there enough boxes? (15 pts)
    4. Eye Level Strategy: High Margin items (FiberCrunch, HeartyOats) at Y range (20-40% from top) (20 pts)
    5. Kids Level Strategy: Kids items (ChocoBlast, SugarDust) at Y range (60-90% from top) (20 pts)
    6. Sale Tag: "SALE" star shape exists (10 pts)
    7. Scale/Dimensions: Boxes have correct aspect ratio (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Basic Checks
    if res_data.get("pdf_exists"):
        score += 10
        feedback.append("PDF export found (+10).")
    else:
        feedback.append("PDF export MISSING.")
        
    if res_data.get("diagram_modified"):
        score += 10
        feedback.append("Diagram file modified (+10).")
    else:
        feedback.append("Diagram file NOT modified.")

    # 2. Retrieve and Parse Diagram XML
    diagram_content = ""
    temp_diagram = tempfile.NamedTemporaryFile(delete=False, suffix=".drawio")
    try:
        copy_from_env(res_data["diagram_path"], temp_diagram.name)
        
        # Parse XML
        tree = ET.parse(temp_diagram.name)
        root = tree.getroot()
        
        # Handle Draw.io Compressed format
        # Usually inside <diagram> tag as text
        diagram_node = root.find("diagram")
        if diagram_node is not None and diagram_node.text:
            try:
                # Decode: Base64 -> Inflate (raw) -> URLDecode (sometimes)
                # Standard draw.io encoding flow: Deflate -> Base64
                txt = diagram_node.text.strip()
                data = base64.b64decode(txt)
                xml_str = zlib.decompress(data, -15).decode('utf-8')
                xml_str = urllib.parse.unquote(xml_str) # Just in case
                root = ET.fromstring(xml_str)
            except Exception as e:
                feedback.append(f"Note: Could not decompress diagram (might be uncompressed): {e}")
                # Fallback: maybe it's already uncompressed XML inside?
                pass
                
        # Find all cells (shapes)
        # We look for 'mxCell'
        cells = root.findall(".//mxCell")
        
        shapes = []
        labels = []
        
        for cell in cells:
            val = cell.get("value", "")
            style = cell.get("style", "")
            vertex = cell.get("vertex")
            
            if vertex == "1":
                geo = cell.find("mxGeometry")
                if geo is not None:
                    try:
                        x = float(geo.get("x", 0))
                        y = float(geo.get("y", 0))
                        w = float(geo.get("width", 0))
                        h = float(geo.get("height", 0))
                        shapes.append({
                            "label": val,
                            "x": x,
                            "y": y,
                            "w": w,
                            "h": h,
                            "style": style
                        })
                        if val:
                            labels.append(val.lower())
                    except:
                        pass

        # ANALYSIS LOGIC
        
        # 3. Facings Count (Total Shapes)
        # Template has ~5 background shapes. We expect ~11 product shapes (2+3+3+2+1).
        product_shapes = [s for s in shapes if s['w'] > 0 and s['h'] > 0 and "locked" not in s.get("style", "")]
        
        # Filter out the template background shapes (width 480 is the fixture)
        user_shapes = [s for s in product_shapes if s['w'] < 400] 
        
        if len(user_shapes) >= 11:
            score += 15
            feedback.append(f"Sufficient product facings found ({len(user_shapes)}) (+15).")
        elif len(user_shapes) >= 5:
            score += 7
            feedback.append(f"Partial product facings found ({len(user_shapes)}) (+7).")
        else:
            feedback.append(f"Too few product shapes found ({len(user_shapes)}).")

        # 4. Strategy Verification
        # Coordinate System: 0 is top.
        # Template: Y=40 (Top) to Y=760 (Bottom). Height 720.
        # "Eye Level" (High Margin): Shelf 3 is at Y=380 (approx). 
        #   Real world: 60" from bottom = 12" from top = 120px. 
        #   Let's just check relative position.
        #   "Adult"/High Margin (FiberCrunch, HeartyOats) should be HIGHER (lower Y) than Kids.
        #   "Kids" (ChocoBlast, SugarDust) should be LOWER (higher Y).
        
        y_adult = []
        y_kids = []
        
        for s in user_shapes:
            lbl = s['label'].lower()
            if "fiber" in lbl or "hearty" in lbl:
                y_adult.append(s['y'])
            if "choco" in lbl or "sugar" in lbl or "blast" in lbl:
                y_kids.append(s['y'])
                
        # Logic: Average Y of Kids should be significantly greater than Average Y of Adult
        valid_strategy = False
        if y_adult and y_kids:
            avg_adult = sum(y_adult)/len(y_adult)
            avg_kids = sum(y_kids)/len(y_kids)
            
            # Eye level is visually higher (smaller Y) than bottom shelf (larger Y)
            if avg_kids > avg_adult + 100: # at least 100px lower
                valid_strategy = True
                
        if valid_strategy:
            score += 40 # Combined Eye Level + Kids strategy
            feedback.append("Strategy Validated: Kids cereals placed lower than Adult cereals (+40).")
        else:
            # Check individual partials
            # Eye Level check (approx Y 200-400)
            adult_ok = any(200 < y < 450 for y in y_adult)
            if adult_ok:
                score += 20
                feedback.append("Adult cereals at eye level (+20).")
            else:
                feedback.append("Adult cereals not at eye level.")
                
            # Kids Level check (approx Y > 500)
            kids_ok = any(y > 500 for y in y_kids)
            if kids_ok:
                score += 20
                feedback.append("Kids cereals at bottom (+20).")
            else:
                feedback.append("Kids cereals not at bottom.")

        # 5. Sale Tag
        has_star = any("star" in s['style'] or "actor=star" in s['style'] or "SALE" in s['label'] for s in user_shapes)
        if has_star:
            score += 10
            feedback.append("Sale tag found (+10).")
        else:
            feedback.append("Sale tag missing.")

        # 6. Scale/Dimensions
        # Check aspect ratio of a known product. FiberCrunch 8x12 (Ratio 0.66)
        # User shapes w < h
        ratios_correct = 0
        for s in user_shapes:
            if s['h'] > 0:
                ratio = s['w'] / s['h']
                if 0.4 < ratio < 1.0: # Tall box
                    ratios_correct += 1
        
        if ratios_correct >= 5:
            score += 15
            feedback.append("Product shapes have correct aspect ratio (+15).")
        
    except Exception as e:
        feedback.append(f"Error parsing diagram: {e}")

    # Final logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }