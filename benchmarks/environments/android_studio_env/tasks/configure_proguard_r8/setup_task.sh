#!/bin/bash
set -e

echo "=== Setting up Configure ProGuard/R8 Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Cleanup previous run
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherNow"
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json /tmp/task_start.png 2>/dev/null || true

# 2. Create Project Structure
# We create a realistic project structure manually to ensure it has the exact dependencies and files needed.
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/weathernow/data/model"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/weathernow/data/api"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Create build.gradle.kts (Project Level)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    id("com.android.application") version "8.1.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# 4. Create settings.gradle.kts
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
rootProject.name = "WeatherNow"
include(":app")
EOF

# 5. Create app/build.gradle.kts (The key file agent needs to edit)
# Note: We pre-configure signing with debug key so assembleRelease works without real keys
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.weathernow"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.weathernow"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        create("release") {
            // Use debug keystore for this task to allow release builds to pass
            storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // TODO: Enable code shrinking and resource shrinking
            isMinifyEnabled = false
            isShrinkResources = false
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
    implementation("com.google.android.material:material:1.10.0")
    
    // Retrofit & Gson
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.google.code.gson:gson:2.10.1")
}
EOF

# 6. Create app/proguard-rules.pro (Empty initially)
cat > "$PROJECT_DIR/app/proguard-rules.pro" << 'EOF'
# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /opt/android-sdk/tools/proguard/proguard-android.txt
# You can edit the include path and order by changing the proguardFiles
# directive in build.gradle.

# TODO: Add rules to keep Gson models and Retrofit interfaces
EOF

# 7. Create Source Files (Models and API)

# WeatherResponse.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/weathernow/data/model/WeatherResponse.kt" << 'EOF'
package com.example.weathernow.data.model

import com.google.gson.annotations.SerializedName

data class WeatherResponse(
    @SerializedName("coord") val coord: Coordinates,
    @SerializedName("weather") val weather: List<Weather>,
    @SerializedName("main") val main: MainData,
    @SerializedName("name") val name: String
)

data class Coordinates(
    @SerializedName("lon") val lon: Double,
    @SerializedName("lat") val lat: Double
)

data class Weather(
    @SerializedName("id") val id: Int,
    @SerializedName("main") val main: String,
    @SerializedName("description") val description: String
)

data class MainData(
    @SerializedName("temp") val temp: Double,
    @SerializedName("pressure") val pressure: Int,
    @SerializedName("humidity") val humidity: Int
)
EOF

# WeatherApiService.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/weathernow/data/api/WeatherApiService.kt" << 'EOF'
package com.example.weathernow.data.api

import com.example.weathernow.data.model.WeatherResponse
import retrofit2.Call
import retrofit2.http.GET
import retrofit2.http.Query

interface WeatherApiService {
    @GET("weather")
    fun getCurrentWeather(
        @Query("q") cityName: String,
        @Query("appid") apiKey: String,
        @Query("units") units: String = "metric"
    ): Call<WeatherResponse>
}
EOF

# MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/weathernow/MainActivity.kt" << 'EOF'
package com.example.weathernow

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
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
        android:theme="@style/Theme.WeatherNow"
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

# Resource files (minimal)
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">WeatherNow</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.WeatherNow" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules />" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content />" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26"
touch "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
touch "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml"


# 8. Setup Gradle Wrapper
cp -r /workspace/data/CalculatorApp/gradle "$PROJECT_DIR/" 2>/dev/null || true
cp /workspace/data/CalculatorApp/gradlew "$PROJECT_DIR/" 2>/dev/null || true
chmod +x "$PROJECT_DIR/gradlew"

# 9. Ensure debug keystore exists
mkdir -p /home/ga/.android
if [ ! -f /home/ga/.android/debug.keystore ]; then
    keytool -genkey -v -keystore /home/ga/.android/debug.keystore \
        -storepass android -alias androiddebugkey -keypass android \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
    chown ga:ga /home/ga/.android/debug.keystore
fi

# 10. Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# 11. Open in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherNow" 120

# 12. Record start state
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="