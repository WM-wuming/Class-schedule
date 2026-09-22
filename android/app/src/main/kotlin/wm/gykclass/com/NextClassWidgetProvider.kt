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
 * 「下一节课」桌面小组件 —— 两种尺寸共用一套数据与刷新逻辑：
 * - [NextClassWidgetProvider]：大尺寸（约 4×1 格），四行卡片（状态 / 课程 / 时间 / 地点）；
 * - [NextClassWidgetSmallProvider]：紧凑尺寸（2 格宽 × 1 格高），两行（课程 / 时间·地点）。
 *
 * 数据来源是 Flutter 侧算好的 JSON（见 lib/models/next_class.dart，经 MainActivity
 * 写进 `next_class_widget` 这个 SharedPreferences），渲染只做三件事：
 * 1. 挑出第一条「还没下课」的条目显示（正在上的课显示成「正在上课」）；
 * 2. 一条都没有就显示空状态；
 * 3. 在这条课的边界（开课/下课时刻）定个闹钟精准刷新，兜底另有系统 30 分钟一拍的轮询。
 *
 * 两种尺寸显示的是**同一份数据、同一条课**，所以节次闹钟只挂一份
 * （PendingIntent 相同，两边重复排也是幂等的）。
 */
internal object NextClassWidgets {

    const val ACTION_REFRESH = "wm.gykclass.com.WIDGET_NEXT_CLASS_REFRESH"

    private const val PREFS = "next_class_widget"
    private const val KEY_PAYLOAD = "payload"
    private const val ALARM_REQUEST_CODE = 41

    /** 刷新**所有**小组件实例（两种尺寸都算）；App 推新数据与节次闹钟都走这里。 */
    fun updateAll(context: Context) {
        render(context, big = true)
        render(context, big = false)
    }

    /** 读取 Flutter 推来的数据；任何一步失败都当「没课」处理。 */
    private fun readEntries(context: Context): List<JSONObject> = try {
        val raw = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PAYLOAD, "[]") ?: "[]"
        val array = JSONArray(raw)
        (0 until array.length()).map { array.getJSONObject(it) }
    } catch (error: Exception) {
        emptyList()
    }

    /** 渲染一种尺寸的全部实例；任何一步失败都静默，维持旧显示即可。 */
    private fun render(context: Context, big: Boolean) {
        try {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val provider = if (big) {
                NextClassWidgetProvider::class.java
            } else {
                NextClassWidgetSmallProvider::class.java
            }
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) return

            val now = System.currentTimeMillis()
            val entries = readEntries(context)
            val current: JSONObject? = entries.firstOrNull {
                it.optLong("end") > now
            }

            val views = RemoteViews(
                context.packageName,
                if (big) R.layout.next_class_widget else R.layout.next_class_widget_small
            )
            if (current == null) {
                if (big) {
                    views.setViewVisibility(R.id.widget_content, View.GONE)
                    views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    views.setTextViewText(R.id.widget_empty, "没有课了\n可以放心玩了！")
                } else {
                    views.setViewVisibility(R.id.widget_small_content, View.GONE)
                    views.setViewVisibility(R.id.widget_small_empty, View.VISIBLE)
                }
                cancelBoundaryAlarm(context)
            } else {
                val start = current.optLong("start")
                val end = current.optLong("end")
                val inClass = now >= start
                val day = current.optString("day", "今天")
                val time = current.optString("time", "")
                val period = current.optString("period", "")
                val name = current.optString("name", "")
                val place = current.optString("location", "").trim()
                val teacher = current.optString("teacher", "").trim()

                if (big) {
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
                    views.setTextViewText(R.id.widget_name, name)
                    views.setTextViewText(
                        R.id.widget_time,
                        "$time · $period"
                    )
                    views.setViewVisibility(
                        R.id.widget_place,
                        if (place.isEmpty() && teacher.isEmpty()) View.GONE else View.VISIBLE
                    )
                    views.setTextViewText(
                        R.id.widget_place,
                        listOf(place, teacher).filter { it.isNotEmpty() }.joinToString(" · ")
                    )
                } else {
                    // 紧凑版没有第几节：状态与日期拼进第二行（上课中 / 明天 …），超宽会省略。
                    val where = listOf(place, teacher)
                        .filter { it.isNotEmpty() }
                        .joinToString(" · ")
                    val info = when {
                        inClass -> listOf("上课中", time, where)
                        day == "今天" -> listOf(time, where)
                        else -> listOf(day, time, where)
                    }.filter { it.isNotEmpty() }.joinToString(" · ")
                    views.setViewVisibility(R.id.widget_small_empty, View.GONE)
                    views.setViewVisibility(R.id.widget_small_content, View.VISIBLE)
                    views.setTextViewText(R.id.widget_small_name, name)
                    views.setTextViewText(R.id.widget_small_info, info)
                }

                // 没在上课 → 开课那一刻刷新（变「正在上课」）；在上课 → 下课那一刻刷新（换下一节）。
                scheduleBoundaryAlarm(context, if (inClass) end else start)
            }

            // 点组件打开应用。
            try {
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                    views.setOnClickPendingIntent(
                        if (big) R.id.widget_root else R.id.widget_small_root,
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

/** 「下一节课」小组件的大尺寸（约 4×1 格，四行卡片）。 */
class NextClassWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        NextClassWidgets.updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == NextClassWidgets.ACTION_REFRESH) {
            NextClassWidgets.updateAll(context)
        }
    }

    companion object {
        /** App 侧（MainActivity）推新数据后调这里；一次把两种尺寸都刷掉。 */
        fun updateAll(context: Context) = NextClassWidgets.updateAll(context)
    }
}

/** 「下一节课」小组件的紧凑尺寸（2 格宽 × 1 格高，两行）。 */
class NextClassWidgetSmallProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        NextClassWidgets.updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == NextClassWidgets.ACTION_REFRESH) {
            NextClassWidgets.updateAll(context)
        }
    }
}
