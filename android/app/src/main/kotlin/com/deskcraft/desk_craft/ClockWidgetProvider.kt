package com.deskcraft.desk_craft

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 数字时钟 widget（M3）。
 *
 * Flutter 侧把 [ClockConfig] 序列化为 JSON 经 home_widget 写入
 * SharedPreferences（key 见 [KEY_CONFIG_JSON]），本 Provider 解析后渲染：
 *
 * - 背景：纯色 / 预置渐变（与 Dart kGradients 一一对应）/ 本地图片
 *   （中心裁剪 cover，不拉伸）+ 任意圆角，绘制成 Bitmap 塞进 widget_bg，
 *   与 Flutter 预览逐像素对齐；
 * - 时间：TextClock 零功耗走时；显示秒时格式带 ss（秒级自刷新），
 *   不显示秒时为分钟级自刷新，无需额外调度；
 * - 日期 / 星期 / 附加文案：按开关显示隐藏，颜色随文字色分层降透明度；
 * - 尺寸自适应：字号 / 内边距 / 圆角按 widget 实际尺寸相对默认 4×2
 *   基准等比缩放，缩放后观感与 App 内预览一致。
 */
class ClockWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val config = ClockNativeConfig.from(widgetData.getString(KEY_CONFIG_JSON, null))
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, appWidgetManager, appWidgetId, config),
            )
        }
    }

    /** 桌面拖拽 / 调整尺寸时按新尺寸重绘背景。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    private fun buildViews(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        config: ClockNativeConfig,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.clock_widget)

        // widget 实际尺寸 + 相对默认 4×2 基准的等比缩放系数
        val size = widgetSizePx(context, appWidgetManager, appWidgetId)
        val density = context.resources.displayMetrics.density
        val scale = renderScale(size[0], size[1], density)

        // 背景 Bitmap：按当前 widget 实际尺寸绘制，保证圆角不变形
        views.setImageViewBitmap(R.id.widget_bg, buildBackground(context, size[0], size[1], config, scale))

        // 内边距随缩放系数调整（覆盖 XML 首帧兜底值）
        val padH = (H_PADDING_DP * scale * density).toInt()
        val padV = (V_PADDING_DP * scale * density).toInt()
        views.setViewPadding(R.id.widget_content, padH, padV, padH, padV)

        // 内容块水平对齐：居左 / 居中（时间 + 日期 + 附加整体）
        val gravity = if (config.timeAlign == "center") {
            Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL
        } else {
            Gravity.START or Gravity.CENTER_VERTICAL
        }
        views.setInt(R.id.widget_content, "setGravity", gravity)

        // 时间：字号（随缩放）/ 颜色 / 走时格式（秒开关决定刷新频率）
        views.setTextViewTextSize(
            R.id.widget_time,
            TypedValue.COMPLEX_UNIT_SP,
            (config.timeSizeSp * scale).coerceIn(MIN_TIME_SP, MAX_TIME_SP),
        )
        views.setTextColor(R.id.widget_time, config.textColor)
        val seconds = if (config.showSeconds) ":ss" else ""
        val timeFormat = if (config.use24h) "HH:mm$seconds" else "a h:mm$seconds"
        // 注意：MIUI 桌面用 HomeMIUIWidgetTextClock 替换 TextClock，
        // setString(String 签名) 反射查不到方法会抛 ActionException 导致整个
        // widget 加载失败，必须用 setCharSequence（CharSequence 签名）。
        views.setCharSequence(R.id.widget_time, "setFormat24Hour", timeFormat)
        views.setCharSequence(R.id.widget_time, "setFormat12Hour", timeFormat)

        // 日期 + 星期：按开关拼格式，全关则隐藏；字号随缩放
        val dateFormat = when {
            config.showDate && config.showWeekday -> "M月d日 EEEE"
            config.showDate -> "M月d日"
            config.showWeekday -> "EEEE"
            else -> null
        }
        if (dateFormat == null) {
            views.setViewVisibility(R.id.widget_date, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_date, View.VISIBLE)
            views.setCharSequence(R.id.widget_date, "setFormat24Hour", dateFormat)
            views.setCharSequence(R.id.widget_date, "setFormat12Hour", dateFormat)
            views.setTextColor(R.id.widget_date, withAlpha(config.textColor, DATE_ALPHA))
            views.setTextViewTextSize(
                R.id.widget_date,
                TypedValue.COMPLEX_UNIT_SP,
                (DATE_SIZE_SP * scale).coerceIn(8f, 32f),
            )
        }

        // 附加文案：留空则隐藏；字号随缩放
        if (config.extraText.isBlank()) {
            views.setViewVisibility(R.id.widget_extra, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_extra, View.VISIBLE)
            views.setTextViewText(R.id.widget_extra, config.extraText)
            views.setTextColor(R.id.widget_extra, withAlpha(config.textColor, EXTRA_ALPHA))
            views.setTextViewTextSize(
                R.id.widget_extra,
                TypedValue.COMPLEX_UNIT_SP,
                (EXTRA_SIZE_SP * scale).coerceIn(7f, 28f),
            )
        }

        // 点击整个组件回到 App
        views.setOnClickPendingIntent(R.id.widget_root, launchAppPendingIntent(context))
        return views
    }

    /** widget 当前尺寸（px），取自 AppWidgetOptions 的 dp 值换算。 */
    private fun widgetSizePx(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): IntArray {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val density = context.resources.displayMetrics.density
        // 竖屏语义：MIN_WIDTH = 宽，MAX_HEIGHT = 高；未上报时按默认 4×2 兜底
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, REF_WIDTH_DP.toInt())
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, REF_HEIGHT_DP.toInt())
        return intArrayOf(
            (widthDp.coerceAtLeast(40) * density).toInt(),
            (heightDp.coerceAtLeast(40) * density).toInt(),
        )
    }

    /**
     * 相对默认 4×2 基准（[REF_WIDTH_DP]×[REF_HEIGHT_DP] dp）的等比缩放系数，
     * 取宽高缩放的较小值（保证都能放下），限制在合理区间。
     */
    private fun renderScale(widthPx: Int, heightPx: Int, density: Float): Float {
        val widthDp = widthPx / density
        val heightDp = heightPx / density
        val scale = minOf(widthDp / REF_WIDTH_DP, heightDp / REF_HEIGHT_DP)
        return scale.coerceIn(MIN_SCALE, MAX_SCALE)
    }

    /** 纯色 / 渐变 / 图片（中心裁剪 cover 不拉伸）+ 圆角背景，与 Flutter 预览一致。 */
    private fun buildBackground(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        config: ClockNativeConfig,
        scale: Float,
    ): Bitmap {
        val width = widthPx.coerceIn(1, MAX_BITMAP_PX)
        val height = heightPx.coerceIn(1, MAX_BITMAP_PX)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        when {
            config.bgStyle == "image" && config.bgImagePath.isNotBlank() -> {
                val cover = decodeCoverBitmap(config.bgImagePath, width, height)
                if (cover != null) {
                    // BitmapShader + drawRoundRect：抗锯齿圆角，且图片已按 cover 裁剪
                    paint.shader = BitmapShader(
                        cover,
                        Shader.TileMode.CLAMP,
                        Shader.TileMode.CLAMP,
                    )
                } else {
                    // 图片解码失败时回落到配置纯色
                    paint.color = config.bgColor
                }
            }
            config.bgStyle == "gradient" -> {
                val colors = GRADIENTS[config.bgGradientIndex.coerceIn(0, GRADIENTS.lastIndex)]
                paint.shader = LinearGradient(
                    0f, 0f, width.toFloat(), 0f,
                    colors[0], colors[1],
                    Shader.TileMode.CLAMP,
                )
            }
            else -> paint.color = config.bgColor
        }
        // 圆角随缩放系数调整，并限制不超过短边一半
        val density = context.resources.displayMetrics.density
        val radius = (config.cornerRadiusDp.coerceIn(0, MAX_CORNER_DP) * scale * density)
            .coerceAtMost(minOf(width, height) / 2f)
        canvas.drawPath(smoothCornerPath(width, height, radius), paint)
        return bitmap
    }

    /**
     * G2 连续曲率圆角路径（squircle）：每个角一条三次贝塞尔，
     * 两个控制点都在角点上，切点距角 r——曲线在衔接直线处曲率为 0，
     * 与 Flutter ContinuousRectangleBorder（预览）同一算法，观感一致。
     */
    private fun smoothCornerPath(width: Int, height: Int, radius: Float): Path {
        val r = radius.coerceIn(0f, minOf(width, height) / 2f)
        val w = width.toFloat()
        val h = height.toFloat()
        return Path().apply {
            moveTo(0f, r)
            cubicTo(0f, 0f, 0f, 0f, r, 0f)          // 左上角
            lineTo(w - r, 0f)
            cubicTo(w, 0f, w, 0f, w, r)             // 右上角
            lineTo(w, h - r)
            cubicTo(w, h, w, h, w - r, h)           // 右下角
            lineTo(r, h)
            cubicTo(0f, h, 0f, h, 0f, h - r)        // 左下角
            close()
        }
    }

    /**
     * 从本地路径解码图片并按 [width]×[height] 中心裁剪（cover，不拉伸变形）。
     * 先按目标尺寸算 inSampleSize 防大图 OOM，再等比放大后裁掉多余边缘。
     */
    private fun decodeCoverBitmap(path: String, width: Int, height: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= width && bounds.outHeight / (sample * 2) >= height) {
            sample *= 2
        }
        val src = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null
        val scale = maxOf(width.toFloat() / src.width, height.toFloat() / src.height)
        val scaledW = (src.width * scale + 0.5f).toInt().coerceAtLeast(width)
        val scaledH = (src.height * scale + 0.5f).toInt().coerceAtLeast(height)
        val scaled = Bitmap.createScaledBitmap(src, scaledW, scaledH, true)
        if (scaled != src) src.recycle()
        val x = ((scaledW - width) / 2f).toInt().coerceIn(0, scaledW - width)
        val y = ((scaledH - height) / 2f).toInt().coerceIn(0, scaledH - height)
        return try {
            Bitmap.createBitmap(scaled, x, y, width, height)
        } catch (_: IllegalArgumentException) {
            scaled
        }
    }

    private fun withAlpha(color: Int, alpha: Float): Int =
        (color and 0x00FFFFFF) or ((alpha * 255).toInt() shl 24)

    private fun launchAppPendingIntent(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        /** home_widget 托管 SharedPreferences 里的配置 JSON key（与 ClockConfigStore 对齐）。 */
        const val KEY_CONFIG_JSON = "clock_config_json"

        private const val DATE_ALPHA = 0.78f
        private const val EXTRA_ALPHA = 0.58f
        private const val MIN_TIME_SP = 12f
        private const val MAX_TIME_SP = 180f
        private const val MAX_CORNER_DP = 120
        private const val MAX_BITMAP_PX = 4096

        /** 默认 4×2 尺寸基准（dp），预览与原生共用同一排版数值。 */
        private const val REF_WIDTH_DP = 250f
        private const val REF_HEIGHT_DP = 110f

        /** 缩放系数上下限：过小时文字不可读，过大时撑爆布局。 */
        private const val MIN_SCALE = 0.35f
        private const val MAX_SCALE = 2f

        /** 与 layout/Flutter 预览对齐的基础排版数值（scale == 1 时的值）。 */
        private const val H_PADDING_DP = 16f
        private const val V_PADDING_DP = 10f
        private const val DATE_SIZE_SP = 13f
        private const val EXTRA_SIZE_SP = 11f

        /** 与 lib/models/clock_config.dart 的 kGradients 严格一一对应。 */
        private val GRADIENTS = arrayOf(
            intArrayOf(0xFF1A1B2E.toInt(), 0xFF4A3B78.toInt()),
            intArrayOf(0xFF0F2027.toInt(), 0xFF2C5364.toInt()),
            intArrayOf(0xFF2F0743.toInt(), 0xFF41295A.toInt()),
            intArrayOf(0xFF232526.toInt(), 0xFF414345.toInt()),
        )
    }
}

