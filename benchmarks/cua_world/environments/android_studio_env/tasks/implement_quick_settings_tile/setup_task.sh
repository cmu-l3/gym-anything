#!/bin/bash
set -e
echo "=== Setting up implement_quick_settings_tile task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project setup variables
PROJECT_NAME="DevTools"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/devtools"

# 1. Scaffolding the Project (Simulating a pre-existing repo)
# We recreate a minimal valid Android project structure since we can't assume external data presence
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/res/drawable"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# Copy Gradle wrapper from a known location (or system default) if available, else standard stub
# Assuming env has a cached wrapper or we can copy from /opt/android-studio/plugins/android/lib/templates/gradle/wrapper
# For this script, we'll try to find one, or rely on Android Studio to fix it, but best to provide a minimal one.
# We will skip the binary jar copy to avoid encoding issues and rely on 'gradle init' style structure if possible.
# BETTER: Just create the text files. The agent opening it in AS will trigger a wrapper generation if missing.

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

# build.gradle.kts (Project)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# app/build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.devtools"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.devtools"
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
}
EOF

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@drawable/ic_launcher_foreground"
        android:label="DevTools"
        android:theme="@style/Theme.DevTools">
        
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        
        <!-- TODO: Add TileService here -->

    </application>

</manifest>
EOF

# Create dummy resources to prevent build errors
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" <<EOF
<resources>
    <style name="Theme.DevTools" parent="Theme.Material3.DayNight.NoActionBar" />
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup><include domain="root" /></cloud-backup>
    <device-transfer><include domain="root" /></device-transfer>
</data-extraction-rules>
EOF

cat > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content><include domain="root" /></full-backup-content>
EOF

# MainActivity.kt
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.devtools

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# PrefsManager.kt (The helper object mentioned in the task)
cat > "$PROJECT_DIR/$PACKAGE_DIR/PrefsManager.kt" <<EOF
package com.example.devtools

import android.content.Context
import android.content.SharedPreferences

object PrefsManager {
    private const val PREFS_NAME = "devtools_prefs"
    const val KEY_DEMO_MODE = "demo_mode_enabled"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun isDemoModeEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_DEMO_MODE, false)
    }

    fun setDemoModeEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_DEMO_MODE, enabled).apply()
    }
}
EOF

# Layout file
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="DevTools App" />
</LinearLayout>
EOF

# Icon (Using a placeholder vector or just creating an empty one to satisfy build)
cat > "$PROJECT_DIR/app/src/main/res/drawable/ic_launcher_foreground.xml" <<EOF
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#FF000000" android:pathData="M0,0h108v108h-108z"/>
</vector>
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# 2. Setup Android Studio
# Use the helper function to open the project
setup_android_studio_project "$PROJECT_DIR" "DevTools" 120

# 3. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="