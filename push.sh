#!/bin/bash
# Quick push script for my_app
# Usage: ./push.sh "your commit message"
# If no message is given, a default one with the date/time is used.

set -e  # stop immediately if any command fails

cd "$(dirname "$0")"  # make sure we're running from the project folder

echo "Checking for changes..."
if [ -z "$(git status --porcelain)" ]; then
  echo "Nothing to commit — working tree is clean."
  exit 0
fi

MESSAGE="${1:-Update $(date '+%Y-%m-%d %H:%M')}"

echo "Staging all changes..."
git add .

echo "Committing: $MESSAGE"
git commit -m "$MESSAGE"

echo "Pushing to GitHub..."
git push

echo "Done! Pushed to GitHub."
echo "Go trigger a build on Codemagic when you're ready: https://codemagic.io"
