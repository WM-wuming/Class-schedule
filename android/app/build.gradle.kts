import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名凭据放在 android/key.properties（已 gitignore，不入库）。
// 文件不存在时自动退回 debug 签名，保证 `flutter run --release` 依旧可用。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "wm.gykclass.com"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 用了 com.android.tools:desugar_jdk_libs（java.time 等
        // 新 API 在低版本系统上的兼容层），AAR metadata 校验要求**宿主 app 也**打开这个开关，
        // 否则 :app:checkReleaseAarMetadata 直接失败。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "wm.gykclass.com"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 写死 24（Android 7.0）：Android 9 (API 28) 及以上的手机都能安装。
        // 不写死的话，将来 Flutter 升级把默认 minSdk 抬到 29+ 就会把老设备挤掉。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // 真机只有 arm 两种架构；x86/x86_64 只给模拟器用，却各自要背一份
            // ML Kit 识别库（每个 ABI 约 7MB），砍掉后 APK 小一圈。
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // 发布包只装 arm 两种架构（见 build apk --target-platform），x86_64 只给模拟器用，
    // 却各自要背一份 11MB 的 ML Kit 识别库 —— 这里直接排除出包。
    packaging {
        jniLibs {
            excludes += listOf("lib/x86_64/**")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // 没配 key.properties 时退回 debug 签名，保证 `flutter run --release` 仍能跑。
                signingConfigs.getByName("debug")
            }
            // ML Kit 文字识别插件只打包拉丁文模型，consumer 规则引用的其它语言识别器
            // 缺类会导致 R8 失败，见同目录 proguard-rules.pro。
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    // 版本与 flutter_local_notifications/android/build.gradle 里声明的保持一致。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
