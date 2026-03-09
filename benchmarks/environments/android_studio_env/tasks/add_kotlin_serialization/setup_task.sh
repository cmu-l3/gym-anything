#!/bin/bash
set -e
echo "=== Setting up add_kotlin_serialization task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="GitHubBrowser"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/githubbrowser"

# Clean up previous artifacts
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png

# Create fresh project structure manually to ensure a consistent clean state
# (Simulating a basic "Empty Views Activity" project)
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/githubbrowser"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# --- 1. settings.gradle.kts ---
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

# --- 2. build.gradle.kts (Project) ---
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# --- 3. app/build.gradle.kts ---
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.githubbrowser"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.githubbrowser"
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
}
EOF

# --- 4. AndroidManifest.xml ---
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="$PROJECT_NAME"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light">
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

# --- 5. MainActivity.kt ---
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.githubbrowser

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
EOF

# --- 6. Gradle Wrapper (Copy from installed location or creating minimal properties) ---
# Assuming /opt/android-studio/plugins/android/lib/templates/gradle/wrapper exists or similar,
# but safest is to write the properties and let Android Studio fix the jar if missing,
# OR rely on `gradle wrapper` command if gradle is in path.
# We will write properties and try to copy jar if available, otherwise `gradlew` might fail until opened in AS.
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Attempt to copy wrapper jar/script from a known location or system
# (In this env, we might not have a clean source, so we rely on opening in AS to potentially fix it,
# or better, use the pre-installed gradle to generate it)
if command -v gradle >/dev/null 2>&1; then
    cd "$PROJECT_DIR"
    gradle wrapper >/dev/null 2>&1 || true
fi

# Ensure gradlew exists and is executable (created by gradle wrapper)
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    # Fallback: create a dummy gradlew that fails if run before AS fixes it
    touch "$PROJECT_DIR/gradlew"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "$PROJECT_NAME" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="