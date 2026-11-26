#!/usr/bin/env bash
# Build a release of the direct download (Developer ID, ADR-002): spora-mac's
# release ceremony, the counterpart of spora-win's and spora-android's
# scripts/release.sh.
#
#   DEVELOPMENT_TEAM=<team ID> scripts/release.sh
#
# Run it on the build Mac, in a git checkout with the core's checkout beside
# it (../spora), inside the logged-in user's session: signing, notarytool and
# Sparkle's EdDSA key all live in the login keychain (over SSH:
# sudo launchctl asuser <uid> sudo -u <user> env DEVELOPMENT_TEAM=… scripts/release.sh).
#
#   1. Refuses a dirty tree, and a ../spora that is dirty or not exactly at
#      .github/core-ref (the ref CI builds against).
#   2. The version is MARKETING_VERSION in project.yml, bumped by hand in the
#      commit the release tags; the build number is the number of commits in
#      HEAD's history (git rev-list --count HEAD), so it rises with every
#      commit on main and a rebuild of one commit gets the same one. Sparkle
#      offers an update only over a lower build number, and sysextd replaces
#      the extension only when the version changes.
#   3. Builds the core's release library (build-ffi-apple.sh, no --debug), then
#      SporaDirect in Release, universal, signed with Developer ID as
#      `dev.sh --direct build` signs it (the profiles named by
#      SPORA_PROFILE_APP / SPORA_PROFILE_TUNNEL).
#   4. Notarizes and staples the app (keychain profile SPORA_NOTARY_PROFILE,
#      default spora-notary), puts it in a DMG beside a link to /Applications,
#      signs the DMG, notarizes and staples it too.
#   5. Signs the DMG for Sparkle (sign_update, the EdDSA key in the login
#      keychain), writes its appcast entry, and adds it to dist/appcast.xml
#      (the appcast as last published: keep it, or download the published one
#      from the feed, SPORA_UPDATE_FEED in project.yml, first).
#   6. On a clean tree, offers an annotated v<version> tag.
#
# It publishes nothing. Publishing is its own step, on spora.to (spora-web's
# AGENTS.md has how): the DMG first, then appcast.xml, which names the DMG
# relative to itself and is refused while a DMG it names is not there.
set -euo pipefail
cd "$(dirname "$0")/.."

CORE_DIR=../spora
DERIVED=build-release
DIST=dist
APPCAST="$DIST/appcast.xml"

die() { echo "error: $*" >&2; exit 1; }
confirm() { local a; read -rp "$1 [y/N] " a; [[ $a == [yY] || $a == yes || $a == YES ]]; }

[ "$(uname)" = Darwin ] || die "run it on the build Mac"
for tool in xcodegen cargo; do command -v "$tool" >/dev/null || die "$tool is not on PATH"; done
TEAM="${DEVELOPMENT_TEAM:-}"
[ -n "$TEAM" ] || die "DEVELOPMENT_TEAM=<team ID> names the team that signs (never written into the repo)"

# --- 1. exactly what is committed, against exactly the pinned core
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git checkout"
[ "$(git rev-parse --is-shallow-repository)" = false ] || die "a shallow clone: the build number counts the whole history (git fetch --unshallow)"
if [ -n "$(git status --porcelain)" ]; then
  git status --short | head -10 >&2
  die "the working tree is not clean: a release is built from a commit"
fi
[ -d "$CORE_DIR/.git" ] || die "no core checkout at $CORE_DIR"
PIN=$(grep -v '^#' .github/core-ref | head -1 | tr -d '[:space:]')
PIN_SHA=$(git -C "$CORE_DIR" rev-parse -q --verify "$PIN^{commit}") \
  || die "core ref '$PIN' (.github/core-ref) not found in $CORE_DIR: git -C $CORE_DIR fetch --tags"
CORE_SHA=$(git -C "$CORE_DIR" rev-parse HEAD)
if [ "$CORE_SHA" != "$PIN_SHA" ]; then
  echo "error: $CORE_DIR is at $(git -C "$CORE_DIR" describe --tags --always HEAD)," >&2
  echo "       but .github/core-ref pins $PIN ($(git -C "$CORE_DIR" rev-parse --short "$PIN_SHA")):" >&2
  echo "         git -C $CORE_DIR checkout $PIN" >&2
  echo "       (or bump .github/core-ref, commit, and re-run)" >&2
  exit 1
fi
if [ -n "$(git -C "$CORE_DIR" status --porcelain --untracked-files=no)" ]; then
  git -C "$CORE_DIR" status --short --untracked-files=no | head -10 >&2
  die "$CORE_DIR has uncommitted changes: the build would not be $PIN"
fi
echo "core: $PIN ($CORE_SHA)"

# --- 2. version and build number
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION in project.yml is '$VERSION', not x.y.z"
BUILD=$(git rev-list --count HEAD)
TAG="v$VERSION"
DMG_NAME="Spora-$VERSION.dmg"
echo "version: $VERSION (build $BUILD), commit $(git rev-parse --short HEAD)"
if TAG_SHA=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}"); then
  [ "$TAG_SHA" = "$(git rev-parse HEAD)" ] \
    || die "$TAG already tags another commit ($(git rev-parse --short "$TAG_SHA")): bump MARKETING_VERSION"
  echo "note: $TAG already tags HEAD: this rebuilds that release"
