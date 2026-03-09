#!/bin/bash
set -e
echo "=== Setting up add_gradle_build_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_iso.txt

# Clean up previous artifacts
rm -rf /tmp/task_result.json /tmp/ground_truth.json 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/TodoApp 2>/dev/null || true

# ------------------------------------------------------------------
# 1. Create a Realistic Android Project Structure (TodoApp)
# ------------------------------------------------------------------
PROJECT_ROOT="/home/ga/AndroidStudioProjects/TodoApp"
mkdir -p "$PROJECT_ROOT/app/src/main/java/com/example/todoapp"
mkdir -p "$PROJECT_ROOT/app/src/main/res/values"
mkdir -p "$PROJECT_ROOT/gradle/wrapper"

# -- gradle.properties --
cat > "$PROJECT_ROOT/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
EOF

# -- settings.gradle.kts --
cat > "$PROJECT_ROOT/settings.gradle.kts" <<EOF
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
rootProject.name = "TodoApp"
include(":app")
EOF

# -- build.gradle.kts (Root) --
cat > "$PROJECT_ROOT/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# -- app/build.gradle.kts (The file to be modified) --
# Note: We include specific values that serve as ground truth
cat > "$PROJECT_ROOT/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.todoapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.todoapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 12
        versionName = "1.2.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
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
    implementation("com.google.android.material:material:1.10.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
EOF

# -- AndroidManifest.xml --
cat > "$PROJECT_ROOT/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.TodoApp"
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

# -- Dummy XML resources to prevent build errors --
mkdir -p "$PROJECT_ROOT/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_ROOT/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_ROOT/app/src/main/res/xml/backup_rules.xml"
echo "<resources><string name=\"app_name\">TodoApp</string></resources>" > "$PROJECT_ROOT/app/src/main/res/values/strings.xml"
mkdir -p "$PROJECT_ROOT/app/src/main/res/values/themes"
echo "<resources><style name=\"Theme.TodoApp\" parent=\"android:Theme.Material.Light.NoActionBar\" /></resources>" > "$PROJECT_ROOT/app/src/main/res/values/themes/themes.xml"

# -- MainActivity.kt --
cat > "$PROJECT_ROOT/app/src/main/java/com/example/todoapp/MainActivity.kt" <<EOF
package com.example.todoapp
import android.app.Activity
import android.os.Bundle
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
EOF

# -- Gradle Wrapper --
cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew "$PROJECT_ROOT/"
cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew.bat "$PROJECT_ROOT/"
cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradle/wrapper/gradle-wrapper.jar "$PROJECT_ROOT/gradle/wrapper/"
cat > "$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_ROOT"
chmod +x "$PROJECT_ROOT/gradlew"

# ------------------------------------------------------------------
# 2. Generate Ground Truth
# ------------------------------------------------------------------
# We manually count dependencies in the file above:
# implementation: 8 lines
# testImplementation: 1 line
# androidTestImplementation: 2 lines
# Total declared dependencies = 11

cat > /tmp/ground_truth.json <<EOF
{
  "applicationId": "com.example.todoapp",
  "versionName": "1.2.0",
  "versionCode": 12,
  "minSdk": 24,
  "targetSdk": 34,
  "compileSdk": 34,
  "javaVersion": "17",
  "dependencyCount_min": 8,
  "dependencyCount_max": 15
}
EOF
chmod 644 /tmp/ground_truth.json

# ------------------------------------------------------------------
# 3. Launch Android Studio
# ------------------------------------------------------------------
setup_android_studio_project "$PROJECT_ROOT" "TodoApp" 180

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="