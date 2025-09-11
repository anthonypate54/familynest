// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('File Picker Test')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  debugPrint('Start: ${DateTime.now()}');
                  final stopwatch = Stopwatch()..start();

                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(
                        type: FileType.any,
                        allowMultiple: false,
                        withData: false,
                        withReadStream: false,
                      );

                  stopwatch.stop();
                  debugPrint('End: ${DateTime.now()}');
                  debugPrint('Duration: ${stopwatch.elapsedMilliseconds}ms');

                  if (result != null) {
                    final file = result.files.first;
                    debugPrint('File: ${file.name}');
                    debugPrint('Size: ${file.size} bytes');
                    debugPrint('Path: ${file.path}');
                    debugPrint('Identifier: ${file.identifier}');
                  } else {
                    debugPrint('No file selected');
                  }
                },
                child: const Text('Pick Any File'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  debugPrint('VIDEO Start: ${DateTime.now()}');
                  final stopwatch = Stopwatch()..start();

                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(
                        type: FileType.video,
                        allowMultiple: false,
                        withData: false,
                        withReadStream: false,
                      );

                  stopwatch.stop();
                  debugPrint('VIDEO End: ${DateTime.now()}');
                  debugPrint(
                    'VIDEO Duration: ${stopwatch.elapsedMilliseconds}ms',
                  );

                  if (result != null) {
                    final file = result.files.first;
                    debugPrint('VIDEO File: ${file.name}');
                    debugPrint('VIDEO Size: ${file.size} bytes');
                    debugPrint('VIDEO Path: ${file.path}');
                    debugPrint('VIDEO Identifier: ${file.identifier}');
                  } else {
                    debugPrint('No video selected');
                  }
                },
                child: const Text('Pick Video Only'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
