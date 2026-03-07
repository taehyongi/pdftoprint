#!/bin/bash
INPUT_IMG="/Users/jutaehyeong/.gemini/antigravity/brain/f040cf0e-5776-4762-96d1-9162860d2ca3/pdf_to_print_icon_1772892333126.png"
APPICONSET="macos/Runner/Assets.xcassets/AppIcon.appiconset"

# Crop the center 800x800 pixels to remove the background padding
sips -c 800 800 "$INPUT_IMG" --out cropped.png
sips -z 1024 1024 cropped.png --out icon_1024.png

# Generate sizes
sips -z 16 16 icon_1024.png --out "$APPICONSET/app_icon_16.png"
sips -z 32 32 icon_1024.png --out "$APPICONSET/app_icon_32.png"
sips -z 64 64 icon_1024.png --out "$APPICONSET/app_icon_64.png"
sips -z 128 128 icon_1024.png --out "$APPICONSET/app_icon_128.png"
sips -z 256 256 icon_1024.png --out "$APPICONSET/app_icon_256.png"
sips -z 512 512 icon_1024.png --out "$APPICONSET/app_icon_512.png"
sips -z 1024 1024 icon_1024.png --out "$APPICONSET/app_icon_1024.png"

# Contents.json is already populated by Flutter, but mapping might be specific. Let's overwrite exactly.
cat << 'JSON' > "$APPICONSET/Contents.json"
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "app_icon_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "app_icon_32.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "app_icon_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "app_icon_64.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "app_icon_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "app_icon_256.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "app_icon_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "app_icon_512.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "app_icon_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "app_icon_1024.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
JSON
