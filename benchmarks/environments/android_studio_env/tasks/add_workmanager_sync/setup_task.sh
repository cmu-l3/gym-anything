#!/bin/bash
set -e
echo "=== Setting up add_workmanager_sync task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -rf /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /tmp/initial_hashes.txt 2>/dev/null || true

# 2. Define Project Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
APP_DIR="$PROJECT_DIR/app"
SRC_MAIN="$APP_DIR/src/main"
JAVA_DIR="$SRC_MAIN/java/com/example/weatherapp"

# 3. Create Project Structure
# We generate a minimal functional Android project programmatically to ensure a clean state
# without relying on external downloads that might fail or change.

echo "Generating WeatherApp project at $PROJECT_DIR..."
rm -rf "$PROJECT_DIR"
mkdir -p "$JAVA_DIR/data"
mkdir -p "$SRC_MAIN/res/layout"
mkdir -p "$SRC_MAIN/res/values"
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
rootProject.name = "WeatherApp"
include(":app")
EOF

# build.gradle.kts (Project level)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# app/build.gradle.kts (App level - MISSING WorkManager)
cat > "$APP_DIR/build.gradle.kts" <<EOF
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    // WorkManager dependency is intentionally missing
}
EOF

# AndroidManifest.xml
cat > "$SRC_MAIN/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="WeatherApp"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.WeatherApp"
        tools:targetApi="31">
        
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

# MainActivity.kt
cat > "$JAVA_DIR/MainActivity.kt" <<EOF
package com.example.weatherapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.example.weatherapp.data.WeatherRepository

class MainActivity : AppCompatActivity() {
    private val repository = WeatherRepository()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        // Simulating some UI interaction
        repository.getWeatherData()
    }
}
EOF

# WeatherRepository.kt (Dummy data layer)
cat > "$JAVA_DIR/data/WeatherRepository.kt" <<EOF
package com.example.weatherapp.data

class WeatherRepository {
    fun getWeatherData(): String {
        return "Sunny, 25C"
    }
}
EOF

# Layout file
cat > "$SRC_MAIN/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Weather App" />
</LinearLayout>
EOF

# Styles/Theme
cat > "$SRC_MAIN/res/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.WeatherApp" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.WeatherApp" parent="Base.Theme.WeatherApp" />
</resources>
EOF

# Create dummy XML rules referenced in Manifest to prevent build errors
mkdir -p "$SRC_MAIN/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$SRC_MAIN/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$SRC_MAIN/res/xml/backup_rules.xml"

# gradle-wrapper.properties
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Copy Gradle Wrapper Jar if available in environment (optimization)
# If not, Android Studio will download it upon opening
if [ -f "/opt/android-studio/plugins/gradle/lib/gradle-wrapper.jar" ]; then
    cp "/opt/android-studio/plugins/gradle/lib/gradle-wrapper.jar" "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial file existence (for anti-gaming "do nothing" check)
# We expect SyncWorker.kt and WeatherApplication.kt to NOT exist initially
if [ ! -f "$JAVA_DIR/sync/SyncWorker.kt" ]; then
    echo "SyncWorker.kt missing (expected)" > /tmp/initial_check_worker.txt
fi
if [ ! -f "$JAVA_DIR/WeatherApplication.kt" ]; then
    echo "WeatherApplication.kt missing (expected)" > /tmp/initial_check_app.txt
fi

# 4. Open Android Studio
echo "Opening Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 180

# 5. Take Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="