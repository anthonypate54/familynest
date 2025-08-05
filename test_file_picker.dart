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
                  print('Start: ${DateTime.now()}');
                  final stopwatch = Stopwatch()..start();

                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(
                        type: FileType.any,
                        allowMultiple: false,
                        withData: false,
                        withReadStream: false,
                      );

                  stopwatch.stop();
                  print('End: ${DateTime.now()}');
                  print('Duration: ${stopwatch.elapsedMilliseconds}ms');

                  if (result != null) {
                    final file = result.files.first;
                    print('File: ${file.name}');
                    print('Size: ${file.size} bytes');
                    print('Path: ${file.path}');
                    print('Identifier: ${file.identifier}');
                  } else {
                    print('No file selected');
                  }
                },
                child: const Text('Pick Any File'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  print('VIDEO Start: ${DateTime.now()}');
                  final stopwatch = Stopwatch()..start();

                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(
                        type: FileType.video,
                        allowMultiple: false,
                        withData: false,
                        withReadStream: false,
                      );

                  stopwatch.stop();
                  print('VIDEO End: ${DateTime.now()}');
                  print('VIDEO Duration: ${stopwatch.elapsedMilliseconds}ms');

                  if (result != null) {
                    final file = result.files.first;
                    print('VIDEO File: ${file.name}');
                    print('VIDEO Size: ${file.size} bytes');
                    print('VIDEO Path: ${file.path}');
                    print('VIDEO Identifier: ${file.identifier}');
                  } else {
                    print('No video selected');
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
