#!/bin/sh

CURL="$1"
JQ="$2"

if ! [ -f "$CURL" ]; then
    echo "Need curl to exist; got $CURL"
    exit 1
fi

if ! [ -f "$JQ" ]; then
    echo "Need jq to exist; got $JQ"
    exit 1
fi

installSinglePack() {
    PACKAGE_NAME="$1"
    VERSION="$2"
    EXPECTED_HASH="$3"
    OUTPUT_DIR="$4"

    LINK=$(echo "https://globalcdn.nuget.org/packages/$PACKAGE_NAME.$VERSION.nupkg" | awk '{print tolower($0)}')
    TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir')
    OUTPUT="$TMP/$PACKAGE_NAME.$VERSION.nupkg"

    "$CURL" "$LINK" --output "$OUTPUT" || exit 1

    if [ "$EXPECTED_HASH" = "nocheck" ]; then
        SHASUM=$(shasum "$OUTPUT" | cut -d ' ' -f 1)
        echo "$PACKAGE_NAME" "$VERSION" "$SHASUM"
    elif [ "$(shasum "$OUTPUT" | cut -d ' ' -f 1)" = "$EXPECTED_HASH" ]; then
        export INSTALLSINGLEPACK_RESULT
        INSTALLSINGLEPACK_RESULT="$OUTPUT_DIR/$PACKAGE_NAME/$VERSION"
        mkdir -p "$INSTALLSINGLEPACK_RESULT"
        unzip -qq "$OUTPUT" -d "$INSTALLSINGLEPACK_RESULT" || exit 2
        # TODO sort out exit codes
        mv "$OUTPUT" "$INSTALLSINGLEPACK_RESULT" || exit 3
    else
        echo "Failed: expected $EXPECTED_HASH, got $(shasum "$OUTPUT")"
        exit 3
    fi
}

getDependencies() {
    PACKAGE_NAME="$1"
    VERSION="$2"
    OUTPUT="$3"
    EXPECTED_HASH="$4"

    installSinglePack "$PACKAGE_NAME" "$VERSION" "$EXPECTED_HASH" "$OUTPUT"

    "$JQ" '.packs | keys[] as $k | "\($k) \(.[$k] | .version)"' "$INSTALLSINGLEPACK_RESULT/data/WorkloadManifest.json" | cut -d '"' -f 2 \
    | while read -r SUBPACKAGE SUBPACKAGE_VERSION; do
        installSinglePack "$SUBPACKAGE" "$SUBPACKAGE_VERSION" 'nocheck' "$OUTPUT_DIR"
    done
}

OUTPUT_DIR="$3"
MODE="$4" # e.g. "freeze" or "install"

if [ "$MODE" = "freeze" ]; then
    PACKAGE_NAME="$5" # e.g. "Microsoft.Maui.Essentials.Ref.win"
    VERSION="$6" # e.g. "6.0.408"
    EXPECTED_HASH="$7"
    if [ -z "$EXPECTED_HASH" ]; then
        echo "Provide an expected shasum."
        exit 5
    fi
    # TODO get rid of the OUTPUT_DIR requirement here
    getDependencies "$PACKAGE_NAME" "$VERSION" "$OUTPUT_DIR" "$EXPECTED_HASH"
elif [ "$MODE" = "install" ]; then
    SOURCE_FILE="$5"
    while read -r PACKAGE_NAME VERSION EXPECTED_HASH; do
        installSinglePack "$PACKAGE_NAME" "$VERSION" "$EXPECTED_HASH" "$OUTPUT_DIR"
    done < "$SOURCE_FILE"
else
    echo "Unknown mode $MODE"
    exit 255
fi
