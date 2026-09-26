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
import java.util.Calendar

/**
 * 「下一节课」桌面小组件 —— 四种尺寸共用一套数据与刷新逻辑：
 * - [NextClassWidgetProvider]：大尺寸（约 4×2 格），四行卡片（状态 / 课程 / 时间 / 地点）；
 * - [NextClassWidgetSquareProvider]：2×2 格 —— **信息展示的主要参考版式**，四行完整信息；
 * - [NextClassWidgetSmallProvider]：紧凑横条（2 格宽 × 1 格高），两行装下同一套信息
 *   （第一行 = 课程名 + 状态·日期，第二行 = 时间·节次·地点·老师）；
 * - [NextClassWidgetTallProvider]：窄竖条（1 格宽 × 2 格高），一列（状态 / 课程 / 时间·节次 / 地点·老师）。
 *
 * 数据来源是 Flutter 侧算好的 JSON（见 lib/models/next_class.dart，经 MainActivity
 * 写进 `next_class_widget` 这个 SharedPreferences），渲染只做三件事：
 * 1. 挑出第一条「还没下课」的条目；
 * 2. 它是**今天**的就显示它（正在上的课显示成「正在上课」）；落在别的日子就说明今天
 *    没课了 —— 只显示「今天没有课了」提示，不把明天的课提前摆上来
 *    （「是不是今天」按本机日历现算，所以数据放旧了也不会把明天的课显示成今天的）；
 * 3. 在这条课的边界（开课/下课时刻）定个闹钟精准刷新，兜底另有系统 30 分钟一拍的轮询。
 *
 * 各尺寸显示的是**同一份数据、同一条课、同一套完整信息**（2×2 的版式是参考基准，
 * 其余尺寸只是把同样的字段重新排进自己的空间），
 * 所以节次闹钟只挂一份（PendingIntent 相同，多处重复排也是幂等的）。
 */
internal object NextClassWidgets {

    const val ACTION_REFRESH = "wm.gykclass.com.WIDGET_NEXT_CLASS_REFRESH"

    private const val PREFS = "next_class_widget"
    private const val KEY_PAYLOAD = "payload"
    private const val ALARM_REQUEST_CODE = 41

    /** 内容版式：大卡与 2×2 共用（连视图 id 都同套），横条与竖条把同一套信息重排进各自空间。 */
    private enum class Style { CARD, COMPACT, COLUMN }

    /** 一种尺寸的描述：自己的 Provider 类、布局与内容版式。 */
    private enum class Variant(
        val provider: Class<out AppWidgetProvider>,
        val layoutId: Int,
        val style: Style,
    ) {
        BIG(NextClassWidgetProvider::class.java, R.layout.next_class_widget, Style.CARD),
        SQUARE(NextClassWidgetSquareProvider::class.java, R.layout.next_class_widget_square, Style.CARD),
        SMALL(NextClassWidgetSmallProvider::class.java, R.layout.next_class_widget_small, Style.COMPACT),
        TALL(NextClassWidgetTallProvider::class.java, R.layout.next_class_widget_tall, Style.COLUMN),
    }

    private val ALL_VARIANTS = listOf(
        Variant.BIG, Variant.SQUARE, Variant.SMALL, Variant.TALL
    )

