import 'package:flutter/material.dart';
import '../services/cloud_file_service.dart';

/// Simple test widget to verify our native file services work
class FilePickerTestWidget extends StatefulWidget {
  const FilePickerTestWidget({super.key});

  @override
  State<FilePickerTestWidget> createState() => _FilePickerTestWidgetState();
}

class _FilePickerTestWidgetState extends State<FilePickerTestWidget> {
  final CloudFileService _fileService = CloudFileService();
  List<CloudFile> _files = [];
  bool _isLoading = false;
  String? _error;
  String _selectedProvider = 'local';
  String _selectedType = 'photo';

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _files = [];
    });

    try {
      List<CloudFile> files;

      if (_selectedProvider == 'document_picker') {
        debugPrint('📄 Using Document Picker...');
        files = await _fileService.browseDocuments();
      } else {
        debugPrint(
          '🔍 Loading $_selectedType files from $_selectedProvider...',
        );
        files = await _fileService.getFiles(
          provider: _selectedProvider,
          type: _selectedType,
        );
      }

      setState(() {
        _files = files;
        _isLoading = false;
      });

      debugPrint('✅ Found ${files.length} files');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      debugPrint('❌ Error loading files: $e');
    }
  }

  Future<void> _selectFile(CloudFile file) async {
    try {
      debugPrint('📁 Getting file for usage: ${file.name}');
      final filePath = await _fileService.getFileForUsage(file);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected: ${file.name}\nPath: $filePath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      debugPrint('✅ File ready: $filePath');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      debugPrint('❌ Error getting file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Service Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Provider selection
                Row(
                  children: [
                    const Text('Provider: '),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedProvider,
                      onChanged: (value) {
                        setState(() => _selectedProvider = value!);
                      },
                      items:
                          _fileService
                              .getAvailableProviders()
                              .map(
                                (provider) => DropdownMenuItem(
                                  value: provider,
                                  child: Text(provider),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Type selection
                Row(
                  children: [
                    const Text('Type: '),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedType,
                      onChanged: (value) {
                        setState(() => _selectedType = value!);
                      },
                      items:
                          ['photo', 'video']
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Load button
                ElevatedButton(
                  onPressed: _isLoading ? null : _loadFiles,
                  child:
                      _isLoading
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text('Load $_selectedType files'),
                ),
              ],
            ),
          ),

          const Divider(),

          // Results
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Error:', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty && !_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No files found\nTap "Load files" to search'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return ListTile(
          leading: Icon(
            _selectedType == 'photo' ? Icons.photo : Icons.videocam,
            color: Colors.blue,
          ),
          title: Text(file.name),
          subtitle: Text(
            '${file.sizeInMB.toStringAsFixed(2)} MB • ${file.provider}',
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => _selectFile(file),
        );
      },
    );
  }
}
