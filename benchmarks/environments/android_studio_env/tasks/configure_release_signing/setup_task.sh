#!/bin/bash
set -e
echo "=== Setting up configure_release_signing task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /tmp/task_result.json /tmp/keytool_output.txt /tmp/apksigner_output.txt 2>/dev/null || true
rm -f /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true

# Define project path
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/cloudview/weatherapp"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# ------------------------------------------------------------------
# Generate a valid Android Project Structure (Kotlin DSL)
# ------------------------------------------------------------------

# 1. settings.gradle.kts
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
rootProject.name = "WeatherApp"
include(":app")
EOF

# 2. Top-level build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 3. App-level build.gradle.kts (The one agent needs to edit)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.cloudview.weatherapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.cloudview.weatherapp"
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

# 4. AndroidManifest.xml
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

# 5. Resources (Dummy files to prevent build errors)
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">WeatherApp</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.WeatherApp" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.WeatherApp" parent="Base.Theme.WeatherApp" />
</resources>
EOF

mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

# 6. MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/cloudview/weatherapp/MainActivity.kt" << 'EOF'
package com.cloudview.weatherapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# 7. Layout
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
</androidx.constraintlayout.widget.ConstraintLayout>
EOF

# 8. Copy Gradle Wrapper from system or created one
# Note: Ideally we copy a known good wrapper. Here we assume one exists or creating a dummy one to trigger IDE to fix it.
# Actually, the best way in this env is to use the `gradle` command if installed, or rely on Studio.
# We'll copy a wrapper from a potentially existing project or download one if we had internet.
# Since we can't guarantee internet in this script block without `curl`, and we want to be safe:
# We will create a minimal properties file so Studio knows what version to use.
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Create the gradlew scripts (simplified)
cat > "$PROJECT_DIR/gradlew" << 'EOF'
#!/bin/sh
exec gradle "$@"
EOF
chmod +x "$PROJECT_DIR/gradlew"

# ------------------------------------------------------------------
# Permissions & Setup
# ------------------------------------------------------------------

chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 180

# Capture initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="