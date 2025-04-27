import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'dart:io';
import '../services/api_service.dart';
import 'demographics_screen.dart';
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

  @override
  void initState() {
    super.initState();
    // Debug log to verify component is mounting
    debugPrint("RegistrationScreen initialized - Basic Info Only Version");
  }

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      try {
        debugPrint("Registering user with basic info only");
        debugPrint("Username: $_username, Email: $_email");

        // Create empty demographics data to allow user to fill in later
        final demographicsData = {
          'phoneNumber': null,
          'address': null,
          'city': null,
          'state': null,
          'zipCode': null,
          'country': null,
          'birthDate': null,
          'bio': null,
          'showDemographics': false,
        };

        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating account... This may take a moment.'),
            duration: Duration(seconds: 3),
          ),
        );

        final userId = await widget.apiService.registerUser(
          username: _username!,
          email: _email!,
          password: _password!,
          firstName: _firstName!,
          lastName: _lastName!,
          photoPath: null, // No photo upload during registration
          demographics: demographicsData,
        );

        if (!mounted) return;

        // Success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful!')),
        );

        // Store basic user data to pass to demographics screen
        final userData = {
          'username': _username,
          'email': _email,
          'firstName': _firstName,
          'lastName': _lastName,
        };

        // Navigate to demographics screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => DemographicsScreen(
                  apiService: widget.apiService,
                  userData: userData,
                  userId: userId['userId'],
                ),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        String errorMessage = 'Error registering user';

        // Handle specific errors
        if (e.toString().contains('Username already taken')) {
          errorMessage =
              'Username already taken. Please choose a different username.';
        } else if (e.toString().contains('Email already registered')) {
          errorMessage =
              'Email already registered. Please use a different email or try logging in.';
        } else {
          errorMessage = 'Error: ${e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Debug log to verify build method is called
    debugPrint("============================================");
    debugPrint("USING UPDATED REGISTRATION SCREEN WITHOUT PHOTO UPLOAD");
    debugPrint("============================================");
    debugPrint("Building basic registration screen");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Account information section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Username field
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                          hintText: 'Choose a unique username',
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty ? 'Username is required' : null,
                        onSaved: (value) => _username = value,
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                          hintText: 'Your email address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator:
                            (value) =>
                                value!.isEmpty ? 'Email is required' : null,
                        onSaved: (value) => _email = value,
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                          hintText: 'Create a secure password',
                        ),
                        obscureText: true,
                        validator:
                            (value) =>
                                value!.isEmpty ? 'Password is required' : null,
                        onSaved: (value) => _password = value,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Personal information section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // First Name field
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          hintText: 'Your first name',
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty
                                    ? 'First name is required'
                                    : null,
                        onSaved: (value) => _firstName = value,
                      ),
                      const SizedBox(height: 16),

                      // Last Name field
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          hintText: 'Your last name',
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty ? 'Last name is required' : null,
                        onSaved: (value) => _lastName = value,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Register button
              ElevatedButton(
                onPressed: _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'CREATE ACCOUNT',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 8),

              const Center(
                child: Text(
                  'You will be able to add profile photo and optional information after registration',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Demographics (phone, address, birth date, etc.) can be added after registration',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
