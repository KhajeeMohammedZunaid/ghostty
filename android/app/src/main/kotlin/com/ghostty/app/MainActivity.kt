package com.ghostty.app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "ghostty/secure"
    private val MEDIA_CHANNEL = "ghostty/media"
    private val NAVIGATION_CHANNEL = "ghostty/navigation"
    private var navigationMethodChannel: MethodChannel? = null
    private var pendingNavigation: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureMode" -> {
                    enableSecureMode()
                    result.success(null)
                }
                "disableSecureMode" -> {
                    disableSecureMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "notifyMediaDeleted" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        notifyMediaDeleted(path)
                    }
                    result.success(true)
                }
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        scanFileToMediaStore(path, result)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        navigationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAVIGATION_CHANNEL)
        
        pendingNavigation?.let { action ->
            navigationMethodChannel?.invokeMethod("navigate", action)
            pendingNavigation = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableSecureMode()
        handleIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }
    
    private fun handleIntent(intent: Intent?) {
        if (intent?.action == "OPEN_TODO_EDITOR") {
            if (navigationMethodChannel != null) {
                navigationMethodChannel?.invokeMethod("navigate", "open_todo_editor")
            } else {
                pendingNavigation = "open_todo_editor"
            }
        }
    }

    private fun enableSecureMode() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    private fun disableSecureMode() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    
    private fun scanFileToMediaStore(path: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        MediaScannerConnection.scanFile(
            this,
            arrayOf(path),
            null
        ) { _, uri ->
            runOnUiThread {
                result.success(uri != null)
            }
        }
    }
    
    private fun notifyMediaDeleted(path: String) {
        try {
            var uri = queryMediaUri(path, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            if (uri != null) {
                contentResolver.delete(uri, null, null)
                return
            }
            
            uri = queryMediaUri(path, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            if (uri != null) {
                contentResolver.delete(uri, null, null)
            }
        } catch (e: Exception) {}
    }
    
    private fun queryMediaUri(path: String, collection: Uri): Uri? {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DATA} = ?"
        val selectionArgs = arrayOf(path)
        
        contentResolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }
}
