#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <lab-project-directory-name>"
    exit 1
fi

LABS_PROJECT_DIR_NAME="$1"

# Navigate to the script's directory, then move up to determine the absolute path of the parent directory
PARENT_DIR=$(cd "$(dirname "$0")" && cd .. && pwd)
TARGET_DIR="$PARENT_DIR/$LABS_PROJECT_DIR_NAME"

# Check and create the target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    echo "Created labs project directory at $TARGET_DIR"
else
    echo "Labs project directory already exists at $TARGET_DIR"
fi

# Proceed to create the documentation structure within the target directory
MODULE_NAME=$(basename -- "$TARGET_DIR")
DOCS_DIR="$TARGET_DIR/docs"
MODULES_DIR="$DOCS_DIR/modules/$MODULE_NAME"
PAGES_DIR="$MODULES_DIR/pages"
IMAGES_DIR="$MODULES_DIR/images"
EXAMPLES_DIR="$MODULES_DIR/examples"
ATTACHMENTS_DIR="$MODULES_DIR/attachments"
PARTIALS_DIR="$MODULES_DIR/partials"

mkdir -p "$PAGES_DIR" "$IMAGES_DIR" "$EXAMPLES_DIR" "$ATTACHMENTS_DIR" "$PARTIALS_DIR"
echo "Antora documentation structure created in $TARGET_DIR."

# Create the antora.yml file with minimal content
ANTORA_YML="$DOCS_DIR/antora.yml"
if [ ! -f "$ANTORA_YML" ]; then
    echo "name: redpanda-labs" > "$ANTORA_YML"
    echo "version: ~" >> "$ANTORA_YML"
    echo "Antora component descriptor (antora.yml) created."
else
    echo "Antora component descriptor (antora.yml) already exists, skipping."
fi

# Add a README.adoc file to the docs directory
README_TEMPLATE="$(dirname "$0")/readme-template.adoc"
README_TARGET="$TARGET_DIR/README.adoc"

if [ -f "$README_TEMPLATE" ]; then
    cp "$README_TEMPLATE" "$README_TARGET"
    echo "README.adoc created in $DOCS_DIR."
else
    echo "readme-template.adoc not found. Skipping README.adoc creation."
fi

echo "Antora documentation structure setup complete for '$MODULE_NAME'."
