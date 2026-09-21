package com.example.class_schedule

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val keepAliveChannel = "keep_alive"
    private val widgetChannel = "next_class_widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keepAliveChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" ->
                        result.success(requestIgnoreBatteryOptimizations())
                    "openBatteryOptimizationSettings" ->
                        result.success(openBatteryOptimizationSettings())
                    "openAutoStartSettings" ->
                        result.success(openAutoStartSettings())
                    "openAppDetailsSettings" ->
                        result.success(openAppDetailsSettings())
                    else -> result.notImplemented()
                }
            }
        // 「下一节课」小组件：Flutter 算好接下来几天的课（JSON），存下来并立刻刷新小组件。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateSchedule" -> {
                        val json = call.argument<String>("json") ?: "[]"
                        try {
                            getSharedPreferences("next_class_widget", MODE_PRIVATE)
                                .edit()
                                .putString("payload", json)
                                .apply()
                            NextClassWidgetProvider.updateAll(this)
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun powerManager(): PowerManager? =
        getSystemService(POWER_SERVICE) as? PowerManager

    private fun isIgnoringBatteryOptimizations(): Boolean =
        try {
            powerManager()?.isIgnoringBatteryOptimizations(packageName) ?: false
        } catch (error: Exception) {
            false
        }

    /** 弹「允许忽略电池优化」确认框；不允许直接弹的机型退回列表页并返回 false。 */
    private fun requestIgnoreBatteryOptimizations(): Boolean =
        try {
            if (isIgnoringBatteryOptimizations()) {
                true
            } else {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName"))
                startActivity(intent)
                // 用户还没点确认框，这里只能先返回 false，状态以后再查。
                false
            }
        } catch (error: Exception) {
            try {
                openBatteryOptimizationSettings()
            } catch (ignored: Exception) {
            }
            false
        }

    private fun openBatteryOptimizationSettings(): Boolean =
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (error: Exception) {
            false
        }

    private fun openAppDetailsSettings(): Boolean =
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:$packageName"))
            )
            true
        } catch (error: Exception) {
            false
        }

    /**
     * 国产 ROM 的自启动管理没有标准入口，按已知组件名逐个试，
     * 全部失败退回应用详情页（从那里也能走到电池/自启动）。
     */
    private fun openAutoStartSettings(): Boolean {
        val candidates = listOf(
            // 小米 MIUI
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // 华为 EMUI / HarmonyOS
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"
            ),
            // OPPO ColorOS
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            // vivo OriginOS / FuntouchOS
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            // 三星 One UI
            ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.ram.AutoRunActivity"
            ),
            // 魅族 Flyme
            ComponentName(
                "com.meizu.safe",
                "com.meizu.safe.security.SHOW_APPSEC"
            )
        )
        for (component in candidates) {
            try {
                val intent = Intent().setComponent(component)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (error: Exception) {
                // 这台机器上没有这个入口，试下一个。
            }
        }
        return openAppDetailsSettings()
    }
}
