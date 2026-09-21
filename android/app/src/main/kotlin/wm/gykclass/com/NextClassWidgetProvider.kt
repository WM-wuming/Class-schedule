package wm.gykclass.com

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * 「下一节课」桌面小组件。
 *
 * 数据来源是 Flutter 侧算好的 JSON（见 lib/models/next_class.dart，经 MainActivity
 * 写进 `next_class_widget` 这个 SharedPreferences），这里只做三件事：
 * 1. 挑出第一条「还没下课」的条目显示（正在上的课显示成「正在上课」）；
 * 2. 一条都没有就显示「没有课了可以放心玩了！」；
 * 3. 在这条课的边界（开课/下课时刻）定个闹钟精准刷新，兜底另有系统 30 分钟一拍的轮询。
 */
class NextClassWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            updateAll(context)
        }
    }

    companion object {
        const val ACTION_REFRESH = "wm.gykclass.com.WIDGET_NEXT_CLASS_REFRESH"

        private const val PREFS = "next_class_widget"
        private const val KEY_PAYLOAD = "payload"
        private const val ALARM_REQUEST_CODE = 41

        /** 读取 Flutter 推来的数据并刷新所有小组件实例；任何一步失败都静默。 */
        fun updateAll(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(
                    ComponentName(context, NextClassWidgetProvider::class.java)
                )
                if (ids.isEmpty()) return

                val now = System.currentTimeMillis()
                val entries: List<JSONObject> = try {
                    val raw = context
                        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .getString(KEY_PAYLOAD, "[]") ?: "[]"
                    val array = JSONArray(raw)
                    (0 until array.length()).map { array.getJSONObject(it) }
                } catch (error: Exception) {
                    emptyList()
                }
                val current: JSONObject? = entries.firstOrNull {
                    it.optLong("end") > now
                }

                val views = RemoteViews(context.packageName, R.layout.next_class_widget)
                if (current == null) {
                    views.setViewVisibility(R.id.widget_content, View.GONE)
                    views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    views.setTextViewText(R.id.widget_empty, "没有课了\n可以放心玩了！")
                    cancelBoundaryAlarm(context)
                } else {
                    val start = current.optLong("start")
                    val end = current.optLong("end")
                    val inClass = now >= start
                    val day = current.optString("day", "今天")
                    views.setViewVisibility(R.id.widget_empty, View.GONE)
                    views.setViewVisibility(R.id.widget_content, View.VISIBLE)
                    views.setTextViewText(
                        R.id.widget_header,
                        when {
                            inClass -> "正在上课"
                            day == "今天" -> "下一节课"
                            else -> "下一节"
                        }
                    )
                    views.setTextViewText(R.id.widget_day, day)
                    views.setTextViewText(R.id.widget_name, current.optString("name", ""))
                    views.setTextViewText(
                        R.id.widget_time,
                        "${current.optString("time", "")} · ${current.optString("period", "")}"
                    )
                    val place = current.optString("location", "").trim()
                    val teacher = current.optString("teacher", "").trim()
                    views.setViewVisibility(
                        R.id.widget_place,
                        if (place.isEmpty() && teacher.isEmpty()) View.GONE else View.VISIBLE
                    )
                    views.setTextViewText(
                        R.id.widget_place,
                        listOf(place, teacher).filter { it.isNotEmpty() }.joinToString(" · ")
                    )
                    // 没在上课 → 开课那一刻刷新（变「正在上课」）；在上课 → 下课那一刻刷新（换下一节）。
                    scheduleBoundaryAlarm(context, if (inClass) end else start)
                }

                // 点组件打开应用。
                try {
                    context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                        views.setOnClickPendingIntent(
                            R.id.widget_root,
                            PendingIntent.getActivity(
                                context,
                                0,
                                it,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                            )
                        )
                    }
                } catch (ignored: Exception) {
                }

                manager.updateAppWidget(ids, views)
            } catch (ignored: Exception) {
                // 小组件刷新失败不能崩主进程，维持旧显示即可。
            }
        }

        private fun boundaryPendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                Intent(context, NextClassWidgetProvider::class.java).setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        private fun scheduleBoundaryAlarm(context: Context, atMillis: Long) {
            try {
                val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                if (alarm != null && atMillis > System.currentTimeMillis()) {
                    try {
                        alarm.setExactAndAllowWhileIdle(
                            AlarmManager.RTC, atMillis, boundaryPendingIntent(context)
                        )
                    } catch (error: Exception) {
                        // 没有精确闹钟权限就退化为不精确（小组件晚几分钟换内容可接受）。
                        alarm.set(AlarmManager.RTC, atMillis, boundaryPendingIntent(context))
                    }
                }
            } catch (ignored: Exception) {
            }
        }

        private fun cancelBoundaryAlarm(context: Context) {
            try {
                (context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)
                    ?.cancel(boundaryPendingIntent(context))
            } catch (ignored: Exception) {
            }
        }
    }
}
