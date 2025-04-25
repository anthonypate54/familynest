import 'package:flutter/material.dart';

class Invitation {
  final int id;
  final int familyId;
  final String status;
  final String email;
  final String expiresAt;
  final String createdAt;
  final int? inviterId;
  final String? inviterName;

  Invitation({
    required this.id,
    required this.familyId,
    required this.status,
    required this.email,
    required this.expiresAt,
    required this.createdAt,
    this.inviterId,
    this.inviterName,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) {
    debugPrint('Creating invitation from JSON: $json');
    return Invitation(
      id: json['id'],
      familyId: json['familyId'],
      status: json['status'],
      email: json['email'] ?? '',
      expiresAt: json['expiresAt'] ?? '',
      createdAt: json['createdAt'] ?? '',
      inviterId: json['inviterId'],
      inviterName: json['inviterName'] ?? 'Unknown',
    );
  }

  // Check if this invitation is new (created in the last hour)
  bool get isNew {
    if (createdAt.isEmpty) return false;

    try {
      final created = DateTime.parse(createdAt);
      final now = DateTime.now();
      return now.difference(created).inHours < 1;
    } catch (e) {
      return false;
    }
  }
}
