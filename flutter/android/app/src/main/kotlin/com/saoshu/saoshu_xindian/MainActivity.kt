package com.saoshu.saoshu_xindian

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import java.io.File
import java.io.IOException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.provider.MediaStore
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

    // saveToDownloads 在 API<29 需要 WRITE_EXTERNAL_STORAGE 运行时授权
    private var saveResult: MethodChannel.Result? = null
    private var pendingSave: Pair<String, ByteArray>? = null
    private val savePermCode = 4301

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
                    "saveToDownloads" -> {
                        // 写入系统「下载」公共目录（子目录 扫书新典），
                        // 卸载应用/清除数据都不丢。API 29+ 走 MediaStore
                        // （无需权限）；更旧版本直接写文件路径。
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name == null || bytes == null) {
                            result.error("badArgs", "name/bytes required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val values = ContentValues().apply {
                                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                                    put(
                                        MediaStore.Downloads.MIME_TYPE,
                                        "application/json"
                                    )
                                    put(
                                        MediaStore.Downloads.RELATIVE_PATH,
                                        Environment.DIRECTORY_DOWNLOADS + "/扫书新典"
                                    )
                                }
                                // 先清同名旧文件，避免 MediaStore 自动改名 (1)
                                val resolver = contentResolver
                                val existing = resolver.query(
                                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                    arrayOf(MediaStore.MediaColumns._ID),
                                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                                        "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                                    arrayOf(name, "%扫书新典%"),
                                    null
                                )
                                existing?.use { cursor ->
                                    while (cursor.moveToNext()) {
                                        val id = cursor.getLong(0)
                                        resolver.delete(
                                            android.content.ContentUris
                                                .withAppendedId(
                                                    MediaStore.Downloads
                                                        .EXTERNAL_CONTENT_URI, id
                                                ),
                                            null, null
                                        )
                                    }
                                }
                                val uri = resolver.insert(
                                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                    values
                                ) ?: throw IOException("MediaStore 插入失败")
                                resolver.openOutputStream(uri)?.use {
                                    it.write(bytes)
                                } ?: throw IOException("无法打开输出流")
                                result.success(
                                    Environment.DIRECTORY_DOWNLOADS + "/扫书新典/$name"
                                )
                            } else {
                                // API 24-28：需运行时写外部存储权限——先请求，
                                // 授权回调里完成写入，拒绝才报错（旧实现无权限
                                // 直接写，必然静默失败）。
                                if (checkSelfPermission(
                                        Manifest.permission.WRITE_EXTERNAL_STORAGE
                                    ) != PackageManager.PERMISSION_GRANTED
                                ) {
                                    saveResult = result
                                    pendingSave = name to bytes
                                    requestPermissions(
                                        arrayOf(
                                            Manifest.permission
                                                .WRITE_EXTERNAL_STORAGE
                                        ),
                                        savePermCode
                                    )
                                    return@setMethodCallHandler
                                }
                                legacyWriteToDownloads(name, bytes, result)
                            }
                        } catch (e: Exception) {
                            result.error("unavailable", e.message, null)
                        }
                    }
                    "clearTiebaCookies" -> {
                        // 退出登录必须连 WebView CookieManager 一起清：
                        // 否则再进登录页会被旧 BDUSS 立刻判定"已登录"，
                        // 用户表现为"退出登录失败"。
                        try {
                            val cm = android.webkit.CookieManager.getInstance()
                            // removeAllCookies 已含会话 cookie（API 35
                            // 移除了 removeSessionCookies 无参重载）
                            cm.removeAllCookies(null)
                            cm.flush()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("unavailable", e.message, null)
                        }
                    }
                    "getTiebaCookies" -> {
                        // WebView 的 cookie 存在系统 CookieManager 里，
                        // document.cookie 读不到 HttpOnly 的 BDUSS/STOKEN，
                        // 只能从这里取。
                        try {
                            val url = call.argument<String>("url")
                                ?: "https://tieba.baidu.com/"
                            val cookie = android.webkit.CookieManager
                                .getInstance().getCookie(url)
                            result.success(cookie)
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
private fun legacyWriteToDownloads(
        name: String,
        bytes: ByteArray,
        result: MethodChannel.Result
    ) {
        try {
            @Suppress("DEPRECATION")
            val base = Environment.getExternalStorageDirectory()
            val dir = File(base, "Download/扫书新典")
            if (!dir.exists() && !dir.mkdirs()) {
                throw IOException("无法创建目录 ${dir.path}")
            }
            File(dir, name).writeBytes(bytes)
            result.success(dir.absolutePath + "/" + name)
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != savePermCode) return
        val pending = saveResult
        val payload = pendingSave
        saveResult = null
        pendingSave = null
        if (pending == null || payload == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            legacyWriteToDownloads(payload.first, payload.second, pending)
        } else {
            pending.error(
                "permission",
                "未授予存储权限，无法写入公共 Download 目录",
                null
            )
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
