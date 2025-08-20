import Flutter
import UIKit
import Photos
import MobileCoreServices

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.anthony.familynest/files", binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler { (call, result) in
      if call.method == "listLocalFiles" {
        guard let args = call.arguments as? [String: Any],
              let type = args["type"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
          guard status == .authorized else {
            result(FlutterError(code: "PERMISSION_DENIED", message: "Photos access denied", details: nil))
            return
          }
          
          let fetchOptions = PHFetchOptions()
          let assetType = type == "photo" ? PHAssetMediaType.image : PHAssetMediaType.video
          fetchOptions.predicate = NSPredicate(format: "mediaType == %ld", assetType.rawValue)
          let assets = PHAsset.fetchAssets(with: fetchOptions)
          
          var files: [[String: Any]] = []
          let maxSizeBytes = 25 * 1024 * 1024
          
          let imageManager = PHImageManager.default()
          let thumbnailSize = CGSize(width: 150, height: 150)
          let options = PHImageRequestOptions()
          options.deliveryMode = .fastFormat
          options.isSynchronous = true
          
          assets.enumerateObjects { (asset, _, _) in
            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first {
              // Generate thumbnail for this asset
              var thumbnailPath: String? = nil
              
              imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: options) { (image, _) in
                if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
                  // Save thumbnail to temp directory
                  let tempDir = FileManager.default.temporaryDirectory
                  let thumbnailFileName = "thumb_\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_")).jpg"
                  let thumbnailURL = tempDir.appendingPathComponent(thumbnailFileName)
                  
                  do {
                    try imageData.write(to: thumbnailURL)
                    thumbnailPath = thumbnailURL.path
                    print("✅ Saved thumbnail: \(thumbnailPath!)")
                  } catch {
                    print("❌ Error saving thumbnail: \(error)")
                  }
                } else {
                  print("❌ Failed to generate thumbnail for asset: \(asset.localIdentifier)")
                }
              }
              
              files.append([
                "id": asset.localIdentifier,
                "name": resource.originalFilename ?? "Unknown",
                "size": 1024 * 1024, // Default to 1MB for display purposes
                "path": resource.originalFilename ?? "Unknown",
                "mimeType": resource.uniformTypeIdentifier ?? "unknown",
                "thumbnailPath": thumbnailPath ?? ""
              ])
              
              print("📄 Added file: \(resource.originalFilename ?? "Unknown"), thumbnail: \(thumbnailPath ?? "none")")
            }
          }
          result(files)
        }
        
      } else if call.method == "getLocalFilePath" {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          return
        }
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else {
          result(FlutterError(code: "ASSET_NOT_FOUND", message: "Asset not found", details: nil))
          return
        }
        
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else {
          result(FlutterError(code: "NO_RESOURCE", message: "No resource found", details: nil))
          return
        }
        
        PHAssetResourceManager.default().writeData(
          for: resource,
          toFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(resource.originalFilename),
          options: nil,
          completionHandler: { error in
            if let error = error {
              result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
            } else {
              result(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(resource.originalFilename).path)
            }
          }
        )
        
      } else if call.method == "browseDocuments" {
        self.browseDocuments(result: result)
      } else if call.method == "listICloudFiles" {
        guard let args = call.arguments as? [String: Any],
              let type = args["type"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          return
        }
        
        print("🔍 Attempting to access iCloud Drive for \(type) files")
        
        // Get the iCloud container URL
        guard let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
          print("❌ Could not get iCloud container URL")
          result(FlutterError(code: "NO_ICLOUD", message: "iCloud not available", details: nil))
          return
        }
        
        print("🔍 iCloud container URL: \(iCloudURL)")
        print("🔍 Container exists: \(FileManager.default.fileExists(atPath: iCloudURL.path))")
        
        do {
          let fileExtensions = type == "photo" ? ["jpg", "jpeg", "png", "heic"] : ["mp4", "mov", "m4v"]
          let maxSizeBytes = 25 * 1024 * 1024
          var files: [[String: Any]] = []
          
          // List all items in the iCloud container
          let allItems = try FileManager.default.contentsOfDirectory(at: iCloudURL, includingPropertiesForKeys: [.fileSizeKey, .nameKey, .isDirectoryKey], options: [])
          
          print("🔍 Found \(allItems.count) items in iCloud container")
          
          for item in allItems {
            print("🔍 Item: \(item.lastPathComponent)")
            
            let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
              // Recursively search subdirectories
              let subItems = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: [.fileSizeKey, .nameKey], options: [])
              
              for subItem in subItems {
                let fileExtension = subItem.pathExtension.lowercased()
                if fileExtensions.contains(fileExtension) {
                  let attrs = try subItem.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                  if let size = attrs.fileSize, let name = attrs.name, size <= maxSizeBytes {
                    files.append([
                      "id": subItem.path,
                      "name": name,
                      "size": size,
                      "path": subItem.path,
                      "mimeType": type == "photo" ? "image/\(fileExtension)" : "video/\(fileExtension)"
                    ])
                    print("🔍 Added file: \(name) (\(size) bytes)")
                  }
                }
              }
            } else {
              // Check if it's a file we want
              let fileExtension = item.pathExtension.lowercased()
              if fileExtensions.contains(fileExtension) {
                let attrs = try item.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                if let size = attrs.fileSize, let name = attrs.name, size <= maxSizeBytes {
                  files.append([
                    "id": item.path,
                    "name": name,
                    "size": size,
                    "path": item.path,
                    "mimeType": type == "photo" ? "image/\(fileExtension)" : "video/\(fileExtension)"
                  ])
                  print("🔍 Added file: \(name) (\(size) bytes)")
                }
              }
            }
          }
          
          print("🔍 Total files found: \(files.count)")
          result(files)
          
        } catch {
          print("❌ Error accessing iCloud: \(error)")
          result(FlutterError(code: "ACCESS_ERROR", message: "Error accessing iCloud: \(error.localizedDescription)", details: nil))
        }
        
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func browseDocuments(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let controller = self.window?.rootViewController else {
        result(FlutterError(code: "NO_CONTROLLER", message: "No view controller available", details: nil))
        return
      }
      
      // Use older iOS compatible API - include photos and media
      let documentPicker = UIDocumentPickerViewController(documentTypes: [
        kUTTypeImage as String,
        kUTTypeMovie as String,
        kUTTypeVideo as String,
        kUTTypeAudio as String,
        kUTTypePDF as String,
        kUTTypeText as String,
        kUTTypeData as String,
        kUTTypeItem as String  // Catch-all for other file types
      ], in: .open)
      
      documentPicker.allowsMultipleSelection = true
      
      // Only set shouldShowFileExtensions if iOS 13+
      if #available(iOS 13.0, *) {
        documentPicker.shouldShowFileExtensions = true
      }
      
      // Store the result callback for later use
      DocumentPickerDelegate.shared.result = result
      documentPicker.delegate = DocumentPickerDelegate.shared
      
      controller.present(documentPicker, animated: true, completion: nil)
    }
  }
}

