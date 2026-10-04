#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d)"
  export TEST_BIN="$TEST_ROOT/bin"
  export LIVE_PLIST="$TEST_ROOT/live.plist"
  export IMPORTED_PLIST="$TEST_ROOT/imported.plist"
  mkdir -p "$TEST_BIN"

  cat > "$TEST_BIN/defaults" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  export)
    cp "$LIVE_PLIST" "$3"
    ;;
  import)
    cp "$3" "$IMPORTED_PLIST"
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$TEST_BIN/defaults"

  cat > "$LIVE_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>inputPriorities</key><array><string>old-device</string></array>
  <key>knownDevices</key><data>Y2FjaGU=</data>
</dict></plist>
EOF
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "AudioPriorityBar config merges managed keys without deleting its device cache" {
  local config="$TEST_ROOT/preferences.plist"
  cat > "$config" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>currentMode</key><string>speaker</string>
  <key>inputPriorities</key><array><string>vocaster</string><string>webcam</string></array>
</dict></plist>
EOF

  run env PATH="$TEST_BIN:/usr/bin:/bin" \
    "$REPO_ROOT/scripts/configure-audio-priority-bar.sh" --config "$config"

  [ "$status" -eq 0 ]
  [ "$(plutil -extract currentMode raw -o - "$IMPORTED_PLIST")" = "speaker" ]
  [ "$(plutil -extract inputPriorities.0 raw -o - "$IMPORTED_PLIST")" = "vocaster" ]
  [ "$(plutil -extract inputPriorities.1 raw -o - "$IMPORTED_PLIST")" = "webcam" ]
  [ "$(plutil -extract knownDevices raw -o - "$IMPORTED_PLIST")" = "Y2FjaGU=" ]
}

@test "AudioPriorityBar portable defaults preserve machine-local device selections" {
  cat > "$LIVE_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>inputPriorities</key><array><string>local-microphone</string></array>
  <key>speakerPriorities</key><array><string>local-speaker</string></array>
  <key>hiddenMics</key><array><string>local-hidden-microphone</string></array>
  <key>hiddenSpeakers</key><array><string>local-hidden-speaker</string></array>
  <key>knownDevices</key><data>Y2FjaGU=</data>
</dict></plist>
EOF

  run env PATH="$TEST_BIN:/usr/bin:/bin" \
    "$REPO_ROOT/scripts/configure-audio-priority-bar.sh" \
    --config "$REPO_ROOT/audio-priority-bar/.config/audio-priority-bar/preferences.plist"

  [ "$status" -eq 0 ]
  [ "$(plutil -extract inputPriorities.0 raw -o - "$IMPORTED_PLIST")" = "local-microphone" ]
  [ "$(plutil -extract speakerPriorities.0 raw -o - "$IMPORTED_PLIST")" = "local-speaker" ]
  [ "$(plutil -extract hiddenMics.0 raw -o - "$IMPORTED_PLIST")" = "local-hidden-microphone" ]
  [ "$(plutil -extract hiddenSpeakers.0 raw -o - "$IMPORTED_PLIST")" = "local-hidden-speaker" ]
  [ "$(plutil -extract knownDevices raw -o - "$IMPORTED_PLIST")" = "Y2FjaGU=" ]
}
