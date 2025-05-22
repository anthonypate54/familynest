import 'package:flutter/material.dart';
import './test_message_card.dart';
import '../config/ui_config.dart';
import '../models/message.dart';
import '../test_data/test_messages.dart';

class TestThreadScreen extends StatefulWidget {
  final List<Message> messages;

  const TestThreadScreen({Key? key, required this.messages}) : super(key: key);

  @override
  TestThreadScreenState createState() => TestThreadScreenState();
}

class TestThreadScreenState extends State<TestThreadScreen> {
  final List<Message> navigationStack = [];
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.messages.isNotEmpty) {
      navigationStack.add(widget.messages[0]);
    } else {
      // If no messages, pop the screen to avoid crash
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
      });
    }
  }

  void navigateToReply(Message reply) {
    setState(() {
      navigationStack.add(reply);
    });
  }

  void navigateBack() {
    if (navigationStack.length > 1) {
      setState(() {
        navigationStack.removeLast();
      });
    }
  }

  void openNewThread(String selectedText) {
    // Create a new message with the selected text
    final newMessage = Message(
      id: DateTime.now().toString(), // Unique ID
      content: selectedText,
      replies: [],
    );

    // Navigate to a new thread screen with the new message
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TestThreadScreen(messages: [newMessage]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMessage = navigationStack.last;

    return Scaffold(
      backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: UIConfig.useDarkMode ? Colors.grey[900] : Colors.blue,
        title: Text(
          'Thread Test',
          style: TextStyle(
            color: UIConfig.useDarkMode ? Colors.white : Colors.white,
          ),
        ),
        leading:
            navigationStack.length > 1
                ? IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: UIConfig.useDarkMode ? Colors.white : Colors.white,
                  ),
                  onPressed: navigateBack,
                )
                : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: currentMessage.replies.length,
              itemBuilder: (context, index) {
                final reply = currentMessage.replies[index];
                return TestMessageCard(
                  message: reply,
                  onTap: () => navigateToReply(reply),
                );
              },
            ),
          ),
          // Reply input row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    decoration: InputDecoration(
                      hintText: 'Post your reply',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        // For now, just print and clear
                        debugPrint('Reply submitted: $value');
                        _replyController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    // TODO: Add camera/media picker logic
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Dummy data for testing
final dummyMessages = [
  Message(
    id: '1',
    content: 'Original Message (Level 0)',
    replies: [
      Message(
        id: '2',
        content: 'Reply Level 1',
        replies: [
          Message(
            id: '3',
            content: 'Reply Level 2',
            replies: [
              Message(
                id: '4',
                content: 'Reply Level 3',
                replies: [
                  Message(
                    id: '5',
                    content: 'Reply Level 4',
                    replies: [
                      Message(
                        id: '6',
                        content: 'Reply Level 5',
                        replies: [
                          Message(
                            id: '7',
                            content: 'Reply Level 6',
                            replies: [
                              Message(
                                id: '8',
                                content: 'Reply Level 7',
                                replies: [
                                  Message(
                                    id: '9',
                                    content: 'Reply Level 8',
                                    replies: [
                                      Message(
                                        id: '10',
                                        content: 'Reply Level 9',
                                        replies: [],
                                        depth: 9,
                                      ),
                                    ],
                                    depth: 8,
                                  ),
                                ],
                                depth: 7,
                              ),
                            ],
                            depth: 6,
                          ),
                        ],
                        depth: 5,
                      ),
                    ],
                    depth: 4,
                  ),
                ],
                depth: 3,
              ),
            ],
            depth: 2,
          ),
        ],
        depth: 1,
      ),
    ],
    depth: 0,
  ),
];
