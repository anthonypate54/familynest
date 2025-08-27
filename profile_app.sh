#!/bin/bash

# Flutter Performance Profiling Script
# Run this to profile memory usage and performance

echo "🔍 Starting Flutter Performance Profiling..."

# Make sure we're in the right directory
cd "$(dirname "$0")"

echo "📊 Available profiling options:"
echo "1. Memory profiling with DevTools"
echo "2. Performance timeline profiling" 
echo "3. Memory allocation tracking"
echo "4. Widget inspector"
echo "5. Network profiling"

echo ""
echo "🚀 Starting Flutter app in profile mode..."

# Start the app in profile mode for better performance analysis
flutter run --profile --verbose

echo ""
echo "📱 App started in profile mode!"
echo ""
echo "🔧 To connect DevTools for profiling:"
echo "1. Open another terminal"
echo "2. Run: flutter pub global activate devtools"
echo "3. Run: flutter pub global run devtools"
echo "4. Open the DevTools URL in your browser"
echo "5. Connect to your running app"
echo ""
echo "🎯 Focus areas for memory profiling:"
echo "- Video thumbnail generation"
echo "- Image loading and caching"
echo "- Widget tree rebuilds"
echo "- Memory allocations during video processing"
echo ""
echo "⚠️  Known issues to watch for:"
echo "- VideoCompress memory usage"
echo "- Thumbnail cache growing indefinitely"
echo "- VideoPlayerController not being disposed"
echo "- Image widgets holding references"
