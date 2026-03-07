#!/bin/bash
INPUT_IMG="/Users/jutaehyeong/.gemini/antigravity/brain/f040cf0e-5776-4762-96d1-9162860d2ca3/app_icon_flat_1772892459215.png"
APPICONSET="macos/Runner/Assets.xcassets/AppIcon.appiconset"

# Because the AI image has a white background, we need to make it somewhat transparent 
# or use it directly (macOS app icons can have a background or be transparent).
# Since the prompt requested "flat mark", let's make it a 1024x1024 flat icon.
sips -z 1024 1024 "$INPUT_IMG" --out icon_1024_flat.png

# Generate sizes
sips -z 16 16 icon_1024_flat.png --out "$APPICONSET/app_icon_16.png"
sips -z 32 32 icon_1024_flat.png --out "$APPICONSET/app_icon_32.png"
sips -z 64 64 icon_1024_flat.png --out "$APPICONSET/app_icon_64.png"
sips -z 128 128 icon_1024_flat.png --out "$APPICONSET/app_icon_128.png"
sips -z 256 256 icon_1024_flat.png --out "$APPICONSET/app_icon_256.png"
sips -z 512 512 icon_1024_flat.png --out "$APPICONSET/app_icon_512.png"
sips -z 1024 1024 icon_1024_flat.png --out "$APPICONSET/app_icon_1024.png"

echo "Done"
