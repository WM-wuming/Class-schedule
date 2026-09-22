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
 * 「下一节课」桌面小组件 —— 三种尺寸共用一套数据与刷新逻辑：
 * - [NextClassWidgetProvider]：大尺寸（约 4×1 格），四行卡片（状态 / 课程 / 时间 / 地点）；
 * - [NextClassWidgetSmallProvider]：紧凑横条（2 格宽 × 1 格高），两行（课程 / 时间·地点）；
 * - [NextClassWidgetTallProvider]：窄竖条（1 格宽 × 2 格高），一列（状态 / 课程 / 时间 / 地点）。
 *
 * 数据来源是 Flutter 侧算好的 JSON（见 lib/models/next_class.dart，经 MainActivity
 * 写进 `next_class_widget` 这个 SharedPreferences），渲染只做三件事：
 * 1. 挑出第一条「还没下课」的条目显示（正在上的课显示成「正在上课」）；
 * 2. 一条都没有就显示空状态；
 * 3. 在这条课的边界（开课/下课时刻）定个闹钟精准刷新，兜底另有系统 30 分钟一拍的轮询。
 *
 * 三种尺寸显示的是**同一份数据、同一条课**，所以节次闹钟只挂一份
 * （PendingIntent 相同，多处重复排也是幂等的）。
 */
internal object NextClassWidgets {

    const val ACTION_REFRESH = "wm.gykclass.com.WIDGET_NEXT_CLASS_REFRESH"

    private const val PREFS = "next_class_widget"
    private const val KEY_PAYLOAD = "payload"
    private const val ALARM_REQUEST_CODE = 41

    /** 一种尺寸的描述：自己的 Provider 类与布局。 */
    private enum class Variant(
        val provider: Class<out AppWidgetProvider>,
        val layoutId: Int,
    ) {
        BIG(NextClassWidgetProvider::class.java, R.layout.next_class_widget),
        SMALL(NextClassWidgetSmallProvider::class.java, R.layout.next_class_widget_small),
        TALL(NextClassWidgetTallProvider::class.java, R.layout.next_class_widget_tall),
    }

    private val ALL_VARIANTS = listOf(Variant.BIG, Variant.SMALL, Variant.TALL)

    /** 刷新**所有**小组件实例（三种尺寸都算）；App 推新数据与节次闹钟都走这里。 */
    fun updateAll(context: Context) {
        for (variant in ALL_VARIANTS) {
            render(context, variant)
        }
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
    private fun render(context: Context, variant: Variant) {
        try {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, variant.provider))
            if (ids.isEmpty()) return

            val now = System.currentTimeMillis()
            val entries = readEntries(context)
            val current: JSONObject? = entries.firstOrNull {
                it.optLong("end") > now
            }

            val views = RemoteViews(context.packageName, variant.layoutId)
            if (current == null) {
                showEmpty(context, views, variant)
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

                when (variant) {
                    Variant.BIG -> {
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
                    }

                    Variant.SMALL -> {
                        // 紧凑横条没有第几节：状态与日期拼进第二行（上课中 / 明天 …），超宽会省略。
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

                    Variant.TALL -> {
                        // 窄竖条：状态一行（非今天直接显示日期），其余全部允许折行/省略。
                        val status = when {
                            inClass -> "正在上课"
                            day == "今天" -> "下一节"
                            else -> day
                        }
                        val where = listOf(place, teacher)
                            .filter { it.isNotEmpty() }
                            .joinToString(" · ")
                        views.setViewVisibility(R.id.widget_tall_empty, View.GONE)
                        views.setViewVisibility(R.id.widget_tall_content, View.VISIBLE)
                        views.setTextViewText(R.id.widget_tall_status, status)
                        views.setTextViewText(R.id.widget_tall_name, name)
                        views.setViewVisibility(
                            R.id.widget_tall_time,
                            if (time.isEmpty()) View.GONE else View.VISIBLE
                        )
                        views.setTextViewText(R.id.widget_tall_time, time)
                        views.setViewVisibility(
                            R.id.widget_tall_place,
                            if (where.isEmpty()) View.GONE else View.VISIBLE
                        )
                        views.setTextViewText(R.id.widget_tall_place, where)
                    }
                }

                // 没在上课 → 开课那一刻刷新（变「正在上课」）；在上课 → 下课那一刻刷新（换下一节）。
                scheduleBoundaryAlarm(context, if (inClass) end else start)
            }

            // 点组件打开应用。
            try {
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                    views.setOnClickPendingIntent(
                        when (variant) {
                            Variant.BIG -> R.id.widget_root
                            Variant.SMALL -> R.id.widget_small_root
                            Variant.TALL -> R.id.widget_tall_root
                        },
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

    /** 各尺寸的空状态文案与可见性。 */
    private fun showEmpty(context: Context, views: RemoteViews, variant: Variant) {
        when (variant) {
            Variant.BIG -> {
                views.setViewVisibility(R.id.widget_content, View.GONE)
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setTextViewText(R.id.widget_empty, "没有课了\n可以放心玩了！")
            }

            Variant.SMALL -> {
                views.setViewVisibility(R.id.widget_small_content, View.GONE)
                views.setViewVisibility(R.id.widget_small_empty, View.VISIBLE)
            }

            Variant.TALL -> {
                views.setViewVisibility(R.id.widget_tall_content, View.GONE)
                views.setViewVisibility(R.id.widget_tall_empty, View.VISIBLE)
            }
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
        /** App 侧（MainActivity）推新数据后调这里；一次把三种尺寸都刷掉。 */
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

/** 「下一节课」小组件的窄竖条尺寸（1 格宽 × 2 格高，一列）。 */
class NextClassWidgetTallProvider : AppWidgetProvider() {

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
