/// Controller to communicate between screens
class BottomNavigationController {
  /// Callback for updating pending invitations count
  Function(int)? updatePendingInvitationsCount;

  /// Callback when families data needs to be refreshed
  Function? refreshUserFamiliesCallback;

  /// Method to update pending invitations count
  void setPendingInvitationsCount(int count) {
    if (updatePendingInvitationsCount != null) {
      updatePendingInvitationsCount!(count);
    }
  }

  /// Method to trigger refresh of user's families data
  void refreshUserFamilies() {
    if (refreshUserFamiliesCallback != null) {
      refreshUserFamiliesCallback!();
    }
  }
}
