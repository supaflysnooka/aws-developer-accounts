#!/usr/bin/env python3
import sys
import re

# A simple regex pattern to check for a wide range of Unicode emojis
# This is a good approximation, but a comprehensive check is more complex.
emoji_pattern = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # Emoticons
    "\U0001F300-\U0001F5FF"  # Symbols & Pictographs
    "\U0001F680-\U0001F6FF"  # Transport & Map Symbols
    "\U0001F1E0-\U0001F1FF"  # Flags (iOS)
    "\U00002702-\U000027B0"  # Dingbats
    "\U000024C2-\U0001F251"
    "]+",
    flags=re.UNICODE)

for filename in sys.argv[1:]:
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
            if emoji_pattern.search(content):
                print(f"File '{filename}' contains an emoji")
    except Exception as e:
        print(f"Error processing {filename}: {e}")


