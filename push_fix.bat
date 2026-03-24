@echo off
echo --- MISE A JOUR MIMO_NDI ---
git add ios/Runner/NDI-Bridging-Header.h
git add ios/configure_xcode.rb
git add .github/workflows/ios-build.yml
git add .gitignore
git add ios/Runner/NDIView.swift
git add ios/Runner/NDIManager.swift
git add lib/main.dart
git add push_fix.bat

echo --- AJOUT DES FICHIERS SDK (SI PRESENTS) ---
git add -f ios/NDISDK/lib/*.part*
git add -f ios/NDISDK/lib/libndi_ios.a

git commit -m "Final Config: Static NDI + Bitcode Disabled + SDK Rejoin Logic"
echo --- ENVOI VERS GITHUB (CLOUD BUILD) ---
git push
pause
