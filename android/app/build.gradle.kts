import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------- 签名配置 ----------
//
// 优先读环境变量（CI 从 GitHub Secrets 注入），其次读本地 android/key.properties。
// 两者都缺失时回退到 debug 签名，保证本地 `flutter run --release` 仍可用；
// 但这样的产物无法被正式包覆盖安装，因此 CI 会把它标注为测试包且不上传 Release。
val keystoreProps = Properties()
val keystorePropsFile = rootProject.file("key.properties")
if (keystorePropsFile.exists()) {
    keystorePropsFile.inputStream().use { keystoreProps.load(it) }
}

val releaseStorePath: String? =
    System.getenv("ANDROID_KEYSTORE_PATH") ?: keystoreProps.getProperty("storeFile")
val releaseStorePassword: String? =
    System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: keystoreProps.getProperty("storePassword")
val releaseKeyAlias: String? =
    System.getenv("ANDROID_KEY_ALIAS") ?: keystoreProps.getProperty("keyAlias")
val releaseKeyPassword: String? =
    System.getenv("ANDROID_KEY_PASSWORD") ?: keystoreProps.getProperty("keyPassword")

// 只有密钥库文件确实存在时才启用 release 签名：
// 否则 Gradle 会在配置阶段直接抛错，导致连 debug 构建都跑不起来
val hasReleaseKeystore = releaseStorePath != null && File(releaseStorePath).exists()

android {
    namespace = "com.crazyfigure.picpro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.crazyfigure.picpro"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 仅保留 arm64-v8a：Rust 内核需为每个 ABI 单独编译，
        // 限制 ABI 能显著减小 APK 体积；如需兼容老旧 32 位设备可放开 armeabi-v7a
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 未配置密钥库时的降级路径，仅用于本地调试
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
