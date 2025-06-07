import 'package:flutter/material.dart';
import 'dm_thread_screen.dart';
import '../utils/page_transitions.dart';

class DMListScreen extends StatefulWidget {
  final int userId;

  const DMListScreen({super.key, required this.userId});

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  // Dummy conversation data for testing
  final List<Map<String, dynamic>> _dummyConversations = [
    {
      'userName': 'Nick',
      'userId': 2,
      'lastMessage': 'Great! I\'ll get the tickets 🎫',
      'timestamp': '2m ago',
      'avatar': 'N',
      'unreadCount': 2,
    },
    {
      'userName': 'Sarah',
      'userId': 3,
      'lastMessage': 'See you tomorrow!',
      'timestamp': '1h ago',
      'avatar': 'S',
      'unreadCount': 0,
    },
    {
      'userName': 'Mike',
      'userId': 4,
      'lastMessage': 'Thanks for sharing those photos',
      'timestamp': '2d ago',
      'avatar': 'M',
      'unreadCount': 1,
    },
    {
      'userName': 'Emma',
      'userId': 5,
      'lastMessage': 'Happy birthday! 🎉',
      'timestamp': '1w ago',
      'avatar': 'E',
      'unreadCount': 0,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        title: const Text(
          'Direct Messages',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Header info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: const Text(
              'Private conversations with family members',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Conversation list
          Expanded(
            child:
                _dummyConversations.isEmpty
                    ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No conversations yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start a conversation with a family member',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _dummyConversations.length,
                      itemBuilder: (context, index) {
                        final conversation = _dummyConversations[index];
                        return _buildConversationTile(conversation);
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    final bool hasUnread = conversation['unreadCount'] > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              conversation['avatar'],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          // Online indicator (dummy)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation['userName'],
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
          Text(
            conversation['timestamp'],
            style: TextStyle(
              fontSize: 12,
              color: hasUnread ? Colors.blue : Colors.grey,
              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              conversation['lastMessage'],
              style: TextStyle(
                fontSize: 14,
                color: hasUnread ? Colors.black87 : Colors.grey.shade600,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasUnread)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${conversation['unreadCount']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        // Navigate to DM thread screen with slide transition
        slidePush(
          context,
          DMThreadScreen(
            currentUserId: widget.userId,
            otherUserId: conversation['userId'],
            otherUserName: conversation['userName'],
          ),
        );
      },
    );
  }
}
