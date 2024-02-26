#!/bin/bash

# Display usage if not enough arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <relative-path-to-lab-project-subdirectory> <target-asciidoc-filename>"
    echo "Example: $0 kubernetes/gitops-helm gitops-helm.adoc"
    exit 1
fi

INPUT_PATH="$1"
TARGET_FILENAME="$2"
# Normalize the input path and remove trailing slashes
NORMALIZED_INPUT_PATH=$(echo "$INPUT_PATH" | sed 's:/*$::')
# Extract the first path segment as the lab project root directory
LAB_PROJECT_ROOT_DIR=$(echo "$NORMALIZED_INPUT_PATH" | cut -d '/' -f1)
# Navigate to the script's directory, then move up to determine the absolute path of the parent directory
PARENT_DIR=$(cd "$(dirname "$0")" && cd .. && pwd)
TARGET_DIR="$PARENT_DIR/$LAB_PROJECT_ROOT_DIR"

# Validate LAB_PROJECT_ROOT_DIR existence
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: The specified lab project root directory '$TARGET_DIR' does not exist."
    exit 1
fi

MODULE_NAME="$LAB_PROJECT_ROOT_DIR"

# Define Antora directory paths based on the lab project root
DOCS_DIR="$TARGET_DIR/docs"
MODULES_DIR="$DOCS_DIR/modules/$MODULE_NAME"
PAGES_DIR="$MODULES_DIR/pages"

# Ensure Antora directories exist
mkdir -p "$PAGES_DIR"

# The README.adoc to symlink
README_SOURCE="$NORMALIZED_INPUT_PATH/README.adoc" # Adjusted to be relative
README_DESTINATION="$PAGES_DIR/$TARGET_FILENAME"

# Compute relative path from destination to source using Perl for macOS compatibility
RELATIVE_PATH=$(perl -e 'use File::Spec; print File::Spec->abs2rel(@ARGV)' "$PARENT_DIR/$NORMALIZED_INPUT_PATH" "$PAGES_DIR")

# Check for README existence
if [ ! -f "$PARENT_DIR/$NORMALIZED_INPUT_PATH/README.adoc" ]; then
    echo "Error: README.adoc does not exist in '$PARENT_DIR/$NORMALIZED_INPUT_PATH'."
    exit 1
fi

# Create or update the symlink with relative path
ln -sf "$RELATIVE_PATH/README.adoc" "$README_DESTINATION"
echo "Symlink created/updated for $RELATIVE_PATH/README.adoc -> $README_DESTINATION"

echo "Symlinking complete."
