#!/bin/bash
# export_result.sh - Post-task hook for import_bookmarks task
# Exports verification data for bookmark import task

echo "=== Exporting import_bookmarks task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Get bookmarks file location
BOOKMARKS_FILE="/home/ga/.config/microsoft-edge/Default/Bookmarks"
echo "Checking bookmarks file: $BOOKMARKS_FILE"

# Initialize variables
BOOKMARKS_FILE_EXISTS="false"
CURRENT_BOOKMARK_COUNT=0
FOLDER_COUNT=0
IMPORTED_BOOKMARKS="[]"
IMPORTED_FOLDERS="[]"
SAMPLE_FOUND="false"
INITIAL_COUNT=$(cat /tmp/initial_bookmark_count 2>/dev/null || echo "0")
EXPECTED_COUNT=$(cat /tmp/expected_bookmark_count 2>/dev/null || echo "0")

if [ -f "$BOOKMARKS_FILE" ]; then
    BOOKMARKS_FILE_EXISTS="true"
    echo "Bookmarks file found"

    # Parse bookmarks using Python
    BOOKMARK_DATA=$(python3 << 'PYEOF'
import json
import sys
import os

# Path to task.json for reading configuration
task_json_path = '/workspace/tasks/import_bookmarks/task.json'

try:
    with open("/home/ga/.config/microsoft-edge/Default/Bookmarks", 'r') as f:
        data = json.load(f)

    def extract_all(node, path=''):
        bookmarks = []
        folders = []

        if node.get('type') == 'url':
            bookmarks.append({
                'name': node.get('name', ''),
                'url': node.get('url', ''),
                'folder': path
            })
        elif node.get('type') == 'folder':
            folder_name = node.get('name', '')
            new_path = path + '/' + folder_name if path else folder_name

            # Don't count root folders (Favorites bar, Other favorites, Mobile favorites)
            if path:  # Only count non-root folders
                folders.append(folder_name)

            for child in node.get('children', []):
                child_bookmarks, child_folders = extract_all(child, new_path)
                bookmarks.extend(child_bookmarks)
                folders.extend(child_folders)

        return bookmarks, folders

    all_bookmarks = []
    all_folders = []

    for root_name, root_node in data.get('roots', {}).items():
        if isinstance(root_node, dict):
            bookmarks, folders = extract_all(root_node, root_name)
            all_bookmarks.extend(bookmarks)
            all_folders.extend(folders)

    # Check for sample bookmarks (case-insensitive matching)
    # Read from task.json if available, otherwise use defaults
    sample_names = ['BBC News', 'Stack Overflow', 'Wikipedia', 'Amazon', 'Netflix']
    if os.path.exists(task_json_path):
        try:
            with open(task_json_path, 'r') as tf:
                task_data = json.load(tf)
                sample_names = task_data.get('metadata', {}).get('sample_bookmarks', sample_names)
        except:
            pass  # Use defaults if reading fails
    sample_names_lower = [s.lower() for s in sample_names]
    found_samples = []
    found_samples_with_folders = []

    import re
    def matches_sample(bookmark_name, sample_name):
        """Check if bookmark name matches sample name using word boundaries.

        Matches if:
        - Exact match (case-insensitive)
        - Sample name appears as complete word(s) at start of bookmark name
        - Bookmark name equals the sample name with common suffixes

        Does NOT match:
        - Sample name embedded in middle of unrelated text (e.g., "MyWikipediaClone")
        - Partial matches without word boundaries
        """
        bm_lower = bookmark_name.lower().strip()
        sample_lower = sample_name.lower().strip()

        # Exact match
        if bm_lower == sample_lower:
            return True

        # Sample name at start with word boundary (e.g., "BBC News" matches "BBC News International")
        # Use word boundary regex: sample must be followed by end of string, space, or punctuation
        pattern = r'^' + re.escape(sample_lower) + r'(?:\s|$|[,.\-_!?])'
        if re.match(pattern, bm_lower):
            return True

        # Bookmark name at start of sample (e.g., "Wikipedia" matches if sample is "Wikipedia, the free encyclopedia")
        pattern = r'^' + re.escape(bm_lower) + r'(?:\s|$|[,.\-_!?])'
        if re.match(pattern, sample_lower):
            return True

        return False

    for bm in all_bookmarks:
        for i, sample_name in enumerate(sample_names):
            if matches_sample(bm['name'], sample_name):
                found_samples.append(sample_names[i])
                found_samples_with_folders.append({
                    'name': bm['name'],
                    'folder': bm['folder'],
                    'url': bm['url']
                })
                break

    # Expected folders from import - read from task.json if available, otherwise use defaults
    expected_folders = ['News & Media', 'Technology', 'Reference', 'Shopping', 'Social', 'Productivity', 'Entertainment', 'Finance', 'Education']
    if os.path.exists(task_json_path):
        try:
            with open(task_json_path, 'r') as tf:
                task_data = json.load(tf)
                expected_folders = task_data.get('metadata', {}).get('expected_folders', expected_folders)
        except:
            pass  # Use defaults if reading fails
    found_expected_folders = [f for f in all_folders if f in expected_folders]

    # Count bookmarks per folder to verify folder content
    folder_bookmark_counts = {}
    for bm in all_bookmarks:
        folder = bm['folder']
        folder_bookmark_counts[folder] = folder_bookmark_counts.get(folder, 0) + 1

    result = {
        'bookmark_count': len(all_bookmarks),
        'folder_count': len(set(all_folders)),
        'bookmarks': all_bookmarks[:20],  # First 20 for brevity
        'folders': list(set(all_folders)),
        'found_samples': list(set(found_samples)),  # Deduplicate
        'found_samples_with_folders': found_samples_with_folders,
        'found_expected_folders': found_expected_folders,
        'folder_bookmark_counts': folder_bookmark_counts,
        'sample_check_passed': len(set(found_samples)) >= 4  # Require 4 of 5 samples
    }

    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        'bookmark_count': 0,
        'folder_count': 0,
        'bookmarks': [],
        'folders': [],
        'found_samples': [],
        'found_expected_folders': [],
        'sample_check_passed': False,
        'error': str(e)
    }))
