import 'package:flutter/material.dart';

enum FamilyRole { admin, member }

class FamilyMember {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String? photo;
  final FamilyRole role;
  final bool isOwner;
  final DateTime joinedAt;
  final bool isMuted;
  final bool receiveMessages;
  final String? ownedFamilyName;

  FamilyMember({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    this.photo,
    required this.role,
    required this.isOwner,
    required this.joinedAt,
    this.isMuted = false,
    this.receiveMessages = true,
    this.ownedFamilyName,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'] ?? json['userId'],
      username: json['username'] ?? '',
      firstName: json['firstName'] ?? json['memberFirstName'] ?? '',
      lastName: json['lastName'] ?? json['memberLastName'] ?? '',
      photo: json['photo'],
      role: _parseRole(json['role'] ?? json['membershipRole']),
      isOwner: json['isOwner'] ?? false,
      joinedAt: _parseDateTime(json['joinedAt']) ?? DateTime.now(),
      isMuted: json['isMuted'] ?? false,
      receiveMessages: json['receiveMessages'] ?? true,
      ownedFamilyName: json['ownedFamilyName'],
    );
  }

  static FamilyRole _parseRole(String? role) {
    switch (role?.toUpperCase()) {
      case 'ADMIN':
      case 'FAMILY_ADMIN':
        return FamilyRole.admin;
      default:
        return FamilyRole.member;
    }
  }

  static DateTime? _parseDateTime(dynamic dateTime) {
    if (dateTime == null) return null;
    if (dateTime is String) {
      return DateTime.tryParse(dateTime);
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'firstName': firstName,
      'lastName': lastName,
      'photo': photo,
      'role': role.name.toUpperCase(),
      'isOwner': isOwner,
      'joinedAt': joinedAt.toIso8601String(),
      'isMuted': isMuted,
      'receiveMessages': receiveMessages,
      'ownedFamilyName': ownedFamilyName,
    };
  }

  String get fullName => '$firstName $lastName';
  String get displayName => fullName.trim().isNotEmpty ? fullName : username;
  String get initials {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    }
    return username.isNotEmpty ? username[0].toUpperCase() : '?';
  }

  String get roleDisplayText {
    switch (role) {
      case FamilyRole.admin:
        return 'Admin';
      case FamilyRole.member:
        return 'Member';
    }
  }

  Color get roleColor {
    switch (role) {
      case FamilyRole.admin:
        return Colors.green;
      case FamilyRole.member:
        return Colors.blue;
    }
  }

  FamilyMember copyWith({
    int? id,
    String? username,
    String? firstName,
    String? lastName,
    String? photo,
    FamilyRole? role,
    bool? isOwner,
    DateTime? joinedAt,
    bool? isMuted,
    bool? receiveMessages,
    String? ownedFamilyName,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      photo: photo ?? this.photo,
      role: role ?? this.role,
      isOwner: isOwner ?? this.isOwner,
      joinedAt: joinedAt ?? this.joinedAt,
      isMuted: isMuted ?? this.isMuted,
      receiveMessages: receiveMessages ?? this.receiveMessages,
      ownedFamilyName: ownedFamilyName ?? this.ownedFamilyName,
    );
  }
}

class Family {
  final int id;
  final String name;
  final bool isOwned;
  final FamilyRole userRole;
  final List<FamilyMember> members;
  final DateTime createdAt;
  final bool isMuted;
  final bool receiveMessages;
  final bool receiveInvitations;
  final bool receiveReactions;
  final FamilyMember? owner;

  Family({
    required this.id,
    required this.name,
    required this.isOwned,
    required this.userRole,
    this.members = const [],
    required this.createdAt,
    this.isMuted = false,
    this.receiveMessages = true,
    this.receiveInvitations = true,
    this.receiveReactions = true,
    this.owner,
  });

