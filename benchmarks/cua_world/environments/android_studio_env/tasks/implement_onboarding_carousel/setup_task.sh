#!/bin/bash
set -e
echo "=== Setting up task: implement_onboarding_carousel ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define project paths
PROJECT_NAME="TravelBuddy"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
TEMPLATE_DIR="/workspace/data/templates/EmptyActivityKotlin" # Assuming a cached template exists

# 1. Clean up previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png
rm -f /tmp/gradle_output.log

# 2. Create Base Project
echo "Creating project structure..."
mkdir -p "$PROJECT_DIR"

# If we have a local template cache, use it. Otherwise, create minimal structure.
# For this environment, we'll assume we need to generate a minimal valid project structure
# if the full template isn't available, but standard practice uses a pre-zipped template.
if [ -d "$TEMPLATE_DIR" ]; then
    cp -r "$TEMPLATE_DIR/." "$PROJECT_DIR/"
else
    # Fallback: Create minimal structure manually (simplified for this script)
    # In a real scenario, we'd wget a zip from a local server or use `android create project`
    # Here we assume a valid base project zip is available at /workspace/data/base_project.zip
    # or we simulate it.
    
    # NOTE: In the android_studio_env, we usually have a base project generator.
    # We will simulate copying a base project for reliability.
    if [ -f "/workspace/data/base_project.zip" ]; then
        unzip -q /workspace/data/base_project.zip -d /home/ga/AndroidStudioProjects/
        mv /home/ga/AndroidStudioProjects/BaseProject "$PROJECT_DIR"
    else
        # Critical fallback: If no data, we cannot proceed effectively without a base.
        # We will assume the environment has a generator or we fail.
        echo "WARNING: Base project template not found. Attempting to create directory structure."
        mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/travelbuddy"
        mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
        mkdir -p "$PROJECT_DIR/app/src/main/res/values"
        mkdir -p "$PROJECT_DIR/gradle/wrapper"
    fi
fi

# Ensure package path matches
PACKAGE_PATH="$PROJECT_DIR/app/src/main/java/com/example/travelbuddy"
mkdir -p "$PACKAGE_PATH"

# Create/Overwrite MainActivity.kt (Clean state)
cat > "$PACKAGE_PATH/MainActivity.kt" <<kotlinEOF
package com.example.travelbuddy

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        // TODO: Initialize ViewPager2 and TabLayout here
    }
}
kotlinEOF

# Create/Overwrite activity_main.xml (Empty state)
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<xmlEOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <!-- TODO: Add ViewPager2 and TabLayout -->
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="TravelBuddy"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
xmlEOF

# 3. Add Resources (Icons and Strings)
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Drawables
cat > "$RES_DIR/drawable/ic_explore.xml" <<EOF
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FF6200EE" android:pathData="M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM12,19.33c-4.05,0 -7.33,-3.28 -7.33,-7.33S7.95,4.67 12,4.67s7.33,3.28 7.33,7.33 -3.28,7.33 -7.33,7.33zM12,6.67c-2.94,0 -5.33,2.39 -5.33,5.33s2.39,5.33 5.33,5.33 5.33,-2.39 5.33,-5.33 -2.39,-5.33 -5.33,-5.33z"/></vector>
EOF
cat > "$RES_DIR/drawable/ic_plan.xml" <<EOF
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FF03DAC5" android:pathData="M19,3h-1L18,1h-2v2L8,3L8,1L6,1v2L5,3c-1.11,0 -1.99,0.9 -1.99,2L3,19c0,1.1 0.89,2 2,2h14c1.1,0 2,-0.9 2,-2L21,5c0,-1.1 -0.9,-2 -2,-2zM19,19L5,19L5,8h14v11z"/></vector>
EOF
cat > "$RES_DIR/drawable/ic_share.xml" <<EOF
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FF018786" android:pathData="M18,16.08c-0.76,0 -1.44,0.3 -1.96,0.77L8.91,12.7c0.05,-0.23 0.09,-0.46 0.09,-0.7s-0.04,-0.47 -0.09,-0.7l7.05,-4.11c0.54,0.5 1.25,0.81 2.04,0.81 1.66,0 3,-1.34 3,-3s-1.34,-3 -3,-3 -3,1.34 -3,3c0,0.24 0.04,0.47 0.09,0.7L8.04,9.81C7.5,9.31 6.79,9 6,9c-1.66,0 -3,1.34 -3,3s1.34,3 3,3c0.79,0 1.5,-0.31 2.04,-0.81l7.12,4.16c-0.05,0.21 -0.08,0.43 -0.08,0.65 0,1.61 1.31,2.92 2.92,2.92 1.61,0 2.92,-1.31 2.92,-2.92s-1.31,-2.92 -2.92,-2.92z"/></vector>
EOF

# Strings
cat > "$RES_DIR/values/strings.xml" <<EOF
<resources>
    <string name="app_name">TravelBuddy</string>
    <string name="onboard_title_1">Explore the World</string>
    <string name="onboard_desc_1">Discover hidden gems and popular destinations near you.</string>
    <string name="onboard_title_2">Plan Your Trip</string>
    <string name="onboard_desc_2">Organize flights, hotels, and itineraries in one place.</string>
    <string name="onboard_title_3">Share Memories</string>
    <string name="onboard_desc_3">Post photos and stories to inspire other travelers.</string>
</resources>
EOF

# Ensure permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew"

# 4. Open Project
setup_android_studio_project "$PROJECT_DIR" "TravelBuddy" 120

# 5. Timestamp
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="