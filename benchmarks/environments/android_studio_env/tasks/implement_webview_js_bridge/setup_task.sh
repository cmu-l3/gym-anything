#!/bin/bash
set -e
echo "=== Setting up implement_webview_js_bridge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="HelpCenterApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_PATH="com/example/helpcenterapp"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/$PACKAGE_PATH"
RES_DIR="$PROJECT_DIR/app/src/main/res"
ASSETS_DIR="$PROJECT_DIR/app/src/main/assets"

# Clean up previous artifacts
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png
rm -f /tmp/gradle_build_output.txt

# ------------------------------------------------------------------
# Generate Project Structure (Simulating a fresh "Empty Activity")
# ------------------------------------------------------------------
echo "Generating project structure..."
mkdir -p "$PACKAGE_DIR"
mkdir -p "$RES_DIR/layout"
mkdir -p "$RES_DIR/values"
mkdir -p "$RES_DIR/mipmap-hdpi"
mkdir -p "$ASSETS_DIR"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" <<EOF
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$PROJECT_NAME"
include(":app")
EOF

# build.gradle.kts (Project level)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# app/build.gradle.kts
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.helpcenterapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.helpcenterapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/Theme.HelpCenterApp">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

# strings.xml
cat > "$RES_DIR/values/strings.xml" <<EOF
<resources>
    <string name="app_name">Help Center</string>
</resources>
EOF

# themes.xml
mkdir -p "$RES_DIR/values/themes"
cat > "$RES_DIR/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.HelpCenterApp" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.HelpCenterApp" parent="Base.Theme.HelpCenterApp" />
</resources>
EOF

# MainActivity.kt (Initial State)
cat > "$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.helpcenterapp

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // TODO: Initialize WebView here
    }
}
EOF

# activity_main.xml (Initial State)
cat > "$RES_DIR/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Welcome to Help Center"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# ------------------------------------------------------------------
# Create the Data Asset (HTML File)
# ------------------------------------------------------------------
cat > "$ASSETS_DIR/help_center.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: sans-serif; padding: 20px; }
        .card { border: 1px solid #ccc; padding: 15px; margin-bottom: 10px; border-radius: 8px; }
        button { background: #007bff; color: white; border: none; padding: 10px 20px; border-radius: 5px; font-size: 16px; }
    </style>
</head>
<body>
    <h1>FAQ</h1>
    <div class="card">
        <h3>How do I return an item?</h3>
        <p>Go to Orders > Select Item > Return.</p>
    </div>
    <div class="card">
        <h3>Still need help?</h3>
        <p>Tap the button below to open a support ticket.</p>
        <button onclick="contactSupport()">Contact Support</button>
    </div>

    <script>
        function contactSupport() {
            // This interface needs to be implemented in Android
            if (window.AndroidHelp) {
                window.AndroidHelp.submitTicket("TICKET-998877");
                document.body.style.backgroundColor = "#e8f5e9"; // Visual feedback
            } else {
                alert("Android interface not found!");
            }
        }
    </script>
</body>
</html>
EOF

# Copy standard gradlew
cp /workspace/data/templates/gradlew "$PROJECT_DIR/" 2>/dev/null || true
cp -r /workspace/data/templates/gradle "$PROJECT_DIR/" 2>/dev/null || true
chmod +x "$PROJECT_DIR/gradlew"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# Launch Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_DIR" "HelpCenterApp" 180

# Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="