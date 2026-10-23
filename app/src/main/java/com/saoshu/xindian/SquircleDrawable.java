package com.saoshu.xindian;

import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;

/**
 * 超椭圆（squircle）圆角 Drawable，用于 Miuix 主题。
 *
 * <p>与 {@link android.graphics.drawable.GradientDrawable} 的圆形圆角不同，
 * 四个角使用 superellipse 曲线（|x|^0.5 + |y|^0.5 = r^0.5），转角更连续、
 * 更接近 Miuix / HyperOS 的平滑圆角观感。纯 Path 绘制，不依赖系统版本。
 */
public class SquircleDrawable extends Drawable {
    private static final float CORNER_EXPONENT = 0.5f;
    private static final int CORNER_STEPS = 10;

    private final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();
    private final Rect cachedBounds = new Rect();
    private boolean pathValid;
    private final float radiusPx;
    private int fillColor;
    private int strokeColor = 0;
    private float strokeWidth;
    private int alpha = 255;

    public SquircleDrawable(int color, float radiusPx) {
        this.radiusPx = Math.max(0f, radiusPx);
        this.fillColor = color;
        fillPaint.setStyle(Paint.Style.FILL);
        fillPaint.setColor(color);
        strokePaint.setStyle(Paint.Style.STROKE);
    }

    /** 描边宽度与颜色（像素）。 */
    public void setStroke(int widthPx, int color) {
        strokeWidth = Math.max(0, widthPx);
        strokeColor = color;
        strokePaint.setStrokeWidth(strokeWidth);
        strokePaint.setColor(color);
        strokePaint.setAlpha(scaleAlpha(color));
        pathValid = false;
        invalidateSelf();
    }

    @Override
    public void draw(Canvas canvas) {
        Rect bounds = getBounds();
        if (bounds.isEmpty()) {
            return;
        }
        if (!pathValid || !bounds.equals(cachedBounds)) {
            buildPath(bounds);
            cachedBounds.set(bounds);
            pathValid = true;
        }
        canvas.drawPath(path, fillPaint);
        if (strokeWidth > 0f) {
            canvas.drawPath(path, strokePaint);
        }
    }

    private void buildPath(Rect bounds) {
        path.reset();
        float inset = strokeWidth / 2f;
        float left = bounds.left + inset;
        float top = bounds.top + inset;
        float right = bounds.right - inset;
        float bottom = bounds.bottom - inset;
        float width = right - left;
        float height = bottom - top;
        if (width <= 0f || height <= 0f) {
            return;
        }
        float radius = Math.min(radiusPx, Math.min(width, height) / 2f);
        if (radius <= 0.5f) {
            path.addRect(left, top, right, bottom, Path.Direction.CW);
            return;
        }
        path.moveTo(left + radius, top);
        path.lineTo(right - radius, top);
        appendCorner(right - radius, top + radius, radius, -90f, 0f);
        path.lineTo(right, bottom - radius);
        appendCorner(right - radius, bottom - radius, radius, 0f, 90f);
        path.lineTo(left + radius, bottom);
        appendCorner(left + radius, bottom - radius, radius, 90f, 180f);
        path.lineTo(left, top + radius);
        appendCorner(left + radius, top + radius, radius, 180f, 270f);
        path.close();
    }

    /** 以超椭圆参数方程采样一段转角，角度为度，顺时针。 */
    private void appendCorner(float centerX, float centerY, float radius,
                              float startDeg, float endDeg) {
        for (int i = 1; i <= CORNER_STEPS; i++) {
            double angle = Math.toRadians(startDeg + (endDeg - startDeg) * i / CORNER_STEPS);
            float cos = (float) Math.cos(angle);
            float sin = (float) Math.sin(angle);
            float x = centerX + radius * signedPow(cos);
            float y = centerY + radius * signedPow(sin);
            path.lineTo(x, y);
        }
    }

    private static float signedPow(float value) {
        float magnitude = (float) Math.pow(Math.abs(value), CORNER_EXPONENT);
        return value < 0f ? -magnitude : magnitude;
    }

    private int scaleAlpha(int color) {
        return alpha * android.graphics.Color.alpha(color) / 255;
    }

    @Override
    public void setAlpha(int alpha) {
        this.alpha = alpha;
        fillPaint.setAlpha(scaleAlpha(fillColor));
        strokePaint.setAlpha(scaleAlpha(strokeColor));
        invalidateSelf();
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {
        fillPaint.setColorFilter(colorFilter);
        strokePaint.setColorFilter(colorFilter);
        invalidateSelf();
    }

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }
}
