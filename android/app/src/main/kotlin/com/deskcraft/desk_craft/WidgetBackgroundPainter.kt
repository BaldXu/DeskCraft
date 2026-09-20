package com.deskcraft.desk_craft

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader

/**
 * widget 背景 Bitmap 绘制器：纯色 / 预置渐变 / 本地图片（cover 中心裁剪）
 * + G2 连续曲率圆角（squircle）。数字时钟与系统监控组件共用，保证观感一致。
 */
object WidgetBackgroundPainter {

    /** 与 lib/models/clock_config.dart 的 kGradients 严格一一对应。 */
    private val GRADIENTS = arrayOf(
        intArrayOf(0xFF1A1B2E.toInt(), 0xFF4A3B78.toInt()),
        intArrayOf(0xFF0F2027.toInt(), 0xFF2C5364.toInt()),
        intArrayOf(0xFF2F0743.toInt(), 0xFF41295A.toInt()),
        intArrayOf(0xFF232526.toInt(), 0xFF414345.toInt()),
    )

    private const val MAX_CORNER_DP = 120
    private const val MAX_BITMAP_PX = 4096

    /**
     * 绘制 widget 背景。
     * [scale] 为相对 4×2 基准的等比缩放系数，圆角随之缩放；
     * [bgStyle] 取 "solid" / "gradient" / "image"，图片缺失或解码失败回落纯色。
     */
    fun build(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        bgStyle: String,
        bgColor: Int,
        bgGradientIndex: Int,
        bgImagePath: String,
        cornerRadiusDp: Int,
        scale: Float,
    ): Bitmap {
        val width = widthPx.coerceIn(1, MAX_BITMAP_PX)
        val height = heightPx.coerceIn(1, MAX_BITMAP_PX)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        when {
            bgStyle == "image" && bgImagePath.isNotBlank() -> {
                val cover = decodeCoverBitmap(bgImagePath, width, height)
                if (cover != null) {
                    // BitmapShader + drawPath：抗锯齿圆角，且图片已按 cover 裁剪
                    paint.shader = BitmapShader(
                        cover,
                        Shader.TileMode.CLAMP,
                        Shader.TileMode.CLAMP,
                    )
                } else {
                    paint.color = bgColor
                }
            }
            bgStyle == "gradient" -> {
                val colors = GRADIENTS[bgGradientIndex.coerceIn(0, GRADIENTS.lastIndex)]
                paint.shader = LinearGradient(
                    0f, 0f, width.toFloat(), 0f,
                    colors[0], colors[1],
                    Shader.TileMode.CLAMP,
                )
            }
            else -> paint.color = bgColor
        }
        // 圆角随缩放系数调整，并限制不超过短边一半
        val density = context.resources.displayMetrics.density
        val radius = (cornerRadiusDp.coerceIn(0, MAX_CORNER_DP) * scale * density)
            .coerceAtMost(minOf(width, height) / 2f)
        canvas.drawPath(smoothCornerPath(width, height, radius), paint)
        return bitmap
    }

    /**
     * G2 连续曲率圆角路径（squircle）：每个角一条三次贝塞尔，
     * 两个控制点都在角点上，切点距角 r——曲线在衔接直线处曲率为 0，
     * 与 Flutter ContinuousRectangleBorder（预览）同一算法，观感一致。
     */
    fun smoothCornerPath(width: Int, height: Int, radius: Float): Path {
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
}
