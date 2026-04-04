#!/bin/bash
set -e
echo "=== Setting up secure_api_key_management task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/CityWeather 2>/dev/null || true

# --- Create CityWeather Project Structure ---
# We create a minimal functional project structure to ensure build capability

PROJECT_DIR="/home/ga/AndroidStudioProjects/CityWeather"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/cityweather/network"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

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
rootProject.name = "CityWeather"
include(":app")
EOF

# 2. Top-level build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 3. App-level build.gradle.kts (Vulnerable State: No buildConfig logic)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.cityweather"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.cityweather"
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
        // Agent needs to ensure this is true or added if missing (default is usually true in older AGP, false in newer)
        buildConfig = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
}
EOF

# 4. WeatherService.kt (Vulnerable State: Hardcoded Key)
cat > "$PROJECT_DIR/app/src/main/java/com/example/cityweather/network/WeatherService.kt" << 'EOF'
package com.example.cityweather.network

class WeatherService {

    companion object {
        // SECURITY ISSUE: Hardcoded API Key
        private const val API_KEY = "owm_8a7b6c5d4e3f2g1h0i9j8k7l6m5n4o3p"
        private const val BASE_URL = "https://api.openweathermap.org/data/2.5/"
    }

    fun getForecast(city: String): String {
        return "Fetching forecast for $city using key: $API_KEY"
    }
}
EOF

# 5. local.properties (Clean state)
cat > "$PROJECT_DIR/local.properties" << EOF
sdk.dir=/opt/android-sdk
EOF

# 6. Gradle Wrapper (Standard)
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

cp /workspace/data/gradle-wrapper.jar "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true
# If we don't have the jar, we hope the environment has a global gradle or we rely on the one in /opt

# Set Permissions
chown -R ga:ga "$PROJECT_DIR"
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# Open in Android Studio
setup_android_studio_project "$PROJECT_DIR" "CityWeather" 120

# Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="