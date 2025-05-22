import '../models/message.dart';

// Test data for message list screen
final List<Message> testTopLevelMessages = [
  Message(
    id: '1',
    content: "Welcome to FamilyNest!",
    replies: [
      Message(
        id: '2',
        content: "Reply to Welcome",
        replies: [
          Message(
            id: '3',
            content: "Reply to Reply to Welcome",
            replies: [
              Message(
                id: '4',
                content: "Third level reply!",
                replies: [
                  Message(
                    id: '5',
                    content: "Fourth level reply!",
                    replies: [
                      Message(
                        id: '6',
                        content: "Fifth level reply!",
                        replies: [],
                        depth: 5,
                        mediaUrl: 'assets/mytest.jpg',
                        mediaType: 'image',
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
        mediaUrl: 'assets/mytest.jpg',
        mediaType: 'image',
      ),
    ],
    mediaUrl: 'assets/mytest.jpg',
    mediaType: 'image',
  ),
  Message(
    id: '7',
    content: "How is everyone doing?",
    replies: [
      Message(
        id: '8',
        content: "Doing great! How about you?",
        replies: [],
        depth: 1,
      ),
    ],
  ),
  Message(
    id: '9',
    content: "Let's plan a family reunion.",
    replies: [
      Message(
        id: '10',
        content: "That sounds fun!",
        replies: [],
        depth: 1,
        mediaUrl: 'assets/mytest.jpg',
        mediaType: 'image',
      ),
    ],
  ),
];

// Test data for thread screen
final List<Message> dummyMessages = [
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
