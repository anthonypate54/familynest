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
import android.util.Log
import android.os.Bundle
import java.io.FileOutputStream
import java.io.InputStream
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import android.content.pm.PackageManager

class MainActivity: FlutterActivity() {
  private val CHANNEL = "com.anthony.familynest/files"
  private val BROWSE_DOCUMENTS_REQUEST = 1001
  private var pendingResult: MethodChannel.Result? = null

  companion object {
    private val PROJECTION = arrayOf(
      MediaStore.MediaColumns._ID,
      MediaStore.MediaColumns.DISPLAY_NAME,
      MediaStore.MediaColumns.SIZE,
      MediaStore.MediaColumns.MIME_TYPE
    )
  }

  private fun hasStoragePermission(): Boolean {
    return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED &&
      ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
    } else {
      ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      if (call.method == "listLocalFiles") {
        // Check storage permissions first
        if (!hasStoragePermission()) {
          ActivityCompat.requestPermissions(
            this,
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
              arrayOf(android.Manifest.permission.READ_MEDIA_IMAGES, android.Manifest.permission.READ_MEDIA_VIDEO)
            } else {
              arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
            },
            100
          )
          result.error("PERMISSION_DENIED", "Storage permissions not granted", null)
          return@setMethodCallHandler
        }

        val type = call.argument<String>("type")
        val maxSizeBytes = call.argument<Long>("maxSizeBytes") ?: (25 * 1024 * 1024)
        val files = mutableListOf<Map<String, Any>>()
        
        val projection = PROJECTION
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
        if (id.isNullOrEmpty()) {
          result.error("INVALID_URI", "Invalid or empty URI", null)
          return@setMethodCallHandler
        }
        val uri = Uri.parse(id)
        contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use {
          if (it.moveToFirst()) {
            val path = it.getString(it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA))
            result.success(path)
          } else {
            result.error("NOT_FOUND", "File not found for URI: $uri", null)
          }
        } ?: result.error("QUERY_FAILED", "Failed to query URI: $uri", null)
        
      } else if (call.method == "browseDocuments") {
        Log.d("MainActivity", "🔍 browseDocuments called")
        pendingResult = result
        Log.d("MainActivity", "🔍 Creating intent")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
          addCategory(Intent.CATEGORY_OPENABLE)
          type = "*/*"
          putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*", "audio/*", "application/pdf", "text/*"))
        }
        Log.d("MainActivity", "🔍 About to call startActivityForResult")
        startActivityForResult(intent, BROWSE_DOCUMENTS_REQUEST)
        Log.d("MainActivity", "🔍 startActivityForResult completed")
        
      } else {
        result.notImplemented()
      }
    }
  }
  
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    Log.d("MainActivity", "🔍 onActivityResult called")
    super.onActivityResult(requestCode, resultCode, data)
    
    if (requestCode == BROWSE_DOCUMENTS_REQUEST) {
      Log.d("MainActivity", "🔍 Processing BROWSE_DOCUMENTS_REQUEST")
      val result = pendingResult
      pendingResult = null
      
      if (resultCode == Activity.RESULT_OK && data?.data != null) {
        val uri = data.data!!
        Log.d("MainActivity", "🔍 File selected: $uri")
        
        // Persist URI permissions for future access
        try {
          contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
          Log.d("MainActivity", "🔍 Persisted URI permission for: $uri")
        } catch (e: Exception) {
          Log.w("MainActivity", "🔍 Could not persist URI permission: ${e.message}")
        }
        
        try {
          Log.d("MainActivity", "🔍 About to call getFileInfoFromUri")
          val fileInfo = getFileInfoFromUri(uri)
          Log.d("MainActivity", "🔍 getFileInfoFromUri completed")
          result?.success(listOf(fileInfo))
          Log.d("MainActivity", "🔍 result.success completed")
        } catch (e: Exception) {
          Log.e("MainActivity", "🔍 Exception in getFileInfoFromUri: ${e.message}", e)
          result?.error("ERROR", "Failed to get file info: ${e.message}", null)
        }
      } else {
        Log.d("MainActivity", "🔍 No file selected or cancelled")
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
        
        // For content URIs, only provide temp file access if size is within limits
        val path = if (uri.scheme == "content") {
          // Copy content URI to temp file (just like FilePicker does)
          copyContentUriToTempFile(uri, name)
        } else {
          getPathFromUri(uri)
        }
        
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
  
  private fun copyContentUriToTempFile(uri: Uri, fileName: String): String? {
    return try {
      Log.d("MainActivity", "📄 Copying content URI to temp cache: $uri")
      
      // Generate unique, sanitized filename to avoid conflicts
      val sanitizedFileName = fileName.replace("[^a-zA-Z0-9.-]".toRegex(), "_")
      val uniqueFileName = "${System.currentTimeMillis()}_$sanitizedFileName"
      val tempFile = File(cacheDir, uniqueFileName)
      
      // Copy content to temp cache
      contentResolver.openInputStream(uri)?.use { inputStream ->
        FileOutputStream(tempFile).use { outputStream ->
          inputStream.copyTo(outputStream)
        }
      }
      
      val tempPath = tempFile.absolutePath
      Log.d("MainActivity", "📄 Content URI copied to temp cache: $tempPath")
      tempPath
    } catch (e: Exception) {
      Log.e("MainActivity", "📄 Error copying content URI: ${e.message}", e)
      null
    }
  }

  private fun getPathFromUri(uri: Uri): String? {
    return try {
      Log.d("MainActivity", "🔍 getPathFromUri called with: $uri")
      if (DocumentsContract.isDocumentUri(this, uri)) {
        Log.d("MainActivity", "🔍 Document URI detected, querying for path")
        // For document URIs, try to get the actual path
        val cursor = contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
        cursor?.use {
          if (it.moveToFirst()) {
            val dataIndex = it.getColumnIndex(MediaStore.MediaColumns.DATA)
            val path = if (dataIndex != -1) it.getString(dataIndex) else null
            Log.d("MainActivity", "🔍 Document URI path: $path")
            path
          } else {
            Log.d("MainActivity", "🔍 Document URI cursor empty")
            null
          }
        }
      } else {
        Log.d("MainActivity", "🔍 Regular URI, using uri.path: ${uri.path}")
        uri.path
      }
    } catch (e: Exception) {
      Log.e("MainActivity", "🔍 Error in getPathFromUri: ${e.message}", e)
      null
    }
  }

  override fun onDestroy() {
    pendingResult = null
    super.onDestroy()
  }
}