class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
  static let shared = DocumentPickerDelegate()
  var result: FlutterResult?
  
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    var fileInfos: [[String: Any]] = []
    
    for url in urls {
      // Start accessing the security-scoped resource
      if url.startAccessingSecurityScopedResource() {
        do {
          let resourceValues = try url.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .isDirectoryKey
          ])
          
          // Copy file to temporary location for persistent access
          let tempDir = FileManager.default.temporaryDirectory
          let fileName = resourceValues.name ?? "unknown_file"
          let tempFileURL = tempDir.appendingPathComponent(fileName)
          
          // Remove existing temp file if it exists
          try? FileManager.default.removeItem(at: tempFileURL)
          
          // Copy the file to temp location
          try FileManager.default.copyItem(at: url, to: tempFileURL)
          
          // Get file type for mime type
          var fileType = "unknown"
          if let pathExtension = resourceValues.name?.components(separatedBy: ".").last {
            fileType = pathExtension
          }
          
          let fileInfo: [String: Any] = [
            "id": url.absoluteString,
            "name": fileName,
            "size": resourceValues.fileSize ?? 0,
            "path": tempFileURL.path,  // Use temp path for persistent access
            "type": fileType,
            "isDirectory": resourceValues.isDirectory ?? false,
            "mimeType": self.getMimeType(for: fileType)
          ]
          
          fileInfos.append(fileInfo)
        } catch {
          print("Error processing file \(url): \(error)")
        }
        
        // Stop accessing security-scoped resource after copying
        url.stopAccessingSecurityScopedResource()
      }
    }
    
    result?(fileInfos)
    result = nil
  }
  
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    result?([])
    result = nil
  }
  
  private func getMimeType(for fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "heic":
      return "image/heic"
    case "mp4":
      return "video/mp4"
    case "mov":
      return "video/quicktime"
    case "m4v":
      return "video/x-m4v"
    case "pdf":
      return "application/pdf"
    case "txt":
      return "text/plain"
    default:
      return "application/octet-stream"
    }
  }
}
