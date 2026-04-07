#!/bin/bash
# Export script for configure_library_site task
echo "=== Exporting library site configuration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract all relevant data using Python and WP-CLI into a structured JSON
echo "Gathering site state..."
python3 << 'EOF'
import subprocess
import json
import os
import time

def run_wp(cmd):
    try:
        output = subprocess.check_output(f"wp {cmd} --allow-root", shell=True, cwd="/var/www/html/wordpress", stderr=subprocess.STDOUT)
        return output.decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        return ""

result = {
    "timestamp": time.time()
}

# 1. Get Pages
try:
    pages_json = run_wp("post list --post_type=page --post_status=publish --fields=ID,post_title,post_content,post_date --format=json")
    result['pages'] = json.loads(pages_json) if pages_json else []
except:
    result['pages'] = []

# 2. Get Reading Settings
result['show_on_front'] = run_wp("option get show_on_front")
result['page_on_front'] = run_wp("option get page_on_front")
result['page_for_posts'] = run_wp("option get page_for_posts")

# 3. Get Menus
try:
    menus_json = run_wp("menu list --fields=term_id,name,count --format=json")
    result['menus'] = json.loads(menus_json) if menus_json else []
    
    # Get items for each menu
    for menu in result['menus']:
        menu_id = menu.get('term_id')
        if menu_id:
            items_json = run_wp(f"menu item list {menu_id} --fields=db_id,title,object_id,object --format=json")
            menu['items'] = json.loads(items_json) if items_json else []
except:
    result['menus'] = []

# 4. Get Menu Locations (Theme Mods)
try:
    theme_mods_json = run_wp("option get theme_mods_twentytwentyone --format=json")
    if theme_mods_json:
        theme_mods = json.loads(theme_mods_json)
        result['nav_menu_locations'] = theme_mods.get('nav_menu_locations', {})
    else:
        result['nav_menu_locations'] = {}
except:
    result['nav_menu_locations'] = {}

# Save to file safely
import tempfile
import shutil

fd, temp_path = tempfile.mkstemp(suffix='.json')
with os.fdopen(fd, 'w') as f:
    json.dump(result, f)

dest = '/tmp/task_result.json'
try:
    if os.path.exists(dest):
        os.remove(dest)
    shutil.copy(temp_path, dest)
    os.chmod(dest, 0o666)
except Exception as e:
    subprocess.run(["sudo", "cp", temp_path, dest])
    subprocess.run(["sudo", "chmod", "666", dest])
finally:
    os.remove(temp_path)

EOF

echo "Result JSON generated:"
cat /tmp/task_result.json | head -n 30
echo "...(truncated)"
echo "=== Export complete ==="