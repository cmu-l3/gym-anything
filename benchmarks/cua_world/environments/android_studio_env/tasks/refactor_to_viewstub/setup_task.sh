#!/bin/bash
set -e
echo "=== Setting up refactor_to_viewstub task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Paths
PROJECT_NAME="DashboardApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
# We assume a base project template exists or we create a minimal one. 
# For this task generator, we'll assume we can copy a base project and inject our specific files.
# If data/DashboardApp doesn't exist, we'll use a generic fallback if available or fail.
DATA_SOURCE="/workspace/data/$PROJECT_NAME"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json

# setup_android_studio_project handles the copying if we point it to data, 
# but here we might need to construct the specific "heavy" state if it's not pre-baked.
# To be safe/standalone, we will copy a base project and overwrite the specific files 
# to ensure the "Starting State" is exactly as described.

# 1. Copy base project (assuming a BasicApp or creating directory structure)
if [ -d "$DATA_SOURCE" ]; then
    echo "Copying existing DashboardApp data..."
    cp -r "$DATA_SOURCE" "/home/ga/AndroidStudioProjects/"
else
    # Fallback: Create a basic project structure if specific data missing
    # This is a fail-safe to make the task runnable in generic environments
    echo "Creating DashboardApp structure..."
    mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/dashboardapp"
    mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
    mkdir -p "$PROJECT_DIR/app/src/main/res/values"
    
    # Copy gradle files from a template if available, or write minimal ones
    # (Omitting full gradle wrapper generation for brevity, assuming environment supports basic project copy)
    # Ideally, we copy a "BlankApp" from data and rename it.
    if [ -d "/workspace/data/BlankApp" ]; then
        cp -r "/workspace/data/BlankApp" "$PROJECT_DIR"
    fi
fi

# 2. Inject the "Heavy" Layout (activity_stats.xml)
# It mimics a complex dashboard with nested views and visibility=gone
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_stats.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Dashboard Overview"
        android:textSize="24sp"
        android:textStyle="bold" />

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:text="Summary: All systems operational." />

    <Button
        android:id="@+id/btn_toggle_details"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:text="Show Details" />

    <!-- HEAVY LAYOUT SECTION START -->
    <!-- This is the section to be refactored into a ViewStub -->
    <LinearLayout
        android:id="@+id/details_panel"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginTop="16dp"
        android:visibility="gone"
        android:background="#F0F0F0"
        android:padding="16dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Detailed Statistics"
            android:textSize="18sp"
            android:textStyle="bold" />

        <!-- Mocking heavy content: Charts/Graphs -->
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Daily Active Users" />
        <ProgressBar
            style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:progress="75" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Retention Rate" />
        <ProgressBar
            style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:progress="45" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Session Length" />
        <ProgressBar
            style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:progress="60" />
            
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="8dp"
            android:text="Conversion Funnel" />
            
        <!-- Simulate nesting depth -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="100dp"
            android:orientation="horizontal">
            <View android:layout_width="0dp" android:layout_weight="1" android:layout_height="match_parent" android:background="#AA0000" />
            <View android:layout_width="0dp" android:layout_weight="1" android:layout_height="match_parent" android:background="#00AA00" />
            <View android:layout_width="0dp" android:layout_weight="1" android:layout_height="match_parent" android:background="#0000AA" />
        </LinearLayout>

    </LinearLayout>
    <!-- HEAVY LAYOUT SECTION END -->

</LinearLayout>
EOF

# 3. Inject the Activity Code (StatsActivity.kt)
cat > "$PROJECT_DIR/app/src/main/java/com/example/dashboardapp/StatsActivity.kt" << 'EOF'
package com.example.dashboardapp

import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity

class StatsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_stats)

        val btnToggle = findViewById<Button>(R.id.btn_toggle_details)
        val detailsPanel = findViewById<LinearLayout>(R.id.details_panel)

        btnToggle.setOnClickListener {
            if (detailsPanel.visibility == View.VISIBLE) {
                detailsPanel.visibility = View.GONE
                btnToggle.text = "Show Details"
            } else {
                detailsPanel.visibility = View.VISIBLE
                btnToggle.text = "Hide Details"
            }
        }
    }
}
EOF

# 4. Ensure Manifest registers the activity
# (Assuming the base project handles the rest, we just ensure StatsActivity is declared)
if grep -q "StatsActivity" "$PROJECT_DIR/app/src/main/AndroidManifest.xml"; then
    echo "StatsActivity already in manifest."
else
    # Simple sed injection if needed, or overwrite manifest. 
    # For safety, we'll overwrite with a basic manifest.
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.dashboardapp">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="DashboardApp"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar">
        <activity
            android:name=".StatsActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# 5. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "DashboardApp" 180

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Task setup complete ==="