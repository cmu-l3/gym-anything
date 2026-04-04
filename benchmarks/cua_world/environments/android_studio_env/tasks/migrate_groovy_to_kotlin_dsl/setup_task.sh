#!/bin/bash
set -e

echo "=== Setting up migrate_groovy_to_kotlin_dsl task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="WeatherApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="com/example/weatherapp"
AGP_VERSION="8.2.0"
KOTLIN_VERSION="1.9.0"

# Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/app/src/main/java/$PACKAGE_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

echo "Creating Groovy DSL project structure..."

# 1. Create settings.gradle (Groovy)
cat > "$PROJECT_DIR/settings.gradle" << GROOVY
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
include ':app'
GROOVY

# 2. Create root build.gradle (Groovy)
cat > "$PROJECT_DIR/build.gradle" << GROOVY
plugins {
    id 'com.android.application' version '$AGP_VERSION' apply false
    id 'org.jetbrains.kotlin.android' version '$KOTLIN_VERSION' apply false
}
GROOVY

# 3. Create app/build.gradle (Groovy)
cat > "$PROJECT_DIR/app/build.gradle" << GROOVY
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.example.weatherapp'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.weatherapp"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"

        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = '1.8'
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    testImplementation 'junit:junit:4.13.2'
    androidTestImplementation 'androidx.test.ext:junit:1.1.5'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.5.1'
}
GROOVY

# 4. Create gradle.properties
cat > "$PROJECT_DIR/gradle.properties" << PROPS
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
PROPS

# 5. Create AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << MANIFEST
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
MANIFEST

# 6. Create MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/weatherapp/MainActivity.kt" << KOTLIN
package com.example.weatherapp

import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
KOTLIN

# 7. Create layout and resources
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << XML
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
        android:text="Weather App"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
XML

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << XML
<resources>
    <string name="app_name">WeatherApp</string>
</resources>
XML

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << XML
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Base.Theme.WeatherApp" parent="Theme.Material3.DayNight.NoActionBar">
    </style>
    <style name="Theme.WeatherApp" parent="Base.Theme.WeatherApp" />
</resources>
XML

cat > "$PROJECT_DIR/app/src/main/res/values/colors.xml" << XML
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="teal_200">#FF03DAC5</color>
    <color name="teal_700">#FF018786</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
XML

# 8. Create dummy backup rules to satisfy manifest
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo '<full-backup-content />' > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
echo '<data-extraction-rules />' > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"

# 9. Setup Gradle Wrapper (copied from system install or downloaded)
# We'll use the one from /opt/android-studio/plugins/android/lib/templates/gradle/wrapper if available,
# or create a basic property file pointing to a distribution.
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << PROPS
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
PROPS

cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradle/wrapper/gradle-wrapper.jar "$PROJECT_DIR/gradle/wrapper/" 2>/dev/null || \
wget -q -O "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" "https://raw.githubusercontent.com/gradle/gradle/v8.4.0/gradle/wrapper/gradle-wrapper.jar"

# 10. Fix permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar"

# 11. Copy gradlew scripts
cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew "$PROJECT_DIR/" 2>/dev/null || true
cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew.bat "$PROJECT_DIR/" 2>/dev/null || true
chmod +x "$PROJECT_DIR/gradlew"

# 12. Run initial build to verify Groovy setup works
echo "Verifying initial Groovy project builds..."
cd "$PROJECT_DIR"
su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon"

# 13. Open in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 180

# 14. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="