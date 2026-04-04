#!/bin/bash
set -e
echo "=== Setting up implement_scoped_storage_save task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous runs
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/PhotoStamp 2>/dev/null || true

# 2. Create the Project Structure
# Since we don't have an external data source for this specific "broken" app,
# we will clone a basic template and inject the broken file.
# We'll use the "SunflowerApp" as a base if available, or create a minimal one.
# For reliability in this environment, we'll create a minimal valid project structure.

PROJECT_DIR="/home/ga/AndroidStudioProjects/PhotoStamp"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/photostamp"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# Copy Gradle wrapper from a known location or create dummy if needed
# Assuming the environment has a cache or we can copy from /opt/android-studio/plugins/android/lib/templates/gradle/wrapper
# For this task, we'll rely on the agent's IDE to handle gradle, but we need a valid build.gradle

# Create settings.gradle.kts
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
rootProject.name = "PhotoStamp"
include(":app")
EOF

# Create project build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# Create app build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.photostamp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.photostamp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
}
EOF

# Create AndroidManifest.xml
mkdir -p "$PROJECT_DIR/app/src/main"
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <application
        android:allowBackup="true"
        android:label="PhotoStamp"
        android:theme="@style/Theme.AppCompat.Light">
    </application>
</manifest>
EOF

# Create the broken ImageExporter.kt file
cat > "$PROJECT_DIR/app/src/main/java/com/example/photostamp/ImageExporter.kt" <<EOF
package com.example.photostamp

import android.content.Context
import android.graphics.Bitmap
import android.os.Environment
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

object ImageExporter {

    /**
     * Saves the bitmap to the public "Pictures/PhotoStamp" directory.
     */
    fun saveBitmapToGallery(context: Context, bitmap: Bitmap, filename: String) {
        // TODO: This crashes on Android 10+ due to Scoped Storage.
        // Task: Rewrite this function using MediaStore API.
        // 1. Use ContentResolver and MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        // 2. Set MIME type to "image/jpeg"
        // 3. Set relative path to "Pictures/PhotoStamp"
        // 4. Do NOT use Environment.getExternalStorageDirectory()

        // --- LEGACY CODE (TO BE REMOVED/REPLACED) ---
        try {
            val path = File(Environment.getExternalStorageDirectory(), "Pictures/PhotoStamp")
            if (!path.exists()) {
                path.mkdirs()
            }
            val file = File(path, filename)
            val out = FileOutputStream(file)
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            out.flush()
            out.close()
        } catch (e: IOException) {
            e.printStackTrace()
        }
        // --- END LEGACY CODE ---
    }
}
EOF

# Create a dummy Gradle wrapper if missing (to allow IDE import)
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    cp -r /workspace/data/SunflowerApp/gradle "$PROJECT_DIR/" 2>/dev/null || mkdir -p "$PROJECT_DIR/gradle/wrapper"
    cp /workspace/data/SunflowerApp/gradlew "$PROJECT_DIR/" 2>/dev/null || touch "$PROJECT_DIR/gradlew"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 3. Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "PhotoStamp" 120

# 4. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="