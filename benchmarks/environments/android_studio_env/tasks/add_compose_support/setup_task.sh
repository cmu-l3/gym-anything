#!/bin/bash
set -e

echo "=== Setting up add_compose_support task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="ViewsApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="com/example/viewsapp"

# Clean up previous artifacts
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png
rm -f /tmp/gradle_output.log

# Ensure parent directory exists
mkdir -p /home/ga/AndroidStudioProjects

# ------------------------------------------------------------------
# GENERATE VIEWS-BASED PROJECT (If not present in data)
# ------------------------------------------------------------------
# We generate a clean Views-only project to ensure a consistent starting state
# independent of external data files.

echo "Generating ViewsApp project..."
mkdir -p "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 1. settings.gradle.kts
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

# 2. build.gradle.kts (Root)
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 3. app/build.gradle.kts (Module - VIEWS ONLY)
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.viewsapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.viewsapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# 4. AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.ViewsApp"
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

# 5. MainActivity.kt (Views based)
cat > "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR/MainActivity.kt" <<EOF
package com.example.viewsapp

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle
import android.widget.Button
import android.widget.Toast

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.button).setOnClickListener {
            Toast.makeText(this, "Hello from Views!", Toast.LENGTH_SHORT).show()
        }
    }
}
EOF

# 6. Resources
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:orientation="vertical">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Welcome to ViewsApp" />

    <Button
        android:id="@+id/button"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:text="Click Me" />

</LinearLayout>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" <<EOF
<resources>
    <string name="app_name">ViewsApp</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" <<EOF
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.ViewsApp" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.ViewsApp" parent="Base.Theme.ViewsApp" />
</resources>
EOF

# 7. XML Configs
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<full-backup-content />" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
echo "<data-extraction-rules><cloud-backup><include domain=\"root\" path=\".\"/></cloud-backup></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"

# 8. Gradle Wrapper (Use system installed gradle or copy from template)
# We'll copy from a template if available, or just rely on the IDE to fix it.
# Ideally, we copy the wrapper from /opt/android-studio/plugins/android/lib/templates/gradle/wrapper if accessible,
# or assume the environment has a cached one.
# For this env, we'll try to use the one from a known location or just assume IDE handles it.
# To be robust, let's copy a wrapper if we have one, otherwise create minimal props.
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Create gradlew script (minimal stub to allow IDE to recognize it)
# Real gradlew is large; typically we'd cp -r /workspace/data/templates/gradlew .
# If we don't have it, we rely on the IDE's "Import Project".
# However, `run_gradle` utils usually call ./gradlew.
# We will assume `gradle` is in PATH or try to find a real wrapper.
if [ -f "/workspace/utils/gradlew" ]; then
    cp /workspace/utils/gradlew "$PROJECT_DIR/"
    chmod +x "$PROJECT_DIR/gradlew"
fi

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
if [ -f "$PROJECT_DIR/gradlew" ]; then chmod +x "$PROJECT_DIR/gradlew"; fi

# ------------------------------------------------------------------
# START ANDROID STUDIO
# ------------------------------------------------------------------

# Open the project
setup_android_studio_project "$PROJECT_DIR" "ViewsApp" 180

# Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="