  factory Family.fromJson(Map<String, dynamic> json) {
    List<FamilyMember> memberList = [];
    if (json['members'] != null) {
      memberList =
          (json['members'] as List)
              .map((member) => FamilyMember.fromJson(member))
              .toList();
    }

    return Family(
      id: json['familyId'] ?? json['id'],
      name: json['familyName'] ?? json['name'] ?? '',
      isOwned: json['isOwned'] ?? json['isOwner'] ?? false,
      userRole: FamilyMember._parseRole(json['role'] ?? json['userRole']),
      members: memberList,
      createdAt:
          FamilyMember._parseDateTime(json['createdAt']) ?? DateTime.now(),
      isMuted: json['isMuted'] ?? false,
      receiveMessages: json['receiveMessages'] ?? true,
      receiveInvitations: json['receiveInvitations'] ?? true,
      receiveReactions: json['receiveReactions'] ?? true,
      owner:
          json['owner'] != null ? FamilyMember.fromJson(json['owner']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isOwned': isOwned,
      'userRole': userRole.name.toUpperCase(),
      'members': members.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'isMuted': isMuted,
      'receiveMessages': receiveMessages,
      'receiveInvitations': receiveInvitations,
      'receiveReactions': receiveReactions,
      'owner': owner?.toJson(),
    };
  }

  int get memberCount => members.length;
  List<FamilyMember> get activeMembers =>
      members.where((m) => !m.isMuted).toList();
  List<FamilyMember> get mutedMembers =>
      members.where((m) => m.isMuted).toList();
  List<FamilyMember> get admins =>
      members.where((m) => m.role == FamilyRole.admin).toList();
  List<FamilyMember> get regularMembers =>
      members.where((m) => m.role == FamilyRole.member).toList();

  String get roleDisplayText {
    switch (userRole) {
      case FamilyRole.admin:
        return isOwned ? 'Owner' : 'Admin';
      case FamilyRole.member:
        return 'Member';
    }
  }

  Color get roleColor {
    switch (userRole) {
      case FamilyRole.admin:
        return isOwned ? Colors.green : Colors.orange;
      case FamilyRole.member:
        return Colors.blue;
    }
  }

  IconData get roleIcon {
    switch (userRole) {
      case FamilyRole.admin:
        return isOwned ? Icons.home : Icons.admin_panel_settings;
      case FamilyRole.member:
        return Icons.person;
    }
  }

  bool get canInvite => userRole == FamilyRole.admin;
  bool get canManageMembers => userRole == FamilyRole.admin && isOwned;
  bool get canEditFamily => userRole == FamilyRole.admin && isOwned;
  bool get canLeave => !isOwned; // Can't leave your own family

  Family copyWith({
    int? id,
    String? name,
    bool? isOwned,
    FamilyRole? userRole,
    List<FamilyMember>? members,
    DateTime? createdAt,
    bool? isMuted,
    bool? receiveMessages,
    bool? receiveInvitations,
    bool? receiveReactions,
    FamilyMember? owner,
  }) {
    return Family(
      id: id ?? this.id,
      name: name ?? this.name,
      isOwned: isOwned ?? this.isOwned,
      userRole: userRole ?? this.userRole,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
      isMuted: isMuted ?? this.isMuted,
      receiveMessages: receiveMessages ?? this.receiveMessages,
      receiveInvitations: receiveInvitations ?? this.receiveInvitations,
      receiveReactions: receiveReactions ?? this.receiveReactions,
      owner: owner ?? this.owner,
    );
  }
}

class FamilyNotificationPreferences {
  final bool receiveMessages;
  final bool receiveInvitations;
  final bool receiveReactions;
  final bool receiveComments;
  final bool muteFamily;
  final List<int> mutedMemberIds;
  final bool emailNotifications;
  final bool pushNotifications;

  FamilyNotificationPreferences({
    this.receiveMessages = true,
    this.receiveInvitations = true,
    this.receiveReactions = true,
    this.receiveComments = true,
    this.muteFamily = false,
    this.mutedMemberIds = const [],
    this.emailNotifications = true,
    this.pushNotifications = true,
  });

  factory FamilyNotificationPreferences.fromJson(Map<String, dynamic> json) {
    return FamilyNotificationPreferences(
      receiveMessages: json['receiveMessages'] ?? true,
      receiveInvitations: json['receiveInvitations'] ?? true,
      receiveReactions: json['receiveReactions'] ?? true,
      receiveComments: json['receiveComments'] ?? true,
      muteFamily: json['muteFamily'] ?? false,
      mutedMemberIds: List<int>.from(json['mutedMemberIds'] ?? []),
      emailNotifications: json['emailNotifications'] ?? true,
      pushNotifications: json['pushNotifications'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'receiveMessages': receiveMessages,
      'receiveInvitations': receiveInvitations,
      'receiveReactions': receiveReactions,
      'receiveComments': receiveComments,
      'muteFamily': muteFamily,
      'mutedMemberIds': mutedMemberIds,
      'emailNotifications': emailNotifications,
      'pushNotifications': pushNotifications,
    };
  }

  FamilyNotificationPreferences copyWith({
    bool? receiveMessages,
    bool? receiveInvitations,
    bool? receiveReactions,
    bool? receiveComments,
    bool? muteFamily,
    List<int>? mutedMemberIds,
    bool? emailNotifications,
    bool? pushNotifications,
  }) {
    return FamilyNotificationPreferences(
      receiveMessages: receiveMessages ?? this.receiveMessages,
      receiveInvitations: receiveInvitations ?? this.receiveInvitations,
      receiveReactions: receiveReactions ?? this.receiveReactions,
      receiveComments: receiveComments ?? this.receiveComments,
      muteFamily: muteFamily ?? this.muteFamily,
      mutedMemberIds: mutedMemberIds ?? this.mutedMemberIds,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      pushNotifications: pushNotifications ?? this.pushNotifications,
    );
  }
}