PYEOF
)

    # Extract values from Python output
    CURRENT_BOOKMARK_COUNT=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bookmark_count', 0))")
    FOLDER_COUNT=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('folder_count', 0))")
    IMPORTED_BOOKMARKS=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('bookmarks', [])))")
    IMPORTED_FOLDERS=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('folders', [])))")
    FOUND_SAMPLES=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('found_samples', [])))")
    FOUND_SAMPLES_WITH_FOLDERS=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('found_samples_with_folders', [])))")
    FOUND_EXPECTED_FOLDERS=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('found_expected_folders', [])))")
    FOLDER_BOOKMARK_COUNTS=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('folder_bookmark_counts', {})))")
    SAMPLE_FOUND=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; print('true' if json.load(sys.stdin).get('sample_check_passed', False) else 'false')")

    echo "Current bookmark count: $CURRENT_BOOKMARK_COUNT"
    echo "Folder count: $FOLDER_COUNT"
    echo "Sample bookmarks found: $FOUND_SAMPLES"
else
    echo "Bookmarks file NOT found"
fi

# Calculate new bookmarks
NEW_BOOKMARKS=$((CURRENT_BOOKMARK_COUNT - INITIAL_COUNT))
if [ $NEW_BOOKMARKS -lt 0 ]; then
    NEW_BOOKMARKS=0
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_bookmark_count": $INITIAL_COUNT,
    "expected_bookmark_count": $EXPECTED_COUNT,
    "current_bookmark_count": $CURRENT_BOOKMARK_COUNT,
    "new_bookmarks_imported": $NEW_BOOKMARKS,
    "folder_count": $FOLDER_COUNT,
    "bookmarks_file_exists": $BOOKMARKS_FILE_EXISTS,
    "sample_bookmarks_found": $SAMPLE_FOUND,
    "found_samples": $FOUND_SAMPLES,
    "found_samples_with_folders": $FOUND_SAMPLES_WITH_FOLDERS,
    "found_expected_folders": $FOUND_EXPECTED_FOLDERS,
    "folder_bookmark_counts": $FOLDER_BOOKMARK_COUNTS,
    "imported_folders": $IMPORTED_FOLDERS,
    "imported_bookmarks": $IMPORTED_BOOKMARKS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Copy to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Result exported to /tmp/task_result.json ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
