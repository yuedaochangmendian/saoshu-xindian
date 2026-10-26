package com.saoshu.saoshu_xindian

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val launcherAliases = listOf(
        "LauncherDefault", "LauncherPhoto", "LauncherBook", "LauncherReading"
    )

    private var pinResult: MethodChannel.Result? = null
    private val pickImageCode = 4201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appVersion" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            result.success(mapOf(
                                "version" to info.versionName,
                                "build" to info.longVersionCode
                            ))
                        } catch (e: Exception) {
                            result.error("unavailable", e.message, null)
                        }
                    }
                    "openUrl" -> {
                        try {
                            val url = call.argument<String>("url")
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("unavailable", e.message, null)
                        }
                    }
                    "setLauncherIcon" -> {
                        try {
                            val target = call.argument<String>("alias")
                                ?: run {
                                    result.error("badArgs", "alias required", null)
                                    return@setMethodCallHandler
                                }
                            val pm = packageManager
                            for (alias in launcherAliases) {
                                val component = ComponentName(
                                    packageName, "com.saoshu.saoshu_xindian.$alias")
                                pm.setComponentEnabledSetting(
                                    component,
                                    if (alias == target)
                                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                                    else
                                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("unavailable", e.message, null)
                        }
                    }
                    "pickImageAndPinShortcut" -> {
                        // Android 无公开 API 用任意位图替换应用图标；
                        // 官方近似 = 打开系统图片选择器，选完后把带自定义
                        // 图标的 pinned 快捷方式钉到桌面（与 app 图标并存）。
                        try {
                            pinResult = result
                            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "image/*"
                            }
                            startActivityForResult(picker, pickImageCode)
                        } catch (e: Exception) {
                            pinResult = null
                            result.error("unavailable", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickImageCode) return
        val pending = pinResult
        pinResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            // 用户取消：返回 null（Dart 侧显示「已取消」）
            pending.success(null)
            return
        }
        try {
            // 两次流式解码（bounds + 实际），采样到 512px 内
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(data.data!!)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            }
            var sample = 1
            while (opts.outWidth / sample > 512 || opts.outHeight / sample > 512) {
                sample *= 2
            }
            opts.inJustDecodeBounds = false
            opts.inSampleSize = sample
            val src = contentResolver.openInputStream(data.data!!)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            } ?: run {
                pending.error("decode", "图片解码失败", null)
                return
            }
            // 居中裁方绘制到白底（launcher 会套自己的圆角蒙版）
            val side = minOf(src.width, src.height)
            val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            canvas.drawBitmap(
                src, (side - src.width) / 2f, (side - src.height) / 2f,
                Paint(Paint.FILTER_BITMAP_FLAG)
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setClassName(packageName, "com.saoshu.saoshu_xindian.MainActivity")
            val shortcut = ShortcutInfoCompat
                .Builder(this, "custom_icon")
                .setShortLabel("扫书新典")
                .setIcon(IconCompat.createWithBitmap(bitmap))
                .setIntent(intent)
                .build()
            val pinned = ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)
            if (pinned) {
                pending.success("pinned")
            } else {
                pending.error("launcher", "当前启动器不支持固定快捷方式", null)
            }
        } catch (e: Exception) {
            pending.error("unavailable", e.message, null)
        }
    }
}
