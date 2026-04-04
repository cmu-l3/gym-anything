#!/bin/bash
# set -euo pipefail

echo "=== Exporting API Caching Workflow Result ==="

WORKSPACE_DIR="/home/ga/workspace/weather_app"

# Give extensions time to finish installing
sleep 3

# Export extensions list
echo "Exporting extensions list..."
ls -la /home/ga/.vscode/extensions/ > /tmp/extensions_list.txt 2>&1 || echo "No extensions directory" > /tmp/extensions_list.txt
su - ga -c "DISPLAY=:1 code --list-extensions > /tmp/extensions_ids.txt 2>&1" || echo "" > /tmp/extensions_ids.txt

# Export workspace directory tree structure
echo "Exporting workspace structure..."
if [ -d "$WORKSPACE_DIR" ]; then
    tree -a -L 3 "$WORKSPACE_DIR" > /tmp/workspace_tree.txt 2>&1 || ls -laR "$WORKSPACE_DIR" > /tmp/workspace_tree.txt 2>&1
    
    # Find and list all JSON files in potential cache directories
    find "$WORKSPACE_DIR" -type f -name "*.json" > /tmp/json_files_list.txt 2>&1 || echo "" > /tmp/json_files_list.txt
    
    # Find and list request files (.http, .rest, etc.)
    find "$WORKSPACE_DIR" -type f \( -name "*.http" -o -name "*.rest" \) > /tmp/request_files_list.txt 2>&1 || echo "" > /tmp/request_files_list.txt
    
    # Check for .env file
    if [ -f "$WORKSPACE_DIR/.env" ]; then
        cp "$WORKSPACE_DIR/.env" /tmp/env_file_export.txt 2>&1
    else
        echo "No .env file" > /tmp/env_file_export.txt
    fi
    
    # Check for documentation files
    find "$WORKSPACE_DIR" -type f \( -name "*README*" -o -name "*readme*" \) > /tmp/readme_files_list.txt 2>&1 || echo "" > /tmp/readme_files_list.txt
    
    # Export potential cache directories
    for cache_dir in "responses" "mocks" "cache" "api_cache"; do
        if [ -d "$WORKSPACE_DIR/$cache_dir" ]; then
            echo "Found cache directory: $cache_dir" >> /tmp/cache_dirs_found.txt
            ls -la "$WORKSPACE_DIR/$cache_dir" >> /tmp/cache_dirs_content.txt 2>&1
        fi
    done
    
    if [ ! -f /tmp/cache_dirs_found.txt ]; then
        echo "No cache directories found" > /tmp/cache_dirs_found.txt
        echo "" > /tmp/cache_dirs_content.txt
    fi
else
    echo "Workspace directory not found" > /tmp/workspace_tree.txt
    echo "" > /tmp/json_files_list.txt
    echo "" > /tmp/request_files_list.txt
    echo "" > /tmp/env_file_export.txt
    echo "" > /tmp/readme_files_list.txt
    echo "No workspace" > /tmp/cache_dirs_found.txt
    echo "" > /tmp/cache_dirs_content.txt
fi

echo "✅ Export complete"
echo "Extensions: /tmp/extensions_ids.txt"
echo "Workspace: /tmp/workspace_tree.txt"
echo "JSON files: /tmp/json_files_list.txt"
echo "Request files: /tmp/request_files_list.txt"
echo "Environment: /tmp/env_file_export.txt"
echo "Documentation: /tmp/readme_files_list.txt"
echo "Cache dirs: /tmp/cache_dirs_found.txt"