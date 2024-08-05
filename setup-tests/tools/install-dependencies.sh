#!/bin/bash
set -e

# Function to install Node.js
install_node() {
  if command -v node &>/dev/null; then
    echo "Node.js is already installed. Version: $(node -v)"
  else
    echo "Installing Node.js..."
    curl -fsSL https://fnm.vercel.app/install | bash || { echo "Failed to install fnm"; exit 1; }
    # Load fnm into the current shell
    export PATH=$HOME/.fnm:$PATH
    eval "$(fnm env)" || { echo "Failed to load fnm environment"; exit 1; }
    fnm install --lts || { echo "Failed to install Node.js"; exit 1; }
    fnm use --lts || { echo "Failed to use Node.js"; exit 1; }
    echo "Node.js version: $(node -v)"
  fi
}

# Function to install Rust
install_rust() {
  if command -v rustc &>/dev/null; then
    echo "Rust is already installed. Version: $(rustc --version)"
  else
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || { echo "Failed to install Rust"; exit 1; }
    source $HOME/.cargo/env || { echo "Failed to load Rust environment"; exit 1; }
    echo "Rust version: $(rustc --version)"
  fi
}

# Function to check if expect and jq are installed and install them if they're not
ensure_dependencies_installed() {

    if ! command -v expect &> /dev/null; then
        echo "Expect is not installed. Trying to install..."
        missing_deps=1

        # Detect OS
        case "$(uname -s)" in
            Linux)
                echo "Detected Linux."
                sudo apt-get update && sudo apt-get install expect -y || sudo yum install expect -y || { echo "Failed to install expect"; exit 1; }
                ;;
            Darwin)
                echo "Detected macOS."
                # Assumes Homebrew is installed. If not, it attempts to install Homebrew first.
                if ! command -v brew &> /dev/null; then
                    echo "Homebrew not found."
                    exit 1
                fi
                brew install expect || { echo "Failed to install expect"; exit 1; }
                ;;
            *)
                echo "Unsupported operating system. Please install expect manually."
                exit 1
                ;;
        esac
    fi

    if ! command -v jq &> /dev/null; then
        echo "jq is not installed. Trying to install..."

        # Install jq based on OS
        case "$(uname -s)" in
            Linux)
                sudo apt-get install jq -y || sudo yum install jq -y || { echo "Failed to install jq"; exit 1; }
                ;;
            Darwin)
                brew install jq || { echo "Failed to install jq"; exit 1; }
                ;;
            *)
                echo "Unsupported operating system. Please install jq manually."
                exit 1
                ;;
        esac
    fi

    install_node
    install_rust
}

# Ensure expect and jq are installed
ensure_dependencies_installed

# Function to check rpk installation and display its version
check_rpk_installed() {
    if command -v rpk &>/dev/null; then
        echo "rpk is already installed. Version information:"
        rpk version
        return 0
    else
        return 1
    fi
}

# Determine OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

# Check if rpk is already installed
if check_rpk_installed; then
    exit 0
fi

# Check if running on macOS and use Homebrew to install rpk
if [ "${OS}" == "Darwin" ]; then
    echo "Detected macOS. Attempting to install rpk using Homebrew..."

    # Check if Homebrew is installed
    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found."
        exit 1
    fi

    # Install rpk
    brew install redpanda-data/tap/redpanda || { echo "Failed to install rpk via Homebrew"; exit 1; }

    # Verify installation
    echo "rpk has been installed. Version information:"
    rpk version
    exit 0
fi

# For Linux systems
if [ "${OS}" == "Linux" ]; then
    FILENAME="rpk-linux-amd64.zip"
    URL_BASE="https://github.com/redpanda-data/redpanda/releases"

    # Download latest version of rpk
    echo "Downloading ${FILENAME}..."
    curl -LO "${URL_BASE}/latest/download/${FILENAME}" || { echo "Failed to download rpk"; exit 1; }

    # Ensure the target directory exists
    mkdir -p $HOME/.local/bin || { echo "Failed to create directory"; exit 1; }

    # Unzip the rpk binary to the target directory
    unzip -o "${FILENAME}" -d $HOME/.local/bin || { echo "Failed to unzip rpk"; exit 1; }

    # Remove the downloaded archive
    rm "${FILENAME}" || { echo "Failed to remove downloaded archive"; exit 1; }

    # Add the target directory to PATH for the current session
    export PATH=$HOME/.local/bin:$PATH

    # Add the target directory to PATH for future sessions
    echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc

    # Verify installation
    echo "rpk has been installed. Version information:"
    rpk version
    exit 0
fi

echo "Unsupported operating system: ${OS}"
exit 1
