# FamilyNest Services

This directory contains service classes for the FamilyNest application.

## Service Architecture

FamilyNest uses a service-based architecture to:
- Centralize API communication
- Reuse business logic across screens
- Reduce code duplication
- Make testing easier

## Available Services

### ApiService

The base service that handles communication with the backend API.

```dart
final apiService = ApiService();
await apiService.initialize();
```

### InvitationService

Handles family invitation-related operations.

```dart
// Get an instance via the ServiceProvider
final invitationService = ServiceProvider().invitationService;

// Get processed invitations (with complete details)
final invitations = await invitationService.getProcessedInvitations(userId);

// Respond to an invitation
final success = await invitationService.respondToInvitation(invitationId, true);

// Send an invitation
final sent = await invitationService.inviteUserToFamily(userId, email);
```

## Service Provider

The `ServiceProvider` is a singleton that gives access to all services:

```dart
// Access anywhere in the app
final provider = ServiceProvider();
final invService = provider.invitationService;

// Services are initialized in main.dart
provider.initialize(apiService); 
```

## How to Create a New Service

1. Create a new service class in this directory
2. Add the service to the `ServiceProvider` class
3. Initialize it in the `initialize()` method of `ServiceProvider`
4. Access it via `ServiceProvider()` in your screens

## Best Practices

- Always access services through the `ServiceProvider`
- Keep service methods focused on one task
- Return clear success/failure indicators
- Handle exceptions within the service when appropriate
- Document your service methods 