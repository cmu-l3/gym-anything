#!/bin/bash
set -e
echo "=== Setting up add_network_security_config task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"

# Clean any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# --- GENERATE MINIMAL ANDROID PROJECT STRUCTURE ---

# 1. Root build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 2. settings.gradle.kts
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

# 3. gradle.properties
cat > "$PROJECT_DIR/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

# 4. Gradle Wrapper
mkdir -p "$PROJECT_DIR/gradle/wrapper"
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Copy wrapper jar if available, else standard fallback
if [ -f /opt/android-studio/plugins/gradle/lib/gradle-wrapper.jar ]; then
    find /opt/android-studio -name "gradle-wrapper.jar" -exec cp {} "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" \; -quit 2>/dev/null || true
fi

# Create gradlew script
cat > "$PROJECT_DIR/gradlew" << 'GRADLEW'
#!/bin/sh
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
APP_HOME=$( cd "${APP_HOME:-$(dirname "$0")}" > /dev/null && pwd -P )
CLASSPATH=$APP_HOME/gradle/wrapper/gradle-wrapper.jar
exec "$JAVA_HOME/bin/java" $JAVA_OPTS -classpath "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
chmod +x "$PROJECT_DIR/gradlew"

# 5. App Module build.gradle.kts
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
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
}
EOF

# 6. AndroidManifest.xml (Initial state: NO networkSecurityConfig)
mkdir -p "$PROJECT_DIR/app/src/main"
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application
        android:allowBackup="true"
        android:label="WeatherApp"
        android:supportsRtl="true"
        android:theme="@style/Theme.WeatherApp">
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

# 7. Basic Source Code
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/weatherapp"
cat > "$PROJECT_DIR/app/src/main/java/com/example/weatherapp/MainActivity.kt" << 'EOF'
package com.example.weatherapp
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# 8. Resources
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
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

mkdir -p "$PROJECT_DIR/app/src/main/res/values"
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources>
    <style name="Theme.WeatherApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">#6200EE</item>
    </style>
</resources>
EOF

# Ensure xml directory does NOT exist
rm -rf "$PROJECT_DIR/app/src/main/res/xml"

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial file checksums for anti-gaming
find "$PROJECT_DIR" -type f -exec md5sum {} \; | sort > /tmp/initial_checksums.txt
cp "$PROJECT_DIR/app/src/main/AndroidManifest.xml" /tmp/initial_manifest.xml

# Open project in Android Studio
echo "Opening project in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 120

# Initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="