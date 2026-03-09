#!/bin/bash
set -e
echo "=== Setting up add_app_widget task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/WeatherApp 2>/dev/null || true

# Prepare the WeatherApp project
# We'll use a base template or copy an existing simple project and rename it
# Assuming we have a base project in data, or we use a script to generate a minimal one.
# For robustness in this environment, we'll clone a known sample if available, or create a minimal structure.
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
mkdir -p "$PROJECT_DIR"

# Use SunflowerApp as a base if available (it's in the env), otherwise create minimal
if [ -d "/workspace/data/SunflowerApp" ]; then
    echo "Creating WeatherApp from SunflowerApp template..."
    cp -r /workspace/data/SunflowerApp/* "$PROJECT_DIR/"
    
    # Rename package references to look like WeatherApp
    # This is a bit "hacky" but ensures a valid compiling project structure
    find "$PROJECT_DIR" -type f -name "*.kt" -o -name "*.xml" -o -name "*.gradle*" | xargs sed -i 's/com.google.samples.apps.sunflower/com.example.weatherapp/g' 2>/dev/null || true
    
    # Move source files to match new package structure
    mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/weatherapp"
    mv "$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower"/* "$PROJECT_DIR/app/src/main/java/com/example/weatherapp/" 2>/dev/null || true
    rm -rf "$PROJECT_DIR/app/src/main/java/com/google"
    
    # Update settings.gradle
    echo "rootProject.name='WeatherApp'" > "$PROJECT_DIR/settings.gradle.kts"
else
    # Fallback: Create minimal project structure if template missing
    echo "WARNING: Template not found, creating minimal project..."
    mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/weatherapp"
    mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
    mkdir -p "$PROJECT_DIR/app/src/main/res/values"
    
    # Create basic build.gradle.kts
    cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.0" apply false
}
EOF
    
    cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.example.weatherapp"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.weatherapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}
EOF
    
    # Create Manifest
    cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="WeatherApp"
        android:theme="@style/Theme.AppCompat.Light">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

    # Create MainActivity
    cat > "$PROJECT_DIR/app/src/main/java/com/example/weatherapp/MainActivity.kt" <<EOF
package com.example.weatherapp
import android.app.Activity
import android.os.Bundle
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
EOF
fi

# Ensure permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# Record initial Manifest hash to detect changes later
md5sum "$PROJECT_DIR/app/src/main/AndroidManifest.xml" > /tmp/initial_manifest_hash.txt

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="