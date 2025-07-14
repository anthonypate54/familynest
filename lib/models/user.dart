import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'subscription.dart';

enum OnboardingFlow { normal, familyMember, invitationFirst, freshUser }

class FamilyDetails {
  final int id;
  final String name;
  final bool isOwner;
  final int memberCount;
  final String membershipRole;
  final bool isActive;

  FamilyDetails({
    required this.id,
    required this.name,
    required this.isOwner,
    required this.memberCount,
    required this.membershipRole,
    required this.isActive,
  });

  factory FamilyDetails.fromJson(Map<String, dynamic> json) {
    return FamilyDetails(
      id: json['id'],
      name: json['name'] ?? '',
      isOwner: json['isOwner'] ?? false,
      memberCount: json['memberCount'] ?? 0,
      membershipRole: json['membershipRole'] ?? 'MEMBER',
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isOwner': isOwner,
      'memberCount': memberCount,
      'membershipRole': membershipRole,
      'isActive': isActive,
    };
  }
}

class User {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String? phoneNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;
  final DateTime? birthDate;
  final String? bio;
  final bool showDemographics;
  final String? photo;
  final int? familyId;
  final FamilyDetails? familyDetails;
  final Subscription? subscription;
  final int? onboardingState;

  User({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    this.phoneNumber,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.birthDate,
    this.bio,
    this.showDemographics = false,
    this.photo,
    this.familyId,
    this.familyDetails,
    this.subscription,
    this.onboardingState,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    debugPrint('Creating user from JSON: $json');

    // Handle id field with proper type conversion
    dynamic rawId = json['id'] ?? json['userId'];
    int id;
    if (rawId is int) {
      id = rawId;
    } else if (rawId is String) {
      id = int.parse(rawId);
    } else if (rawId is num) {
      id = rawId.toInt();
    } else {
      throw Exception(
        'User id is required but was null or invalid type: $rawId',
      );
    }

    return User(
      id: id,
      username: json['username'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'USER',
      phoneNumber: json['phoneNumber'],
      address: json['address'],
      city: json['city'],
      state: json['state'],
      zipCode: json['zipCode'],
      country: json['country'],
      birthDate: _parseBirthDate(json['birthDate']),
      bio: json['bio'],
      showDemographics: json['showDemographics'] ?? false,
      photo: json['photo'],
      familyId: json['familyId'],
      familyDetails:
          json['familyDetails'] != null
              ? FamilyDetails.fromJson(json['familyDetails'])
              : null,
      subscription:
          json['subscription'] != null
              ? Subscription.fromJson(json['subscription'])
              : null,
      onboardingState: json['onboardingState'] ?? 0, // Default to 0 if null
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'role': role,
      'phoneNumber': phoneNumber,
      'address': address,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
      'birthDate': birthDate?.toIso8601String(),
      'bio': bio,
      'showDemographics': showDemographics,
      'photo': photo,
      'familyId': familyId,
      'familyDetails': familyDetails?.toJson(),
      'subscription': subscription?.toJson(),
      'onboardingState': onboardingState,
    };
  }

  // Static method to parse birth date from various formats
  static DateTime? _parseBirthDate(dynamic birthDate) {
    if (birthDate == null) return null;

    try {
      // If it's already a string, try to parse it
      if (birthDate is String) {
        return DateTime.parse(birthDate);
      }

      // If it's an integer timestamp, convert it
      if (birthDate is int) {
        return DateTime.fromMillisecondsSinceEpoch(birthDate);
      }

      // If it's a double, convert to int first
      if (birthDate is double) {
        return DateTime.fromMillisecondsSinceEpoch(birthDate.toInt());
      }

      return null;
    } catch (e) {
      debugPrint('Error parsing birth date: $e');
      return null;
    }
  }

  // Helper getters
  String get fullName => '$firstName $lastName';

  String get formattedBirthDate {
    if (birthDate == null) return '';
    return DateFormat('MM/dd/yyyy').format(birthDate!);
  }

  bool get hasProfilePhoto => photo != null && photo!.isNotEmpty;

  bool get hasCompleteAddress =>
      address != null && city != null && state != null && zipCode != null;

  bool get hasBasicInfo =>
      firstName.isNotEmpty && lastName.isNotEmpty && email.isNotEmpty;

  // Subscription-related helper methods
  bool get hasSubscription => subscription != null;
  bool get isInTrial => subscription?.isInTrial ?? false;
  bool get hasActiveSubscription => subscription?.isActive ?? false;
  bool get subscriptionExpired => subscription?.isExpired ?? false;
  int get trialDaysLeft => subscription?.daysLeftInTrial ?? 0;

  // Onboarding flow determination using bitmap logic
  OnboardingFlow getOnboardingFlow() {
    int state = onboardingState ?? 0;

    // Check decision flow based on our flowchart
    // 1. Has messages (1) OR DMs (2) → Normal flow (skip onboarding)
    if ((state & 3) > 0) {
      return OnboardingFlow.normal;
    }

    // 2. Has family membership (4) → Family member onboarding
    if ((state & 4) > 0) {
      return OnboardingFlow.familyMember;
    }

    // 3. Has pending invitations (8) → Invitation-first onboarding
    if ((state & 8) > 0) {
      return OnboardingFlow.invitationFirst;
    }

    // 4. Fresh user → Full onboarding
    return OnboardingFlow.freshUser;
  }

  // Helper methods for debugging onboarding state
  bool get hasMessages => (onboardingState ?? 0) & 1 > 0;
  bool get hasDMs => (onboardingState ?? 0) & 2 > 0;
  bool get hasFamilyMembership => (onboardingState ?? 0) & 4 > 0;
  bool get hasPendingInvitations => (onboardingState ?? 0) & 8 > 0;

  String get onboardingStateDebug {
    int state = onboardingState ?? 0;
    List<String> flags = [];
    if (hasMessages) flags.add('HAS_MESSAGES');
    if (hasDMs) flags.add('HAS_DMS');
    if (hasFamilyMembership) flags.add('HAS_FAMILY_MEMBERSHIP');
    if (hasPendingInvitations) flags.add('HAS_PENDING_INVITATIONS');
    return 'State: $state (${flags.join(', ')})';
  }

  // Create a copy with updated demographics
  User copyWith({
    int? id,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? role,
    String? phoneNumber,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    DateTime? birthDate,
    String? bio,
    bool? showDemographics,
    String? photo,
    int? familyId,
    FamilyDetails? familyDetails,
    Subscription? subscription,
    int? onboardingState,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      role: role ?? this.role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      birthDate: birthDate ?? this.birthDate,
      bio: bio ?? this.bio,
      showDemographics: showDemographics ?? this.showDemographics,
      photo: photo ?? this.photo,
      familyId: familyId ?? this.familyId,
      familyDetails: familyDetails ?? this.familyDetails,
      subscription: subscription ?? this.subscription,
      onboardingState: onboardingState ?? this.onboardingState,
    );
  }
}
