import 'package:flutter/material.dart';

class Invitation {
  final int id;
  final int familyId;
  final int inviterId;
  final String status;
  final String createdAt;
  final String expiresAt;

  Invitation({
    required this.id,
    required this.familyId,
    required this.inviterId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'],
      familyId: json['familyId'],
      inviterId: json['inviterId'],
      status: json['status'],
      createdAt: json['createdAt'],
      expiresAt: json['expiresAt'],
    );
  }
}
