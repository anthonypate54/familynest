package com.anthony.familynest

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentResolver
import android.provider.MediaStore
import android.net.Uri
import java.io.File

class MainActivity: FlutterActivity() {
  private val CHANNEL = "com.anthony.familynest/files"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      if (call.method == "listLocalFiles") {
        val type = call.argument<String>("type")
        val maxSizeBytes = 25 * 1024 * 1024
        val files = mutableListOf<Map<String, Any>>()
        
        val projection = arrayOf(
          MediaStore.MediaColumns._ID,
          MediaStore.MediaColumns.DISPLAY_NAME,
          MediaStore.MediaColumns.SIZE,
          MediaStore.MediaColumns.MIME_TYPE
        )
        val selection = "${MediaStore.MediaColumns.MIME_TYPE} LIKE ?"
        val selectionArgs = arrayOf(if (type == "photo") "image/%" else "video/%")
        
        val cursor = contentResolver.query(
          if (type == "photo") MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
          projection,
          selection,
          selectionArgs,
          null
        )
        
        cursor?.use {
          val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
          val nameColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
          val sizeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
          val mimeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
          
          while (it.moveToNext()) {
            val size = it.getLong(sizeColumn)
            if (size <= maxSizeBytes) {
              val id = it.getLong(idColumn)
              val uri = Uri.withAppendedPath(
                if (type == "photo") MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                id.toString()
              )
              files.add(
                mapOf(
                  "id" to uri.toString(),
                  "name" to it.getString(nameColumn),
                  "size" to size,
                  "path" to uri.toString(),
                  "mimeType" to it.getString(mimeColumn)
                )
              )
            }
          }
        }
        result.success(files)
        
      } else if (call.method == "getLocalFilePath") {
        val id = call.argument<String>("id")
        val uri = Uri.parse(id)
        val cursor = contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
        cursor?.use {
          if (it.moveToFirst()) {
            val path = it.getString(it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA))
            result.success(path)
          } else {
            result.error("NOT_FOUND", "File not found", null)
          }
        } ?: result.error("ERROR", "Query failed", null)
        
      } else {
        result.notImplemented()
      }
    }
  }
}
