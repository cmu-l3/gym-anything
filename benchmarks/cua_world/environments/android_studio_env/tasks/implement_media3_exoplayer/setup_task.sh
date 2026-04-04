#!/bin/bash
set -e
echo "=== Setting up Task: Implement Media3 ExoPlayer ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Project Configuration
PROJECT_NAME="VideoPlayerApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"

# Clean up any previous runs
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json
rm -f /tmp/task_start.png /tmp/task_end.png

# 2. Create Directory Structure
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/videoplayer"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/raw"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Generate Settings Gradle
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

# 4. Generate Project Build Gradle
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 5. Generate App Build Gradle (Initial State - Missing Media3)
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.videoplayer"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.videoplayer"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    // Agent needs to add Media3 dependencies here
}
EOF

# 6. Generate Android Manifest
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:icon="@android:drawable/sym_def_app_icon"
        android:label="Video Player"
        android:theme="@style/Theme.Material3.DayNight.NoActionBar">
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

# 7. Generate Styles/Theme
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.VideoPlayerApp" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your light theme here. -->
    </style>
    <style name="Theme.VideoPlayerApp" parent="Base.Theme.VideoPlayerApp" />
    <style name="Theme.Material3.DayNight.NoActionBar" parent="Theme.MaterialComponents.DayNight.NoActionBar" />
</resources>
EOF

# 8. Generate MainActivity (Empty)
cat > "$PROJECT_DIR/app/src/main/java/com/example/videoplayer/MainActivity.kt" <<EOF
package com.example.videoplayer

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        // TODO: Initialize ExoPlayer here
    }
    
    // TODO: Handle lifecycle events
}
EOF

# 9. Generate Layout (Basic)
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Video Player App"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 10. Setup Gradle Wrapper
mkdir -p "$PROJECT_DIR/gradle/wrapper"
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# 11. Download Sample Video
# Using Big Buck Bunny 320x180 (small size)
echo "Downloading sample video..."
if [ ! -f "$PROJECT_DIR/app/src/main/res/raw/promo_video.mp4" ]; then
    # Try multiple sources if one fails
    curl -L -o "$PROJECT_DIR/app/src/main/res/raw/promo_video.mp4" \
        "https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4" || \
    curl -L -o "$PROJECT_DIR/app/src/main/res/raw/promo_video.mp4" \
        "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" # Ensure wrapper config is readable

# 12. Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "VideoPlayerApp"

# 13. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="