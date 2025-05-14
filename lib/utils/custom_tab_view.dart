import 'package:flutter/material.dart';

class CustomTabView extends StatelessWidget {
  final TabController controller;
  final List<Widget> children;
  final bool disableSwipe;

  const CustomTabView({
    Key? key,
    required this.controller,
    required this.children,
    this.disableSwipe = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: controller,
      physics: disableSwipe ? const NeverScrollableScrollPhysics() : null,
      children: children,
    );
  }
}

/// A PageView-based implementation that ensures consistent right-to-left swiping for navigation
class AnimatedTabView extends StatefulWidget {
  final TabController controller;
  final List<Widget> children;
  final bool disableSwipe;

  const AnimatedTabView({
    Key? key,
    required this.controller,
    required this.children,
    this.disableSwipe = false,
  }) : super(key: key);

  @override
  State<AnimatedTabView> createState() => _AnimatedTabViewState();
}

class _AnimatedTabViewState extends State<AnimatedTabView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.controller.index);
    widget.controller.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _pageController.dispose();
    widget.controller.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    // When tab controller changes, update page view
    if (widget.controller.indexIsChanging ||
        (_pageController.hasClients &&
            _pageController.page?.round() != widget.controller.index)) {
      _pageController.animateToPage(
        widget.controller.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics:
          widget.disableSwipe ? const NeverScrollableScrollPhysics() : null,
      children: widget.children,
      onPageChanged: (index) {
        // Update the tab controller when PageView is swiped
        if (index != widget.controller.index) {
          widget.controller.animateTo(index);
        }
      },
    );
  }
}
