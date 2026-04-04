#!/bin/bash
set -e
echo "=== Setting up migrate_version_catalog task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Project Location
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherTracker"

# 1. Clean previous state
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/gradle/wrapper"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/weathertracker"
mkdir -p "$PROJECT_DIR/data/src/main/java/com/example/weathertracker/data"

# 2. Setup Gradle Wrapper (Copy from system or generate)
# Assuming a standard wrapper exists in /opt/android-studio or similar, 
# but best to create a minimal one or copy if available. 
# We'll rely on the one from the template data if available, or just write properties.
# For this environment, we will generate a valid project structure.

cat > "$PROJECT_DIR/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
EOF

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
rootProject.name = "WeatherTracker"
include(":app", ":data")
EOF

# Root build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("com.android.library") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 3. Create 'app' module with HARDCODED dependencies
cat > "$PROJECT_DIR/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.weathertracker"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.weathertracker"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    
    // Lifecycle
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.7.0")
    
    // Navigation
    implementation("androidx.navigation:navigation-fragment-ktx:2.7.7")
    implementation("androidx.navigation:navigation-ui-ktx:2.7.7")

    // Project modules
    implementation(project(":data"))

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
EOF

# 4. Create 'data' module with HARDCODED dependencies
cat > "$PROJECT_DIR/data/build.gradle.kts" <<EOF
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp") version "1.9.22-1.0.17"
}

android {
    namespace = "com.example.weathertracker.data"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
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
    
    // Retrofit
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Room
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")
}
EOF

# Create dummy source files to make build pass
touch "$PROJECT_DIR/app/src/main/java/com/example/weathertracker/MainActivity.kt"
cat > "$PROJECT_DIR/app/src/main/java/com/example/weathertracker/MainActivity.kt" <<EOF
package com.example.weathertracker
import android.app.Activity
class MainActivity : Activity()
EOF

# Copy Gradle Wrapper from environment (standard practice)
if [ -d "/opt/android-studio/plugins/android/lib/templates/gradle/wrapper" ]; then
    cp -r /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/* "$PROJECT_DIR/"
else
    # Fallback if specific template path varies
    cp -r /workspace/data/gradle-wrapper/* "$PROJECT_DIR/" 2>/dev/null || true
fi

# Ensure gradlew exists and is executable
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    # Create a basic gradlew script if missing (unlikely if data prep is good, but safety net)
    echo '#!/bin/sh' > "$PROJECT_DIR/gradlew"
    echo 'exec gradle "$@"' >> "$PROJECT_DIR/gradlew"
fi
chmod +x "$PROJECT_DIR/gradlew"

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 5. Open Project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherTracker" 180

# 6. Capture initial state hash (to prove file modification later)
md5sum "$PROJECT_DIR/app/build.gradle.kts" > /tmp/initial_app_build_hash.txt
md5sum "$PROJECT_DIR/data/build.gradle.kts" > /tmp/initial_data_build_hash.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="