/**
 * 原生侧配置镜像：从 JSON 宽松解析，缺字段 / 解析失败一律回落到
 * 与 Dart [ClockConfig] 构造默认值一致的 [ClockNativeConfig.DEFAULT]。
 */
private data class ClockNativeConfig(
    val textColor: Int,
    val bgStyle: String,
    val bgColor: Int,
    val bgGradientIndex: Int,
    val bgImagePath: String,
    val cornerRadiusDp: Int,
    val timeSizeSp: Int,
    val timeAlign: String,
    val use24h: Boolean,
    val showSeconds: Boolean,
    val showDate: Boolean,
    val showWeekday: Boolean,
    val extraText: String,
) {
    companion object {
        val DEFAULT = ClockNativeConfig(
            textColor = 0xFFFFFFFF.toInt(),
            bgStyle = "solid",
            bgColor = 0xE61C1C22.toInt(),
            bgGradientIndex = 0,
            bgImagePath = "",
            cornerRadiusDp = 22,
            timeSizeSp = 38,
            timeAlign = "left",
            use24h = true,
            showSeconds = false,
            showDate = true,
            showWeekday = true,
            extraText = "DeskCraft - M1",
        )

        fun from(raw: String?): ClockNativeConfig {
            if (raw.isNullOrBlank()) return DEFAULT
            return try {
                val json = JSONObject(raw)
                ClockNativeConfig(
                    textColor = json.optLong("textColor", DEFAULT.textColor.toLong()).toInt(),
                    bgStyle = json.optString("bgStyle", "solid"),
                    bgColor = json.optLong("bgColor", DEFAULT.bgColor.toLong()).toInt(),
                    bgGradientIndex = json.optInt("bgGradientIndex", DEFAULT.bgGradientIndex),
                    bgImagePath = json.optString("bgImagePath", DEFAULT.bgImagePath),
                    cornerRadiusDp = json.optInt("cornerRadiusDp", DEFAULT.cornerRadiusDp),
                    timeSizeSp = json.optInt("timeSizeSp", DEFAULT.timeSizeSp),
                    timeAlign = json.optString("timeAlign", DEFAULT.timeAlign),
                    use24h = json.optBoolean("use24h", DEFAULT.use24h),
                    showSeconds = json.optBoolean("showSeconds", DEFAULT.showSeconds),
                    showDate = json.optBoolean("showDate", DEFAULT.showDate),
                    showWeekday = json.optBoolean("showWeekday", DEFAULT.showWeekday),
                    extraText = json.optString("extraText", DEFAULT.extraText),
                )
            } catch (_: Exception) {
                DEFAULT
            }
        }
    }
}
