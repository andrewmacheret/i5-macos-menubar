#!/bin/bash
# Writes the update feed the app checks, with one update in it, to stdout.
# Usage: scripts/appcast.sh <zip> <download url> <version> <build number>
# Signs with SPARKLE_ED_KEY if it's set, or with the key in your Keychain if not.
set -euo pipefail

zip=$1 url=$2 version=$3 build=$4
tool=.build/artifacts/sparkle/Sparkle/bin/sign_update

if [ -n "${SPARKLE_ED_KEY:-}" ]; then
  # printf is built into bash, so the key never shows up in the process list
  attrs=$(printf '%s' "$SPARKLE_ED_KEY" | "$tool" --ed-key-file - "$zip")
else
  attrs=$("$tool" --account i5-express "$zip")
fi

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>I-5 Express</title>
    <item>
      <title>Version $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="$url" $attrs type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
