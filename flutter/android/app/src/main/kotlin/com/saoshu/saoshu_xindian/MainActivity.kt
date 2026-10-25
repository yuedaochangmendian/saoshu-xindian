package com.saoshu.saoshu_xindian

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val launcherAliases = listOf(
        "LauncherDefault", "LauncherPhoto", "LauncherBook", "LauncherReading"
    )

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
                    else -> result.notImplemented()
                }
            }
    }
}
