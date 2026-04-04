#!/bin/bash
echo "=== Setting up extend_navigation_graph task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Project paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskTracker"
DATA_SOURCE="/workspace/data/TaskTracker"

# Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png /tmp/task_final.png 2>/dev/null || true

# Ensure parent directory exists
mkdir -p /home/ga/AndroidStudioProjects

# Copy project data
if [ -d "$DATA_SOURCE" ]; then
    echo "Copying TaskTracker project from data source..."
    cp -r "$DATA_SOURCE" "$PROJECT_DIR"
else
    echo "WARNING: Data source not found. Generating minimal TaskTracker project..."
    # Fallback: Create a minimal project structure if data is missing (for standalone testing)
    mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/tasktracker"
    mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
    mkdir -p "$PROJECT_DIR/app/src/main/res/navigation"
    mkdir -p "$PROJECT_DIR/gradle/wrapper"
    
    # Create minimal build.gradle.kts
    cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.example.tasktracker"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.tasktracker"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.navigation:navigation-fragment-ktx:2.7.7")
    implementation("androidx.navigation:navigation-ui-ktx:2.7.7")
}
EOF

    # Create dummy HomeFragment
    cat > "$PROJECT_DIR/app/src/main/java/com/example/tasktracker/HomeFragment.kt" << 'EOF'
package com.example.tasktracker
import android.os.Bundle
import android.view.View
import android.widget.Button
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController

class HomeFragment : Fragment(R.layout.fragment_home) {
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        view.findViewById<Button>(R.id.btn_settings).setOnClickListener {
            // TODO: Implement navigation to settings
        }
    }
}
EOF

    # Create dummy Layout
    cat > "$PROJECT_DIR/app/src/main/res/layout/fragment_home.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">
    <Button android:id="@+id/btn_settings" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Settings"/>
</LinearLayout>
EOF

    # Create initial nav_graph.xml
    cat > "$PROJECT_DIR/app/src/main/res/navigation/nav_graph.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<navigation xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/nav_graph"
    app:startDestination="@id/homeFragment">
    <fragment
        android:id="@+id/homeFragment"
        android:name="com.example.tasktracker.HomeFragment"
        android:label="Home"
        tools:layout="@layout/fragment_home" />
</navigation>
EOF
    
    # Create gradlew dummy (just to prevent setup failure, verification will fail build if not present)
    touch "$PROJECT_DIR/gradlew"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "TaskTracker" 120

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="