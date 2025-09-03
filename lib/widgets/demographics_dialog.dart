import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../services/api_service.dart';

class DemographicsDialog {
  static Future<void> show({
    required BuildContext context,
    required int userId,
    required ApiService apiService,
    Map<String, dynamic>? currentUserData,
  }) async {
    // Get user data if not provided
    Map<String, dynamic> userData = currentUserData ?? {};
    if (userData.isEmpty) {
      try {
        userData = await apiService.getUserById(userId);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading user data: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!context.mounted) return;

    final TextEditingController firstNameController = TextEditingController(
      text: userData['firstName'] as String? ?? '',
    );
    final TextEditingController lastNameController = TextEditingController(
      text: userData['lastName'] as String? ?? '',
    );
    final TextEditingController phoneController = TextEditingController(
      text: userData['phoneNumber'] as String? ?? '+1 ',
    );
    final TextEditingController addressController = TextEditingController(
      text: userData['address'] as String? ?? '',
    );
    final TextEditingController cityController = TextEditingController(
      text: userData['city'] as String? ?? '',
    );
    final TextEditingController stateController = TextEditingController(
      text: userData['state'] as String? ?? '',
    );
    final TextEditingController zipController = TextEditingController(
      text: userData['zipCode'] as String? ?? '',
    );
    final TextEditingController countryController = TextEditingController(
      text: userData['country'] as String? ?? '',
    );
    final TextEditingController birthDateController = TextEditingController(
      text: _formatBirthDateFromMap(userData['birthDate']),
    );
    final TextEditingController bioController = TextEditingController(
      text: userData['bio'] as String? ?? '',
    );

    // Phone number formatter
    final phoneFormatter = MaskTextInputFormatter(
      mask: '+# (###) ###-####',
      filter: {"#": RegExp(r'[0-9]')},
      type: MaskAutoCompletionType.lazy,
    );

    // If phone number already exists, try to set the formatter value
    if (phoneController.text.isNotEmpty) {
      try {
        phoneFormatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: phoneController.text),
        );
      } catch (e) {
        // If formatting fails, keep the original text
        debugPrint('Could not format existing phone number: $e');
      }
    }

    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Profile Information'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // First Name
                    TextField(
                      controller: firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // Last Name
                    TextField(
                      controller: lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // Phone Number
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone),
                        hintText: '+1 (555) 123-4567',
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [phoneFormatter],
                    ),
                    const SizedBox(height: 16),
                    
                    // Address
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.home),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // City
                    TextField(
                      controller: cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // State
                    TextField(
                      controller: stateController,
                      decoration: const InputDecoration(
                        labelText: 'State/Province',
                        prefixIcon: Icon(Icons.map),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // ZIP Code
                    TextField(
                      controller: zipController,
                      decoration: const InputDecoration(
                        labelText: 'ZIP/Postal Code',
                        prefixIcon: Icon(Icons.local_post_office),
                      ),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    
                    // Country
                    TextField(
                      controller: countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        prefixIcon: Icon(Icons.public),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // Birth Date
                    TextField(
                      controller: birthDateController,
                      decoration: const InputDecoration(
                        labelText: 'Birth Date (YYYY-MM-DD)',
                        prefixIcon: Icon(Icons.cake),
                        hintText: '1990-01-15',
                      ),
                      keyboardType: TextInputType.datetime,
                      onTap: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (pickedDate != null) {
                          birthDateController.text = DateFormat('yyyy-MM-dd').format(pickedDate);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Bio
                    TextField(
                      controller: bioController,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        prefixIcon: Icon(Icons.edit),
                        hintText: 'Tell us about yourself...',
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  setState(() {
                    isLoading = true;
                  });

                  await _saveDemographics(
                    context: context,
                    dialogContext: dialogContext,
                    userId: userId,
                    apiService: apiService,
                    firstNameController: firstNameController,
                    lastNameController: lastNameController,
                    phoneController: phoneController,
                    addressController: addressController,
                    cityController: cityController,
                    stateController: stateController,
                    zipController: zipController,
                    countryController: countryController,
                    birthDateController: birthDateController,
                    bioController: bioController,
                  );

                  if (context.mounted) {
                    setState(() {
                      isLoading = false;
                    });
                  }
                },
                child: isLoading 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatBirthDateFromMap(dynamic birthDate) {
    if (birthDate == null) return '';

    try {
      // If it's already a string, return it as is
      if (birthDate is String) {
        return birthDate;
      }

      // If it's an integer timestamp, convert it to a date string
      if (birthDate is int) {
        final date = DateTime.fromMillisecondsSinceEpoch(birthDate);
        return DateFormat('yyyy-MM-dd').format(date);
      }

      // If it's a double, convert to int first
      if (birthDate is double) {
        final date = DateTime.fromMillisecondsSinceEpoch(birthDate.toInt());
        return DateFormat('yyyy-MM-dd').format(date);
      }

      return '';
    } catch (e) {
      debugPrint('Error formatting birth date: $e');
      return '';
    }
  }

  static Future<void> _saveDemographics({
    required BuildContext context,
    required BuildContext dialogContext,
    required int userId,
    required ApiService apiService,
    required TextEditingController firstNameController,
    required TextEditingController lastNameController,
    required TextEditingController phoneController,
    required TextEditingController addressController,
    required TextEditingController cityController,
    required TextEditingController stateController,
    required TextEditingController zipController,
    required TextEditingController countryController,
    required TextEditingController birthDateController,
    required TextEditingController bioController,
  }) async {
    try {
      // Validate required fields
      if (firstNameController.text.trim().isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('First name is required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (lastNameController.text.trim().isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Last name is required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Create demographics data map
      final data = {
        'firstName': firstNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'phoneNumber': phoneController.text.trim().isEmpty 
            ? null 
            : phoneController.text.trim(),
        'address': addressController.text.trim().isEmpty 
            ? null 
            : addressController.text.trim(),
        'city': cityController.text.trim().isEmpty 
            ? null 
            : cityController.text.trim(),
        'state': stateController.text.trim().isEmpty 
            ? null 
            : stateController.text.trim(),
        'zipCode': zipController.text.trim().isEmpty 
            ? null 
            : zipController.text.trim(),
        'country': countryController.text.trim().isEmpty 
            ? null 
            : countryController.text.trim(),
        'birthDate': birthDateController.text.trim().isEmpty 
            ? null 
            : birthDateController.text.trim(),
        'bio': bioController.text.trim().isEmpty 
            ? null 
            : bioController.text.trim(),
      };

      // Update demographics
      await apiService.updateDemographics(userId, data);

      if (!context.mounted) return;

      // Close dialog
      Navigator.pop(dialogContext);

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}








