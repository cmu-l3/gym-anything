#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up JaCoCo Coverage Task ==="
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"

# Clean any previous attempt
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json
mkdir -p "$PROJECT_DIR/app/src/main/kotlin/com/example/weatherapp"
mkdir -p "$PROJECT_DIR/app/src/test/kotlin/com/example/weatherapp"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# --- Project-level build.gradle.kts ---
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# --- settings.gradle.kts ---
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

# --- gradle.properties ---
cat > "$PROJECT_DIR/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

# --- local.properties ---
cat > "$PROJECT_DIR/local.properties" << 'EOF'
sdk.dir=/opt/android-sdk
EOF

# --- Gradle Wrapper ---
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Copy gradle wrapper from Android Studio's bundled version or create fallback
if [ -f /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew ]; then
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew "$PROJECT_DIR/gradlew"
    cp /opt/android-studio/plugins/android/lib/templates/gradle/wrapper/gradlew.bat "$PROJECT_DIR/gradlew.bat"
else
    cat > "$PROJECT_DIR/gradlew" << 'GRADLEW'
#!/bin/sh
APP_NAME="Gradle"
APP_BASE_NAME=$(basename "$0")
DEFAULT_JVM_OPTS='"-Xmx64m" "-Xms64m"'
DIRNAME=$(dirname "$0")
CLASSPATH="$DIRNAME/gradle/wrapper/gradle-wrapper.jar"
exec java $DEFAULT_JVM_OPTS -classpath "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
fi
chmod +x "$PROJECT_DIR/gradlew"

# Download gradle-wrapper.jar
if [ ! -f "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" ]; then
    wget -q "https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradle/wrapper/gradle-wrapper.jar" \
        -O "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || \
    wget -q "https://github.com/nicohman/nugget/raw/main/gradle/wrapper/gradle-wrapper.jar" \
        -O "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true
fi

# --- App-level build.gradle.kts (NO JaCoCo - agent must add it) ---
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
    implementation("com.google.android.material:material:1.11.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
EOF

# --- AndroidManifest.xml ---
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.MaterialComponents.Light.DarkActionBar">
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

# --- strings.xml ---
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">Weather App</string>
</resources>
EOF

# --- WeatherUtils.kt (Source Code) ---
cat > "$PROJECT_DIR/app/src/main/kotlin/com/example/weatherapp/WeatherUtils.kt" << 'KOTLIN'
package com.example.weatherapp

object WeatherUtils {
    fun fahrenheitToCelsius(f: Double): Double {
        return (f - 32.0) * 5.0 / 9.0
    }
    fun celsiusToFahrenheit(c: Double): Double {
        return c * 9.0 / 5.0 + 32.0
    }
    fun calculateHeatIndex(temperatureF: Double, relativeHumidity: Double): Double {
        val simpleHI = 0.5 * (temperatureF + 61.0 + ((temperatureF - 68.0) * 1.2) + (relativeHumidity * 0.094))
        if (simpleHI < 80.0) return simpleHI
        var hi = -42.379 + 2.04901523 * temperatureF + 10.14333127 * relativeHumidity
        return hi // Simplified for brevity
    }
}
KOTLIN

# --- MainActivity.kt ---
cat > "$PROJECT_DIR/app/src/main/kotlin/com/example/weatherapp/MainActivity.kt" << 'KOTLIN'
package com.example.weatherapp
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
KOTLIN

# --- WeatherUtilsTest.kt (Unit Tests) ---
cat > "$PROJECT_DIR/app/src/test/kotlin/com/example/weatherapp/WeatherUtilsTest.kt" << 'KOTLIN'
package com.example.weatherapp
import org.junit.Assert.*
import org.junit.Test
class WeatherUtilsTest {
    private val delta = 0.5
    @Test
    fun `fahrenheit to celsius - freezing point`() {
        assertEquals(0.0, WeatherUtils.fahrenheitToCelsius(32.0), delta)
    }
    @Test
    fun `celsius to fahrenheit - boiling point`() {
        assertEquals(212.0, WeatherUtils.celsiusToFahrenheit(100.0), delta)
    }
    @Test
    fun `heat index - simple`() {
        val hi = WeatherUtils.calculateHeatIndex(70.0, 50.0)
        assertTrue(hi < 80.0)
    }
}
KOTLIN

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial state of build.gradle.kts (for anti-gaming)
cp "$PROJECT_DIR/app/build.gradle.kts" /tmp/initial_build_gradle.kts
md5sum "$PROJECT_DIR/app/build.gradle.kts" > /tmp/initial_build_gradle_md5.txt

# Open the project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "WeatherApp" 120

# Capture initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== JaCoCo Coverage Task Setup Complete ==="