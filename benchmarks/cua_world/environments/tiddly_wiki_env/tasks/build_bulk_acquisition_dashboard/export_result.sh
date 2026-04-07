#!/bin/bash
echo "=== Exporting build_bulk_acquisition_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Use Python to accurately parse all tiddler files and construct a single JSON result.
# This avoids tricky bash/grep parsing for space-separated tags and multiline fields.
python3 - << 'EOF'
import os
import json
import re

TIDDLERS_DIR = "/home/ga/mywiki/tiddlers"
LOG_FILE = "/home/ga/tiddlywiki.log"

books = [
    "1984", "To Kill a Mockingbird", "The Great Gatsby", "Pride and Prejudice", "The Catcher in the Rye",
    "The Lord of the Rings", "The Hobbit", "Fahrenheit 451", "Jane Eyre", "Animal Farm",
    "The Grapes of Wrath", "Catch-22", "Brave New World", "The Odyssey", "The Iliad",
    "Crime and Punishment", "The Brothers Karamazov", "War and Peace", "Anna Karenina", "Madame Bovary",
    "Les Miserables", "The Count of Monte Cristo", "Don Quixote", "Moby-Dick", "Frankenstein",
    "Dracula", "The Picture of Dorian Gray", "Wuthering Heights", "Great Expectations", "A Tale of Two Cities"
]

dashboard_exists = False
dashboard_text = ""
books_state = []

# Scan all .tid files
if os.path.exists(TIDDLERS_DIR):
    for filename in os.listdir(TIDDLERS_DIR):
        if not filename.endswith('.tid') or filename.startswith('$__'):
            continue
            
        filepath = os.path.join(TIDDLERS_DIR, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Check if this is the dashboard
            if "title: Acquisitions Dashboard\n" in content:
                dashboard_exists = True
                parts = content.split('\n\n', 1)
                if len(parts) > 1:
                    dashboard_text = parts[1]
                    
            # Check if this is one of our target books
            for book in books:
                if f"title: {book}\n" in content:
                    # Extract tags
                    tags_match = re.search(r'^tags:\s*(.+)$', content, re.MULTILINE)
                    tags = tags_match.group(1) if tags_match else ""
                    
                    # Extract catalog-status
                    status_match = re.search(r'^catalog-status:\s*(.+)$', content, re.MULTILINE)
                    status = status_match.group(1) if status_match else ""
                    
                    books_state.append({
                        "title": book,
                        "tags": tags,
                        "status": status.strip()
                    })
                    break
        except Exception as e:
            pass

# Count books meeting the final criteria
correct_tags = 0
correct_fields = 0

for b in books_state:
    has_main = "MainCollection" in b["tags"]
    no_queue = "AcquisitionQueue" not in b["tags"]
    
    if has_main and no_queue:
        correct_tags += 1
        
    if b["status"] == "Complete":
        correct_fields += 1

# Check server logs for GUI interaction to prevent bash script gaming
dashboard_saved_via_gui = False
batch_saves_detected = 0

if os.path.exists(LOG_FILE):
    try:
        with open(LOG_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                if "Dispatching 'save' task" in line:
                    if "Acquisitions Dashboard" in line:
                        dashboard_saved_via_gui = True
                    for book in books:
                        if book in line:
                            batch_saves_detected += 1
    except:
        pass

result = {
    "dashboard_exists": dashboard_exists,
    "dashboard_text": dashboard_text,
    "books_found": len(books_state),
    "books_with_correct_tags": correct_tags,
    "books_with_correct_status": correct_fields,
    "dashboard_saved_via_gui": dashboard_saved_via_gui,
    "batch_saves_detected": batch_saves_detected
}

with open('/tmp/dashboard_result.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

chmod 666 /tmp/dashboard_result.json
echo "Result exported to /tmp/dashboard_result.json:"
cat /tmp/dashboard_result.json

echo "=== Export complete ==="