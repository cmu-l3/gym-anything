#!/bin/bash
echo "=== Setting up create_state_list_drawable task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="LoginUI"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
DATA_SOURCE="/workspace/data/$PROJECT_NAME"

# Clean up previous artifacts
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start.png 2>/dev/null || true

# Prepare the project
echo "Setting up project files..."
mkdir -p /home/ga/AndroidStudioProjects

if [ -d "$DATA_SOURCE" ]; then
    cp -r "$DATA_SOURCE" "$PROJECT_DIR"
else
    # Fallback if data source missing: Create a basic project structure
    # This ensures the task is runnable even if the specific data volume is missing in test envs
    echo "WARNING: Data source not found, creating base project..."
    mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
    mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
    
    # Create minimal layout
    cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="16dp">

    <Button
        android:id="@+id/login_button"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Login" />

</LinearLayout>
EOF
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;

# Record initial state of layout for verification comparison
if [ -f "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" ]; then
    md5sum "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" > /tmp/initial_layout_hash.txt
fi

# Launch Android Studio
echo "Opening project in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "$PROJECT_NAME" 120

# Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="