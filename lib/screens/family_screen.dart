import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'package:provider/provider.dart';

class FamilyScreen extends StatefulWidget {
  final int userId;

  const FamilyScreen({super.key, required this.userId});

  @override
  FamilyScreenState createState() => FamilyScreenState();
}

class FamilyScreenState extends State<FamilyScreen> {
  final _createFormKey = GlobalKey<FormState>();
  final _joinFormKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final _familyIdController = TextEditingController();

  Future<void> _createFamily() async {
    if (_createFormKey.currentState!.validate()) {
      _createFormKey.currentState!.save();
      try {
        Map<String, dynamic> familyData = await Provider.of<ApiService>(
          context,
          listen: false,
        ).createFamily(widget.userId, _familyNameController.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Family created! ID: ${familyData['id']}')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(userId: widget.userId),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating family: $e')));
      }
    }
  }

  Future<void> _joinFamily() async {
    if (_joinFormKey.currentState!.validate()) {
      _joinFormKey.currentState!.save();
      try {
        int familyId = int.parse(_familyIdController.text);
        await Provider.of<ApiService>(
          context,
          listen: false,
        ).joinFamily(widget.userId, familyId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined family successfully!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(userId: widget.userId),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error joining family: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a New Family',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Form(
              key: _createFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _familyNameController,
                    decoration: const InputDecoration(labelText: 'Family Name'),
                    validator:
                        (value) =>
                            value!.isEmpty ? 'Family name is required' : null,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _createFamily,
                    child: const Text('Create Family'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Join an Existing Family',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Form(
              key: _joinFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _familyIdController,
                    decoration: const InputDecoration(labelText: 'Family ID'),
                    keyboardType: TextInputType.number,
                    validator:
                        (value) =>
                            value!.isEmpty ? 'Family ID is required' : null,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _joinFamily,
                    child: const Text('Join Family'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    _familyIdController.dispose();
    super.dispose();
  }
}
