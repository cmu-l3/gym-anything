#!/bin/bash
# Export script for travel_itinerary_layout task

echo "=== Exporting Travel Itinerary Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Paths
OUTPUT_FILE="/home/ga/Documents/Italy_Proposal_2025.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Python Analysis Script
# This script extracts the ODT and analyzes XML for orientation, columns, and content.
python3 << 'PYEOF'
import zipfile
import json
import os
import re

output_file = "/home/ga/Documents/Italy_Proposal_2025.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "is_landscape": False,
    "has_columns": False,
    "image_count": 0,
    "has_logo": False,
    "content_found": [],
    "heading_count": 0,
    "timestamp_valid": False
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check timestamp (anti-gaming)
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = int(f.read().strip())
        file_mtime = int(os.path.getmtime(output_file))
        if file_mtime > start_time:
            result["timestamp_valid"] = True
    except:
        pass

    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # Read styles.xml for page layout (Orientation)
            styles_xml = z.read('styles.xml').decode('utf-8', errors='ignore')
            
            # Read content.xml for content, columns, and images
            content_xml = z.read('content.xml').decode('utf-8', errors='ignore')
            
            # --- CHECK ORIENTATION ---
            # Look for print-orientation="landscape" OR page dimensions where width > height
            # A4 Landscape: width="29.7cm" height="21cm"
            # US Letter Landscape: width="11in" height="8.5in"
            
            is_landscape = False
            if 'style:print-orientation="landscape"' in styles_xml:
                is_landscape = True
            else:
                # Regex to find page-layout-properties
                # This is heuristic; looking for any page master used that is landscape
                layout_matches = re.findall(r'<style:page-layout-properties[^>]*fo:page-width="([^"]+)"[^>]*fo:page-height="([^"]+)"', styles_xml)
                for width_str, height_str in layout_matches:
                    # Convert to float (rough)
                    def parse_dim(s):
                        val = float(re.findall(r"[\d\.]+", s)[0])
                        return val
                    
                    try:
                        w = parse_dim(width_str)
                        h = parse_dim(height_str)
                        if w > h:
                            is_landscape = True
                    except:
                        pass
            
            result["is_landscape"] = is_landscape

            # --- CHECK COLUMNS ---
            # Columns are usually defined in a section style or page style
            # Look for style:columns element with fo:column-count >= 2
            # This can be in content.xml (automatic styles) or styles.xml
            
            has_columns = False
            
            # Check for column definitions
            col_matches = re.findall(r'<style:columns[^>]*fo:column-count="(\d+)"', content_xml)
            col_matches += re.findall(r'<style:columns[^>]*fo:column-count="(\d+)"', styles_xml)
            
            for count in col_matches:
                if int(count) >= 2:
                    has_columns = True
                    break
            
            result["has_columns"] = has_columns

            # --- CHECK IMAGES ---
            # Count <draw:image> tags
            # Note: The logo might be one image. The specific landmarks are others.
            # We look for unique image binaries referenced or just count tags.
            # In ODT, images are referenced in manifest or stored in Pictures/
            
            # Let's count draw:image elements in content.xml
            image_tags = re.findall(r'<draw:image', content_xml)
            result["image_count"] = len(image_tags)
            
            # Heuristic for logo: check if "logo" is in the href (if linked) or just count total
            # Since user provided "logo.png", we hope the filename or similar preserved, 
            # but ODT often renames internal images. We will rely on count >= 4 (3 landmarks + 1 logo).
            
            # --- CHECK CONTENT ---
            text_content = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            keywords = [
                "italian renaissance", 
                "sterling", 
                "colosseum", 
                "hotel de russie", 
                "ferrari", 
                "venice"
            ]
            
            found_words = []
            for kw in keywords:
                if kw in text_content:
                    found_words.append(kw)
            result["content_found"] = found_words

            # Check headings
            # Look for text:h with outline-level
            headings = re.findall(r'<text:h[^>]*text:outline-level', content_xml)
            result["heading_count"] = len(headings)

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

# 4. Save permission
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="