fi
if [ -f "$APPCAST" ]; then
  LATEST=$(sed -n 's#.*<sparkle:version>\([0-9]*\)</sparkle:version>.*#\1#p' "$APPCAST" | sort -n | tail -1)
  if [ -n "$LATEST" ] && [ "$BUILD" -le "$LATEST" ]; then
    grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST" \
      && die "$APPCAST already has build $BUILD" \
      || die "build $BUILD is not above the appcast's newest ($LATEST): Sparkle would not offer it"
  fi
else
  echo "note: no $APPCAST yet: starting a new appcast (download the published one from the feed first if there is one)"
fi
confirm "Build release $VERSION (build $BUILD)?" || { echo "aborted"; exit 1; }
mkdir -p "$DIST"

# --- 3. the core's release build, then the app
SPORA_MAC_OUT="$PWD/rust-out" "$CORE_DIR/build-ffi-apple.sh"
xcodegen generate >/dev/null
rm -rf "$DERIVED/Build/Products/Release"
# dev.sh --direct build's signing, with the release's version and build number.
xcodebuild -project Spora.xcodeproj -scheme SporaDirect -configuration Release \
  -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  SPORA_PROFILE_APP="${SPORA_PROFILE_APP:-Spora macOS}" \
  SPORA_PROFILE_TUNNEL="${SPORA_PROFILE_TUNNEL:-Spora macOS Tunnel}" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  build > "$DIST/xcodebuild.log" 2>&1 || { tail -30 "$DIST/xcodebuild.log" >&2; die "the build failed ($DIST/xcodebuild.log)"; }
APP="$DERIVED/Build/Products/Release/Spora.app"
SYSEXT="$APP/Contents/Library/SystemExtensions/to.spora.macos.tunnel.systemextension"
[ -d "$APP" ] || die "no $APP"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
for b in "$APP" "$SYSEXT"; do
  [ "$(plist "$b" CFBundleShortVersionString)" = "$VERSION" ] && [ "$(plist "$b" CFBundleVersion)" = "$BUILD" ] \
    || die "$b is not $VERSION ($BUILD)"
done
FEED=$(plist "$APP" SUFeedURL)
[[ $FEED == https://* ]] || die "SUFeedURL is '$FEED', not an https feed"
[[ $(plist "$APP" SUPublicEDKey) =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "SUPublicEDKey is not an EdDSA public key"
for arch in arm64 x86_64; do # one per -verify_arch
  lipo "$APP/Contents/MacOS/Spora" -verify_arch "$arch" || die "the app has no $arch"
done
codesign --verify --deep --strict "$APP" || die "the app's signature does not verify"
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)
[ -n "$IDENTITY" ] || die "the app is not signed with Developer ID"
echo "signed: $IDENTITY"

# --- 4. notarized app, notarized DMG
NOTARY="${SPORA_NOTARY_PROFILE:-spora-notary}"
notarize() {
  local out
  out=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY" --wait 2>&1) || true
  echo "$out"
  grep -q 'status: Accepted' <<<"$out"
}
OUT="$DIST/$VERSION"
rm -rf "$OUT"; mkdir -p "$OUT"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
notarize "$OUT/notarize.zip" || die "Apple did not accept the app"
rm -f "$OUT/notarize.zip"
xcrun stapler staple "$APP"
spctl --assess --type execute -v "$APP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/Spora"
ditto "$APP" "$STAGE/Spora/Spora.app"
ln -s /Applications "$STAGE/Spora/Applications"
DMG="$OUT/$DMG_NAME"
hdiutil create -volname Spora -srcfolder "$STAGE/Spora" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG" || die "Apple did not accept the DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# --- 5. Sparkle's signature and the appcast
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "$SPARKLE_BIN/sign_update" ] || die "no sign_update in $SPARKLE_BIN"
ED=$("$SPARKLE_BIN/sign_update" "$DMG") || die "sign_update failed (is the EdDSA key in this keychain?)"
[[ $ED == sparkle:edSignature=* ]] || die "sign_update said: $ED"
MIN_OS=$(plist "$APP" LSMinimumSystemVersion)
cat > "$OUT/appcast-item.xml" <<EOF
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <enclosure url="$DMG_NAME" type="application/octet-stream" $ED/>
    </item>
EOF
if [ ! -f "$APPCAST" ]; then
  cat > "$APPCAST" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Spora</title>
  </channel>
</rss>
EOF
fi
# Newest first: before the first item, or at the end of an empty channel.
awk -v item="$OUT/appcast-item.xml" '
  !done && (/<item>/ || /<\/channel>/) { while ((getline l < item) > 0) print l; done = 1 }
  { print }' "$APPCAST" > "$APPCAST.new"
mv "$APPCAST.new" "$APPCAST"
cp "$APPCAST" "$OUT/appcast.xml"
SHA256=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

echo
echo "built:   $DMG"
echo "sha256:  $SHA256"
echo "appcast: $APPCAST (with $OUT/appcast-item.xml added)"

# --- 6. the tag, for the exact source of this build
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "note: tag $TAG already exists: not re-tagging"
elif confirm "Tag HEAD as $TAG (annotated)?"; then
  git tag -a "$TAG" -m "spora-mac $VERSION (build $BUILD)

core: $PIN ($CORE_SHA)
toolchain: $(xcodebuild -version | tr '\n' ' ')
dmg: $DMG_NAME sha256 $SHA256"
  echo "tagged $TAG: push it with git push origin $TAG"
fi

echo
echo "next: install the DMG on a test Mac (connect, then an update from the previous"
echo "      release), then publish on spora.to: $DMG_NAME first, then appcast.xml"
echo "      (ask first: it reaches every installed copy)."
