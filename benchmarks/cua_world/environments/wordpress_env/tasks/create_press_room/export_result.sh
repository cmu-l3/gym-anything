#!/bin/bash
# Export script for create_press_room task (post_task hook)

echo "=== Exporting create_press_room result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query MariaDB and export clean JSON
python3 << 'EOF'
import pymysql
import json
import os

result = {
    "category": {"exists": False, "term_id": None},
    "posts": {
        "p1": {"exists": False, "published": False, "in_category": False, "content": ""},
        "p2": {"exists": False, "published": False, "in_category": False, "content": ""},
        "p3": {"exists": False, "published": False, "in_category": False, "content": ""}
    },
    "pages": {
        "press_room": {"exists": False, "published": False, "parent": None, "content": "", "id": None},
        "media_contact": {"exists": False, "published": False, "parent": None, "content": "", "id": None}
    },
    "error": None
}

try:
    conn = pymysql.connect(host='127.0.0.1', user='wordpress', password='wordpresspass', database='wordpress')
    with conn.cursor(pymysql.cursors.DictCursor) as cursor:
        # 1. Check Category
        cursor.execute("SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id=tt.term_id WHERE tt.taxonomy='category' AND LOWER(t.name)='press releases'")
        cat = cursor.fetchone()
        if cat:
            result['category']['exists'] = True
            result['category']['term_id'] = cat['term_id']

        # 2. Check Posts
        post_titles = {
            "p1": "Nimbus Technologies Raises $42 Million in Series B Funding",
            "p2": "Nimbus Technologies Launches CloudSync 2.0 Platform",
            "p3": "Nimbus Technologies Named to Forbes Cloud 100 List"
        }
        
        for key, title in post_titles.items():
            cursor.execute("SELECT ID, post_status, post_content FROM wp_posts WHERE post_type='post' AND post_title=%s ORDER BY ID DESC LIMIT 1", (title,))
            post = cursor.fetchone()
            if post:
                result['posts'][key]['exists'] = True
                result['posts'][key]['published'] = (post['post_status'] == 'publish')
                result['posts'][key]['content'] = post['post_content']
                
                # Check category assignment
                if cat:
                    cursor.execute("SELECT object_id FROM wp_term_relationships WHERE object_id=%s AND term_taxonomy_id=%s", (post['ID'], cat['term_id']))
                    if cursor.fetchone():
                        result['posts'][key]['in_category'] = True

        # 3. Check Pages
        cursor.execute("SELECT ID, post_status, post_parent, post_content FROM wp_posts WHERE post_type='page' AND LOWER(post_title)='press room' ORDER BY ID DESC LIMIT 1")
        pr = cursor.fetchone()
        if pr:
            result['pages']['press_room']['exists'] = True
            result['pages']['press_room']['published'] = (pr['post_status'] == 'publish')
            result['pages']['press_room']['parent'] = pr['post_parent']
            result['pages']['press_room']['content'] = pr['post_content']
            result['pages']['press_room']['id'] = pr['ID']

        cursor.execute("SELECT ID, post_status, post_parent, post_content FROM wp_posts WHERE post_type='page' AND LOWER(post_title)='media contact' ORDER BY ID DESC LIMIT 1")
        mc = cursor.fetchone()
        if mc:
            result['pages']['media_contact']['exists'] = True
            result['pages']['media_contact']['published'] = (mc['post_status'] == 'publish')
            result['pages']['media_contact']['parent'] = mc['post_parent']
            result['pages']['media_contact']['content'] = mc['post_content']
            result['pages']['media_contact']['id'] = mc['ID']

except Exception as e:
    result['error'] = str(e)

with open('/tmp/create_press_room_result.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

# Fix permissions
chmod 666 /tmp/create_press_room_result.json 2>/dev/null || sudo chmod 666 /tmp/create_press_room_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/create_press_room_result.json
echo "=== Export complete ==="