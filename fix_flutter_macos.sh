#!/bin/bash

echo "🧹 Cleaning Flutter project..."
flutter clean

echo "🗑 Removing CocoaPods cache and old pods..."
rm -rf macos/Pods
rm -rf macos/Podfile.lock
rm -rf ~/Library/Caches/CocoaPods
rm -rf ~/.cocoapods

echo "🔧 Resetting Xcode path..."
sudo xcode-select --reset
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

echo "📦 Getting Flutter packages..."
flutter pub get

echo "🍏 Installing CocoaPods with arm64 architecture..."
cd macos || exit
arch -arm64 pod install --repo-update
cd ..

echo "✅ Done! Now run: flutter run -d macos"