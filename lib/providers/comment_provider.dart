import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/message.dart';

class CommentProvider extends ChangeNotifier {
  List<Message> _comments = [];
  bool _isLoading = false;
  String? _error;

  List<Message> get comments => _comments;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void setComments(List<Message> newComments) {
    _comments = newComments;
    _error = null;
    notifyListeners();
  }

  void addComment(Message comment, {bool insertAtBeggining = false}) {
    // Check if comment already exists to prevent duplicates
    final alreadyExists = _comments.any(
      (existing) => existing.id == comment.id,
    );

    if (alreadyExists) {
      debugPrint(
        'Comment ${comment.id} already exists, skipping',
      );
      return;
    }

    debugPrint('Adding comment ${comment.id}');

    if (insertAtBeggining) {
      _comments.insert(0, comment);
    } else {
      _comments.add(comment);
    }
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? errorMessage) {
    _error = errorMessage;
    notifyListeners();
  }

  void clear() {
    _comments = [];
    _error = null;
    notifyListeners();
  }

  void updateComment(Message updatedComment) {
    final index = _comments.indexWhere((c) => c.id == updatedComment.id);
    if (index != -1) {
      _comments[index] = updatedComment;
      notifyListeners();
    }
  }

  void incrementLikeCount(String messageId) {
    final index = _comments.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final msg = _comments[index];
      _comments[index] = msg.copyWith(likeCount: (msg.likeCount ?? 0) + 1);
      notifyListeners();
    }
  }

  void decrementLikeCount(String messageId) {
    final index = _comments.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final msg = _comments[index];
      _comments[index] = msg.copyWith(likeCount: (msg.likeCount ?? 0) - 1);
      notifyListeners();
    }
  }

  void incrementLoveCount(String messageId) {
    final index = _comments.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final msg = _comments[index];
      _comments[index] = msg.copyWith(loveCount: (msg.loveCount ?? 0) + 1);
      notifyListeners();
    }
  }

  void decrementLoveCount(String messageId) {
    final index = _comments.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final msg = _comments[index];
      _comments[index] = msg.copyWith(loveCount: (msg.loveCount ?? 0) - 1);
      notifyListeners();
    }
  }

  void updateMessageLoveCount(String messageId, int loveCount) {
    final index = _comments.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final msg = _comments[index];
      _comments[index] = msg.copyWith(loveCount: loveCount);
      notifyListeners();
    }
  }

  void updateMessageReactions(
    String messageId, {
    int? likeCount,
    int? loveCount,
    bool? isLiked,
    bool? isLoved,
  }) {
    final index = _comments.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final msg = _comments[index];
      _comments[index] = msg.copyWith(
        likeCount: likeCount ?? msg.likeCount,
        loveCount: loveCount ?? msg.loveCount,
        isLiked: isLiked ?? msg.isLiked,
        isLoved: isLoved ?? msg.isLoved,
      );
      notifyListeners();
    }
  }
}