    /** 刷新**所有**小组件实例（四种尺寸都算）；App 推新数据与节次闹钟都走这里。 */
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
                // 数据里一条「还没下课」的都没有：假期，或者后面几天确实没课。
                showEmpty(views, variant, todayFree = false)
                cancelBoundaryAlarm(context)
            } else if (!isSameDay(current.optLong("start"), now)) {
                // 今天没课了、但后面几天还有课：只给「今天没有课了」提示，
                // 不把明天的课提前摆上来（用户要的是无课提示，不是明天的课）。
                showEmpty(views, variant, todayFree = true)
                // 明天零点先翻一次页（明天的课要在零点就顶上来），再到那一节开课的
                // 时刻刷成「正在上课」—— 取两个时刻里更早的那个。
                scheduleBoundaryAlarm(
                    context,
                    minOf(current.optLong("start"), startOfNextDay(now))
                )
            } else {
                val start = current.optLong("start")
                val end = current.optLong("end")
                val inClass = now >= start
                val time = current.optString("time", "")
                val period = current.optString("period", "")
                val name = current.optString("name", "")
                val place = current.optString("location", "").trim()
                val teacher = current.optString("teacher", "").trim()

                when (variant.style) {
                    Style.CARD -> {
                        // 大卡与 2×2 的完整信息版式：状态+日期 / 课程 / 时间·节次 / 地点·老师。
                        views.setViewVisibility(R.id.widget_empty, View.GONE)
                        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
                        views.setTextViewText(
                            R.id.widget_header,
                            if (inClass) "正在上课" else "下一节课"
                        )
                        // 能走到这里的一定是今天的课：是不是今天由原生按日历判定。
                        views.setTextViewText(R.id.widget_day, "今天")
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

                    Style.COMPACT -> {
                        // 横条两行装下与 2×2 相同的信息集：
                        // 第一行 = 课程名 + 状态·日期，第二行 = 时间·节次·地点·老师（超宽省略尾部）。
                        val status = if (inClass) "正在上课" else "下一节"
                        val statusLine = listOf(status, "今天")
                            .filter { it.isNotEmpty() }
                            .joinToString(" · ")
                        val where = listOf(place, teacher)
                            .filter { it.isNotEmpty() }
                            .joinToString(" · ")
                        val info = listOf(time, period, where)
                            .filter { it.isNotEmpty() }
                            .joinToString(" · ")
                        views.setViewVisibility(R.id.widget_small_empty, View.GONE)
                        views.setViewVisibility(R.id.widget_small_content, View.VISIBLE)
                        views.setTextViewText(R.id.widget_small_status, statusLine)
                        views.setTextViewText(R.id.widget_small_name, name)
                        views.setTextViewText(R.id.widget_small_info, info)
                    }

                    Style.COLUMN -> {
                        // 窄竖条：状态一行（显示的一定是今天的课），其余全部允许折行/省略。
                        val status = if (inClass) "正在上课" else "下一节"
                        val where = listOf(place, teacher)
                            .filter { it.isNotEmpty() }
                            .joinToString(" · ")
                        val timeLine = listOf(time, period)
                            .filter { it.isNotEmpty() }
                            .joinToString(" · ")
                        views.setViewVisibility(R.id.widget_tall_empty, View.GONE)
                        views.setViewVisibility(R.id.widget_tall_content, View.VISIBLE)
                        views.setTextViewText(R.id.widget_tall_status, status)
                        views.setTextViewText(R.id.widget_tall_name, name)
                        views.setViewVisibility(
                            R.id.widget_tall_time,
                            if (timeLine.isEmpty()) View.GONE else View.VISIBLE
                        )
                        views.setTextViewText(R.id.widget_tall_time, timeLine)
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
                        when (variant.style) {
                            Style.CARD -> R.id.widget_root
                            Style.COMPACT -> R.id.widget_small_root
                            Style.COLUMN -> R.id.widget_tall_root
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

    /**
     * 各版式的空状态文案与可见性。
     *
     * [todayFree] = 今天没课了、后面几天还有课 —— 提示只针对今天，别写成「没有课了」，
     * 免得用户以为这周都放假了；false 才是「数据里后面几天都没课」（假期）。窄的两种
     * 尺寸塞不下第二行，只说「今天没有课了」。
     */
    private fun showEmpty(views: RemoteViews, variant: Variant, todayFree: Boolean) {
        when (variant.style) {
            Style.CARD -> {
                views.setViewVisibility(R.id.widget_content, View.GONE)
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_empty,
                    if (todayFree) "今天没有课了\n可以放心玩了！" else "没有课了\n可以放心玩了！"
                )
            }

            Style.COMPACT -> {
                views.setViewVisibility(R.id.widget_small_content, View.GONE)
                views.setViewVisibility(R.id.widget_small_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_small_empty,
                    if (todayFree) "今天没有课了" else "没有课了"
                )
            }

            Style.COLUMN -> {
                views.setViewVisibility(R.id.widget_tall_content, View.GONE)
                views.setViewVisibility(R.id.widget_tall_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_tall_empty,
                    if (todayFree) "今天没有课了" else "没有课了"
                )
            }
        }
    }

    /** [millis] 和 [now] 是不是本机的同一天 —— 用来判断「下一节课是不是今天的」。 */
    private fun isSameDay(millis: Long, now: Long): Boolean {
        val target = Calendar.getInstance().apply { timeInMillis = millis }
        val today = Calendar.getInstance().apply { timeInMillis = now }
        return target.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
            target.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
    }

    /** 本机时区下「明天零点」的时刻 —— 今天没课时，靠它在零点把日界翻准。 */
    private fun startOfNextDay(now: Long): Long = Calendar.getInstance().apply {
        timeInMillis = now
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

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

/** 「下一节课」小组件的大尺寸（约 4×2 格，四行卡片）。 */
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
        /** App 侧（MainActivity）推新数据后调这里；一次把四种尺寸都刷掉。 */
        fun updateAll(context: Context) = NextClassWidgets.updateAll(context)
    }
}

/** 「下一节课」小组件的 2×2 尺寸 —— 信息展示的主要参考版式（与大卡共用渲染分支）。 */
class NextClassWidgetSquareProvider : AppWidgetProvider() {

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
