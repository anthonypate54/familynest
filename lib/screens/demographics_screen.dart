import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'family_screen.dart';

class DemographicsScreen extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> userData;
  final int userId;

  const DemographicsScreen({
    Key? key,
    required this.apiService,
    required this.userData,
    required this.userId,
  }) : super(key: key);

  @override
  State<DemographicsScreen> createState() => _DemographicsScreenState();
}

class _DemographicsScreenState extends State<DemographicsScreen> {
  // Demographics fields
  String? _phoneNumber;
  String? _address;
  String? _city;
  String? _state;
  String? _zipCode;
  String? _country;
  DateTime? _birthDate;
  String? _bio;
  bool _showDemographics = false;

  // Controller for date picker
  final TextEditingController _dateController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    debugPrint("DemographicsScreen initialized");
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _birthDate) {
      setState(() {
        _birthDate = picked;
        _dateController.text = _dateFormat.format(picked);
      });
    }
  }

  Future<void> _saveDemographics() async {
    try {
      // Create a map of demographic data
      final demographicsData = {
        'phoneNumber': _phoneNumber,
        'address': _address,
        'city': _city,
        'state': _state,
        'zipCode': _zipCode,
        'country': _country,
        'birthDate':
            _birthDate != null ? _dateFormat.format(_birthDate!) : null,
        'bio': _bio,
        'showDemographics': _showDemographics,
      };

      // Log the demographic data for debugging
      debugPrint("Saving demographic data: $demographicsData");

      // Update demographics for the user
      await widget.apiService.updateDemographics(
        widget.userId,
        demographicsData,
      );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demographics saved successfully!')),
      );

      // Navigate to the family screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => FamilyScreen(
                apiService: widget.apiService,
                userId: widget.userId,
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // Show error message
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving demographics: $e')));
    }
  }

  Future<void> _skipDemographics() async {
    // Navigate directly to the family screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (context) => FamilyScreen(
              apiService: widget.apiService,
              userId: widget.userId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optional Information'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _skipDemographics,
            child: const Text('Skip', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          children: [
            // Header
            Text(
              'Demographics Info',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const Text(
              'These fields are optional',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // Contact & Address (smaller fields with icons)
            _buildCompactSectionHeader(context, 'Contact & Location'),

            // Phone & Address in one row
            Row(
              children: [
                // Phone number (40%)
                Expanded(
                  flex: 4,
                  child: _buildCompactTextField(
                    label: 'Phone',
                    icon: Icons.phone,
                    onChanged: (val) => _phoneNumber = val,
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 8),
                // Country (60%)
                Expanded(
                  flex: 6,
                  child: _buildCompactTextField(
                    label: 'Country',
                    icon: Icons.public,
                    onChanged: (val) => _country = val,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Address
            _buildCompactTextField(
              label: 'Address',
              icon: Icons.home,
              onChanged: (val) => _address = val,
            ),
            const SizedBox(height: 8),

            // City, State & ZIP in a compact row
            Row(
              children: [
                // City (40%)
                Expanded(
                  flex: 4,
                  child: _buildCompactTextField(
                    label: 'City',
                    icon: Icons.location_city,
                    onChanged: (val) => _city = val,
                  ),
                ),
                const SizedBox(width: 8),
                // State (30%)
                Expanded(
                  flex: 3,
                  child: _buildCompactTextField(
                    label: 'State',
                    icon: Icons.map,
                    onChanged: (val) => _state = val,
                  ),
                ),
                const SizedBox(width: 8),
                // ZIP (30%)
                Expanded(
                  flex: 3,
                  child: _buildCompactTextField(
                    label: 'ZIP',
                    icon: Icons.pin,
                    onChanged: (val) => _zipCode = val,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Personal Info
            _buildCompactSectionHeader(context, 'Personal Details'),

            // Birth date in compact form
            TextField(
              controller: _dateController,
              decoration: InputDecoration(
                labelText: 'Birth Date',
                labelStyle: const TextStyle(fontSize: 12),
                hintText: 'YYYY-MM-DD',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.cake, size: 18),
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(fontSize: 14),
              readOnly: true,
              onTap: () => _selectDate(context),
            ),
            const SizedBox(height: 8),

            // Bio with reduced height
            TextField(
              decoration: InputDecoration(
                labelText: 'Bio',
                labelStyle: const TextStyle(fontSize: 12),
                hintText: 'Tell your family about yourself',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(fontSize: 14),
              maxLines: 2, // Reduced lines
              onChanged: (value) => _bio = value,
            ),
            const SizedBox(height: 8),

            // Share switch
            SwitchListTile.adaptive(
              title: const Text(
                'Share with family',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Make visible to family',
                style: TextStyle(fontSize: 12),
              ),
              secondary: const Icon(Icons.visibility, size: 20),
              contentPadding: EdgeInsets.zero,
              value: _showDemographics,
              onChanged: (value) {
                setState(() {
                  _showDemographics = value;
                });
              },
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                // Skip Text Button (30%)
                Expanded(
                  flex: 3,
                  child: TextButton(
                    onPressed: _skipDemographics,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 8),
                // Save Button (70%)
                Expanded(
                  flex: 7,
                  child: ElevatedButton(
                    onPressed: _saveDemographics,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('SAVE & CONTINUE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Compact section header with minimal padding
  Widget _buildCompactSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(thickness: 1, color: Theme.of(context).dividerColor),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          Expanded(
            child: Divider(thickness: 1, color: Theme.of(context).dividerColor),
          ),
        ],
      ),
    );
  }

  // Compact text field with small font and padding
  Widget _buildCompactTextField({
    required String label,
    required IconData icon,
    required Function(String) onChanged,
    TextInputType? keyboardType,
  }) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        prefixIcon: Icon(icon, size: 18),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: const TextStyle(fontSize: 14),
      keyboardType: keyboardType,
      onChanged: onChanged,
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }
}
