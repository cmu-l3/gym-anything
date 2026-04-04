#!/bin/bash
set -e

echo "=== Setting up implement_android12_splash_screen task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Clean up artifacts
rm -rf /tmp/task_result.json /tmp/gradle_output.log 2>/dev/null || true

# Define Project Paths
PROJECT_NAME="SunriseApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="app/src/main/java/com/example/sunriseapp"
RES_DIR="app/src/main/res"

# Remove existing project to start fresh
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR"

echo "Generating SunriseApp project structure..."

# 1. Root settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" << 'EOF'
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
rootProject.name = "SunriseApp"
include(":app")
EOF

# 2. Root build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 3. App module directory
mkdir -p "$PROJECT_DIR/app"

# 4. App build.gradle.kts (Missing splash dependency initially)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.sunriseapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.sunriseapp"
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
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
EOF

# 5. Create Source Directories
mkdir -p "$PROJECT_DIR/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/$RES_DIR/layout"
mkdir -p "$PROJECT_DIR/$RES_DIR/values"
mkdir -p "$PROJECT_DIR/$RES_DIR/mipmap-hdpi"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 6. AndroidManifest.xml (Uses default theme initially)
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
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
        android:theme="@style/Theme.SunriseApp"
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

# 7. MainActivity.kt (Missing installSplashScreen)
cat > "$PROJECT_DIR/$PACKAGE_DIR/MainActivity.kt" << 'EOF'
package com.example.sunriseapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# 8. Resources (themes.xml, strings.xml, colors.xml)
cat > "$PROJECT_DIR/$RES_DIR/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <!-- Base application theme. -->
    <style name="Base.Theme.SunriseApp" parent="Theme.Material3.DayNight.NoActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>

    <style name="Theme.SunriseApp" parent="Base.Theme.SunriseApp" />
</resources>
EOF

cat > "$PROJECT_DIR/$RES_DIR/values/colors.xml" << 'EOF'
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="teal_200">#FF03DAC5</color>
    <color name="teal_700">#FF018786</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

cat > "$PROJECT_DIR/$RES_DIR/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">SunriseApp</string>
</resources>
EOF

cat > "$PROJECT_DIR/$RES_DIR/layout/activity_main.xml" << 'EOF'
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
        android:text="Welcome to Sunrise App!"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# Dummy xml rules to satisfy manifest
mkdir -p "$PROJECT_DIR/$RES_DIR/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/$RES_DIR/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/$RES_DIR/xml/backup_rules.xml"

# Copy Gradle Wrapper from system or generate it
# Assuming environment has a gradle wrapper we can copy or we rely on system gradle
# To make it self-contained, we'll try to use the one from /opt/android-studio/plugins/android/lib/templates/gradle/wrapper if it exists,
# or just rely on 'gradle wrapper' command if gradle is in path.
if command -v gradle &> /dev/null; then
    cd "$PROJECT_DIR"
    gradle wrapper --gradle-version 8.4 > /dev/null 2>&1 || true
fi

# Ensure permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "SunriseApp" 180

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="