#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null || ! command -v xcbeautify >/dev/null; then
    echo 'São necessários macOS, Xcode e xcbeautify para validar tvOS.' >&2
    exit 1
fi

xcodebuild -version
xcrun swift --version
xcodebuild -showsdks
xcrun simctl list runtimes

project=AppleTVMultiplatform.xcodeproj
xcodebuild -project "$project" -scheme AppleTVMultiplatform \
    -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build | xcbeautify

# Discover an existing Apple TV simulator; never assume a runtime name or create devices.
simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".tvOS-" in runtime:
        for device in devices[runtime]:
            if device.get("isAvailable") and "Apple TV" in device["name"]:
                print(device["udid"])
                sys.exit(0)
sys.exit("Não existe um simulador tvOS disponível neste Xcode.")
')"

xcodebuild -project "$project" -scheme AppleTVMultiplatformTests \
    -sdk appletvsimulator -destination "platform=tvOS Simulator,id=$simulator_id" \
    -parallel-testing-enabled NO \
    -only-testing:AppleTVMultiplatformTests/LiveTVPreferencesServiceTests \
    -only-testing:AppleTVMultiplatformTests/LiveTVViewModelTests \
    -only-testing:AppleTVMultiplatformTests/XMLTVTimingAndMappingTests \
    -only-testing:AppleTVMultiplatformTests/PlaylistParserTests \
    -only-testing:AppleTVMultiplatformTests/PlaylistServiceTests \
    -only-testing:AppleTVMultiplatformTests/StreamViewModelTests \
    CODE_SIGNING_ALLOWED=NO test | xcbeautify
