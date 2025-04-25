import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';
import 'family_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegistrationScreen extends StatefulWidget {
  final ApiService apiService;

  const RegistrationScreen({super.key, required this.apiService});

  @override
  RegistrationScreenState createState() => RegistrationScreenState();
}

class RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _username;
  String? _email;
  String? _firstName;
  String? _lastName;
  String? _password;
  File? _photoFile;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _photoFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      try {
        final userId = await widget.apiService.registerUser(
          username: _username!,
          email: _email!,
          password: _password!,
          firstName: _firstName!,
          lastName: _lastName!,
          photoPath: _photoFile?.path,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => FamilyScreen(
                  apiService: widget.apiService,
                  userId: userId['userId'],
                ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error registering user: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator:
                      (value) => value!.isEmpty ? 'Username is required' : null,
                  onSaved: (value) => _username = value,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator:
                      (value) => value!.isEmpty ? 'Email is required' : null,
                  onSaved: (value) => _email = value,
                  keyboardType: TextInputType.emailAddress,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'First Name'),
                  validator:
                      (value) =>
                          value!.isEmpty ? 'First Name is required' : null,
                  onSaved: (value) => _firstName = value,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Last Name'),
                  validator:
                      (value) =>
                          value!.isEmpty ? 'Last Name is required' : null,
                  onSaved: (value) => _lastName = value,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator:
                      (value) => value!.isEmpty ? 'Password is required' : null,
                  onSaved: (value) => _password = value,
                ),
                const SizedBox(height: 20),
                _photoFile == null
                    ? const Text('No image selected')
                    : Image.file(_photoFile!, height: 100, width: 100),
                ElevatedButton(
                  onPressed: _pickImage,
                  child: const Text('Pick Image'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _register,
                  child: const Text('Register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
