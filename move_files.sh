#!/bin/bash

# Define the base directory of your project
BASE_DIR="/Users/boris/coding/nilsApp"

echo "Ensuring target directories exist..."
# Create target directories if they don't already exist
mkdir -p "$BASE_DIR/ViewModels/Child"
mkdir -p "$BASE_DIR/Views/Admin"
mkdir -p "$BASE_DIR/Utils"

echo "Moving files to their correct locations..."

# --- Move ViewModels ---
# Move PlaylistViewModel.swift from Views/Child to ViewModels/Child
if [ -f "$BASE_DIR/Views/Child/PlaylistViewModel.swift" ]; then
    mv "$BASE_DIR/Views/Child/PlaylistViewModel.swift" "$BASE_DIR/ViewModels/Child/PlaylistViewModel.swift"
    echo "Moved PlaylistViewModel.swift"
else
    echo "PlaylistViewModel.swift not found in Views/Child, skipping move."
fi

# Move PodcastViewModel.swift from Views/Child to ViewModels/Child
if [ -f "$BASE_DIR/Views/Child/PodcastViewModel.swift" ]; then
    mv "$BASE_DIR/Views/Child/PodcastViewModel.swift" "$BASE_DIR/ViewModels/Child/PodcastViewModel.swift"
    echo "Moved PodcastViewModel.swift"
else
    echo "PodcastViewModel.swift not found in Views/Child, skipping move."
fi

# --- Move Admin Views ---
# Move AdminView.swift from Views/Child to Views/Admin
if [ -f "$BASE_DIR/Views/Child/AdminView.swift" ]; then
    mv "$BASE_DIR/Views/Child/AdminView.swift" "$BASE_DIR/Views/Admin/AdminView.swift"
    echo "Moved AdminView.swift"
else
    echo "AdminView.swift not found in Views/Child, skipping move."
fi

# Move PINEntryView.swift from Views/Child to Views/Admin
if [ -f "$BASE_DIR/Views/Child/PINEntryView.swift" ]; then
    mv "$BASE_DIR/Views/Child/PINEntryView.swift" "$BASE_DIR/Views/Admin/PINEntryView.swift"
    echo "Moved PINEntryView.swift"
else
    echo "PINEntryView.swift not found in Views/Child, skipping move."
fi

# --- Move Utility Files ---
# Move Constants.swift from Views/Child to Utils
if [ -f "$BASE_DIR/Views/Child/Constants.swift" ]; then
    mv "$BASE_DIR/Views/Child/Constants.swift" "$BASE_DIR/Utils/Constants.swift"
    echo "Moved Constants.swift"
else
    echo "Constants.swift not found in Views/Child, skipping move."
fi

# --- Remove Duplicate Service Files ---
# Remove duplicate SpotifyAPIService.swift from Views/Child
if [ -f "$BASE_DIR/Views/Child/SpotifyAPIService.swift" ]; then
    rm "$BASE_DIR/Views/Child/SpotifyAPIService.swift"
    echo "Removed duplicate SpotifyAPIService.swift from Views/Child."
else
    echo "Duplicate SpotifyAPIService.swift not found in Views/Child, skipping removal."
fi

# Remove duplicate SpotifySDKService.swift from Views/Child
if [ -f "$BASE_DIR/Views/Child/SpotifySDKService.swift" ]; then
    rm "$BASE_DIR/Views/Child/SpotifySDKService.swift"
    echo "Removed duplicate SpotifySDKService.swift from Views/Child."
else
    echo "Duplicate SpotifySDKService.swift not found in Views/Child, skipping removal."
fi

echo "File movement complete. Please ensure to update your Xcode project references by dragging files to new groups and deleting old references."

