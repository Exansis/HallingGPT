#!/bin/bash

# Initialize flags and installation path
NO_DOCKER=0
NO_OLLAMA=0
INSTALL_PATH="$HOME/.open-webui/source"

# Parse command-line arguments
for arg in "$@"; do
    case $arg in
        --no-docker)
        NO_DOCKER=1
        shift # Remove --no-docker from processing
        ;;
        --no-ollama)
        NO_OLLAMA=1
        shift # Remove --no-ollama from processing
        ;;
        --install-path)
        INSTALL_PATH="$2"
        shift # Remove argument name
        shift # Remove argument value
        ;;
        *)
        # Unknown option
        ;;
    esac
done

# Define the base directory as the installation path
BASE_DIR=$(mkdir -p "$INSTALL_PATH" && cd "$INSTALL_PATH" && pwd)
cd "$BASE_DIR"

echo "Installation will proceed in directory: $BASE_DIR"

# Function to clone the Open WebUI repository
clone_repository() {
    if [ -d "$BASE_DIR/open-webui/.git" ]; then
        echo "The Open WebUI repository already exists at $BASE_DIR/open-webui."
    else
        echo "Cloning Open WebUI repository into $BASE_DIR/open-webui..."
        git clone https://github.com/open-webui/open-webui.git "$BASE_DIR/open-webui"
    fi
}

# Function to check if Docker is installed
check_docker() {
    echo "Checking for Docker..."
    if ! command -v docker &> /dev/null; then
        echo "Docker could not be found. Would you like to install Docker? (y/n)"
        read -r choice
        if [ "$choice" = "y" ]; then
            install_docker
        else
            echo "Docker is required for the Docker-based installation."
            echo "Would you like to proceed with the Docker-less installation? (y/N)"
            read -r proceed
            if [ "$proceed" != "y" ]; then
                echo "Exiting the installation script."
                exit 0
            fi
            clone_repository
            dockerless_install
            exit 0
        fi
    else
        echo "Docker is already installed."
    fi
}

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    curl -fsSL get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo docker run --rm hello-world
    if [ $? -ne 0 ]; then
        echo "Docker installation failed. Please check the error messages above."
        exit 1
    fi
    echo "Docker has been successfully installed."
    clone_repository
}

# Function to check for Node.js
check_nodejs() {
    if ! command -v node &> /dev/null; then
        install_nodejs
    else
        echo "Node.js is already installed."
    fi
}

# Function to install Node.js using nvm
install_nodejs() {
    echo "Node.js not found. Installing Node.js using nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    source "$HOME/.nvm/nvm.sh"
    nvm install 20
}

# Function to install Miniconda for Python
install_miniconda() {
    echo "Installing Miniconda for Python dependencies..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda
    source "$HOME/miniconda/etc/profile.d/conda.sh"
    conda init
    conda create -y -n openwebui python=3.11
    conda activate openwebui
}

# Function to install Open WebUI with Docker
install_openwebui_docker() {
    echo "Installing Open WebUI with Docker..."
    docker pull ghcr.io/open-webui/open-webui:latest
    docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:latest
    echo "Open WebUI has been installed and started with Docker. Access it at http://localhost:3000"
}

# Function for Docker-less installation
dockerless_install() {
    echo "Starting Docker-less installation..."

    cd "$BASE_DIR/open-webui" # Change directory to the repository

    # Check and install Node.js if necessary
    check_nodejs

    # Install Miniconda and Python Environment
    install_miniconda

    cp -RPp .env.example .env

    if command -v npm &> /dev/null; then
        npm install
        npm run build
    else
        echo "npm is not available after Node.js installation. Exiting."
        exit 1
    fi

    cd ./backend
    pip install -r requirements.txt -U
    sh start.sh
    echo "Open WebUI has been installed and started without Docker."
}

# Main script starts here
echo "Starting the Open WebUI installation script..."

if [ "$NO_DOCKER" -eq 1 ]; then
    echo "Proceeding with Docker-less installation due to --no-docker flag."
    clone_repository
    dockerless_install
    echo "Installation process has completed."
    exit 0
fi

# Step 1: Check for Docker
check_docker

# Skip Ollama-related options if --no-ollama flag is set
if [ "$NO_OLLAMA" -eq 0 ]; then
    echo "Would you like to install Ollama directly (not inside Docker)? (y/n)"
    read -r install_ollama_directly

    if [ "$install_ollama_directly" = "y" ]; then
        curl -fsSL https://ollama.com/install.sh | sh
        echo "Ollama has been installed directly on the system."
        # No exit here; continue to WebUI installation
    else
        echo "Proceeding with Docker-based installation options..."
        echo "Would you like to install Ollama inside Docker? (y/n)"
        read -r install_ollama

        if [ "$install_ollama" = "y" ]; then
            echo "Installing Ollama with Docker..."
            # Direct call to the script without GPU check, as the script handles it internally
            (cd "$BASE_DIR/open-webui" && chmod +x run-ollama-docker.sh && ./run-ollama-docker.sh)
            echo "Ollama has been installed with Docker."
            # Continue to Docker Compose or direct WebUI installation
        fi
    fi
}

# Ask about Docker Compose only if Ollama wasn't installed by previous options
echo "Would you like to deploy Open WebUI and Ollama together using Docker Compose? (y/n)"
read -r deploy_compose

if [ "$deploy_compose" = "y" ]; then
    echo "Enable GPU support? (y/n)"
    read -r enable_gpu
    compose_cmd="./run-compose.sh"
    if [ "$enable_gpu" = "y" ]; then
        compose_cmd+=" --enable-gpu"
    fi
    echo "Running: $compose_cmd"
    eval "$compose_cmd"
else
    # If not using Docker Compose, just install Open WebUI with Docker
    install_openwebui_docker
fi

echo "Installation process has completed."