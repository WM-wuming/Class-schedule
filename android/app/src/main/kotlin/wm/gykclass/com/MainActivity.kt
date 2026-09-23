package wm.gykclass.com

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val keepAliveChannel = "keep_alive"
    private val widgetChannel = "next_class_widget"
    private val ringChannel = "reminder_ring"

    // 与 Dart 侧 class_notifier_io.dart 的 reminderChannelId 保持一致。
    private val reminderChannelId = "class_reminder"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 横屏（或平板横持）时，默认的刘海模式 defaultMode 会让系统把整个窗口往内收，
        // 页面两侧出现黑边、状态栏区域也变成黑底。改成 shortEdges 让应用延伸到刘海区，
        // 内容是否避开刘海交给 Flutter 侧的 SafeArea 处理。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

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
                    "openBatterySaverSettings" ->
                        result.success(openBatterySaverSettings())
                    "openAutoStartSettings" ->
                        result.success(openAutoStartSettings())
                    "openAppDetailsSettings" ->
                        result.success(openAppDetailsSettings())
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(openUrl(url))
                    }
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
        // 上课提醒的「响铃」：勿扰豁免（通知策略访问）权限的查询与授权入口。
        // 拿到授权后，提醒渠道按「闹钟」类别发（见 class_notifier_io.dart），
        // 勿扰模式的默认例外规则就会放行提醒的铃声。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ringChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDndAccessGranted" ->
                        result.success(isDndAccessGranted())
                    "openDndAccessSettings" ->
                        result.success(openDndAccessSettings())
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

    /** 打开系统的「省电模式」设置页；低电量自动省电的机型会连白名单里的闹钟一起拦。 */
    private fun openBatterySaverSettings(): Boolean =
        try {
            startActivity(Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS))
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

    /** 用系统浏览器打开外部链接；没有可用的浏览器时返回 false。 */
    private fun openUrl(url: String): Boolean =
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            true
        } catch (error: Exception) {
            false
        }

    /**
     * 有没有拿到「能让提醒在勿扰下响」的放行，两条路任通其一即可：
     * ① 通知策略访问（勿扰豁免授权，老路子）；
     * ② 「上课提醒」渠道开了「允许勿扰期间通知 / 允许打扰」（用户在渠道设置页
     *    打开的开关，见 [openDndAccessSettings] 跳过去的那页）。
     */
    private fun isDndAccessGranted(): Boolean =
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager
            val byPolicy = manager?.isNotificationPolicyAccessGranted ?: false
            val byChannel = try {
                manager?.getNotificationChannel(reminderChannelId)?.canBypassDnd() ?: false
            } catch (error: Exception) {
                false
            }
            byPolicy || byChannel
        } catch (error: Exception) {
            false
        }

    /**
     * 跳到能让提醒「在勿扰下照常响」的设置页。
     *
     * 之前跳系统的「勿扰访问」授权列表（ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS），
     * 但新版 ColorOS 把它实现成了勿扰模式的开关页 —— 在那里只有「开/关勿扰」，
     * 没有放行本应用的入口。改为三级兜底：
     * ① 直达本应用「上课提醒」通知渠道的设置页（渠道 id 与
     *    class_notifier_io.dart 的 reminderChannelId 一致），里面有
     *    「允许勿扰期间通知 / 允许打扰」开关；
     * ② 退到本应用的通知设置页（用户在渠道列表里手动找「上课提醒」）；
     * ③ 再退回老的勿扰访问授权列表。
     */
    private fun openDndAccessSettings(): Boolean {
        val attempts =
            listOf<() -> Unit>(
                {
                    startActivity(
                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, reminderChannelId)
                    )
                },
                {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    )
                },
                {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                },
            )
        for (attempt in attempts) {
            try {
                attempt()
                return true
            } catch (error: Exception) {
                // 这一级跳不了就试下一级
            }
        }
        return false
    }

    /**
     * 直接打开系统设置的「应用信息」页。
     *
     * 之前按机型试自启动管理的专属 Activity（小米/华为/OPPO/一加…），但新版 ROM
     * （尤其 ColorOS 13+）频繁改包名类名，命中率低还常落到错误页面；拉起手机管家
     * 又要用户自己找两层。应用详情页是**所有机型都稳定可达**的起点——耗电管理
     * 就在里面，自启动开关则按指引卡说的路径去手机管家找。
     */
    private fun openAutoStartSettings(): Boolean = openAppDetailsSettings()
}
