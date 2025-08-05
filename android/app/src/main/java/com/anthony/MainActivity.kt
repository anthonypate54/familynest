package com.anthony.familynest

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentResolver
import android.provider.MediaStore
import android.net.Uri
import java.io.File
import android.content.Intent
import android.app.Activity
import io.flutter.plugin.common.PluginRegistry
import android.provider.DocumentsContract
import android.database.Cursor
import android.provider.OpenableColumns

class MainActivity: FlutterActivity() {
  private val CHANNEL = "com.anthony.familynest/files"
  private val BROWSE_DOCUMENTS_REQUEST = 1001
  private var pendingResult: MethodChannel.Result? = null

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
        
      } else if (call.method == "browseDocuments") {
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
          addCategory(Intent.CATEGORY_OPENABLE)
          type = "*/*"
          putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*", "audio/*", "application/pdf", "text/*"))
        }
        startActivityForResult(intent, BROWSE_DOCUMENTS_REQUEST)
        
      } else {
        result.notImplemented()
      }
    }
  }
  
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    
    if (requestCode == BROWSE_DOCUMENTS_REQUEST) {
      val result = pendingResult
      pendingResult = null
      
      if (resultCode == Activity.RESULT_OK && data?.data != null) {
        val uri = data.data!!
        try {
          val fileInfo = getFileInfoFromUri(uri)
          result?.success(listOf(fileInfo))
        } catch (e: Exception) {
          result?.error("ERROR", "Failed to get file info: ${e.message}", null)
        }
      } else {
        result?.success(emptyList<Map<String, Any>>())
      }
    }
  }
  
  private fun getFileInfoFromUri(uri: Uri): Map<String, Any> {
    val cursor = contentResolver.query(uri, null, null, null, null)
    return cursor?.use {
      if (it.moveToFirst()) {
        val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
        val sizeIndex = it.getColumnIndex(android.provider.OpenableColumns.SIZE)
        
        val name = if (nameIndex != -1) it.getString(nameIndex) else "Unknown"
        val size = if (sizeIndex != -1) it.getLong(sizeIndex) else 0L
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        
        // Get actual file path if possible
        val path = getPathFromUri(uri)
        
        mapOf(
          "id" to uri.toString(),
          "name" to name,
          "size" to size,
          "path" to (path ?: uri.toString()),
          "mimeType" to mimeType,
          "isDirectory" to false
        )
      } else {
        mapOf(
          "id" to uri.toString(),
          "name" to "Unknown",
          "size" to 0L,
          "path" to uri.toString(),
          "mimeType" to "application/octet-stream",
          "isDirectory" to false
        )
      }
    } ?: mapOf(
      "id" to uri.toString(),
      "name" to "Unknown", 
      "size" to 0L,
      "path" to uri.toString(),
      "mimeType" to "application/octet-stream",
      "isDirectory" to false
    )
  }
  
  private fun getPathFromUri(uri: Uri): String? {
    return try {
      if (DocumentsContract.isDocumentUri(this, uri)) {
        // For document URIs, try to get the actual path
        val cursor = contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
        cursor?.use {
          if (it.moveToFirst()) {
            val dataIndex = it.getColumnIndex(MediaStore.MediaColumns.DATA)
            if (dataIndex != -1) it.getString(dataIndex) else null
          } else null
        }
      } else {
        uri.path
      }
    } catch (e: Exception) {
      null
    }
  }
}
