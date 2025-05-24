#!/bin/bash

# Define colors using tput for better compatibility
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
RESET=$(tput sgr0) # Reset colors

# --- Distribution Detection ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|parrot|kali) # Debian-based distributions
                echo "debian"
                ;;
            arch|manjaro|endeavouros|blackarch|athena) # Arch-based distributions 
                echo "arch"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# --- Function to display animated installation progress and capture errors ---
animate_install() {
    local tool_name="$1"
    local install_command="$2"
    local pid=""
    local delay=0.1
    local progress_chars="/-\|"
    local i=0
    # Create a temporary file for capturing stderr
    local error_file=$(mktemp /tmp/script_error_output_XXXXXX.log)

    echo -n "${BLUE}Installing ${tool_name}:${RESET} "

    # Run the installation command in the background, redirecting stderr to the temp file
    # Use 'eval' to execute the command string correctly
    eval "$install_command" > /dev/null 2> "$error_file" &
    pid=$! # Get the process ID of the background command

    # Simple animation loop
    while kill -0 $pid 2>/dev/null; do
        echo -n "${YELLOW}${progress_chars:$i:1}${RESET}"
        i=$(( (i+1) % ${#progress_chars} ))
        sleep $delay
        echo -en "\b" # Erase the last character
    done

    # Wait for the background process to finish and capture exit status
    wait $pid
    local exit_status=$?

    # Clear the animation characters
    echo -en "\b\b\b" # Clear a few characters just in case

    if [ $exit_status -eq 0 ]; then
        echo -e "${GREEN}100%${RESET} ${GREEN}Done!${RESET}"
        # Clean up the temporary error file on success
        rm -f "$error_file"
    else
        echo -e "${RED}Failed!${RESET}"
        echo "${RED}Command failed: ${install_command}${RESET}"
        # Display the captured error output
        if [ -s "$error_file" ]; then # Check if the error file is not empty
            echo "${RED}Error Output:${RESET}"
            cat "$error_file"
        fi
        # Clean up the temporary error file on failure
        rm -f "$error_file"
        return 1 # Indicate failure
    fi
    return 0 # Indicate success
}

# --- Main Script ---

echo "${BLUE}Welcome to the Network Tool Installer!${RESET}"
echo ""
echo "${YELLOW}It is recommended to run this script with sudo: sudo ./install_tools.sh${RESET}"
echo ""

# Detect the distribution
DISTRO=$(detect_distro)

if [ "$DISTRO" == "unknown" ]; then
    echo "${RED}Error: Could not detect supported distribution (Debian/Ubuntu/Parrot/Kali or Arch/Manjaro/EndeavourOS/BlackArch/Athena).${RESET}"
    echo "${RED}Installation cannot proceed.${RED}"
    exit 1
fi

echo "${BLUE}Detected distribution: ${DISTRO}${RESET}"
echo ""

# Ask user preference for update
echo "Do you want to update/upgrade your software packages:"
echo "  A) Before installation"
echo "  B) After installation"
echo "Enter your choice (A or B): "

read -r update_choice

# Convert choice to uppercase
update_choice=$(echo "$update_choice" | tr '[:lower:]' '[:upper:]')

# Define the tools and their installation commands based on distribution
declare -A tools

if [ "$DISTRO" == "debian" ]; then
    tools=(
        ["xprobe2"]="sudo apt-get install -y xprobe2"
        ["xprobe"]="sudo apt-get install -y xprobe" # Fallback for xprobe2
        ["etherape"]="sudo apt-get -y install etherape"
        ["backdoor-factory"]="sudo apt-get -y install backdoor-factory" # Note: backdoor-factory might require specific repositories or methods depending on your distro version. apt-get might not find it on all systems.
        ["can-utils"]="sudo apt-get -y install can-utils"
    )
    UPDATE_CMD="sudo apt update"
    UPGRADE_CMD="sudo apt upgrade -y"
elif [ "$DISTRO" == "arch" ]; then
    tools=(
        ["xprobe2"]="sudo pacman -S --noconfirm xprobe2"
        ["xprobe"]="sudo pacman -S --noconfirm xprobe" # Fallback for xprobe2
        ["etherape"]="sudo pacman -S --noconfirm etherape"
        ["backdoor-factory"]="sudo pacman -S --noconfirm backdoor-factory" # Note: backdoor-factory might not be in the official Arch repos. AUR might be needed.
        ["can-utils"]="sudo pacman -S --noconfirm can-utils"
    )
    # pacman -Syyu syncs package databases and upgrades all packages
    UPDATE_UPGRADE_CMD="sudo pacman -Syyu --noconfirm"
fi

# Function to perform installation of all tools
perform_installation() {
    echo ""
    echo "${BLUE}Starting tool installations...${RESET}"
    # Iterate over the primary tools, handling fallbacks explicitly
    local primary_tools=("xprobe2" "etherape" "backdoor-factory" "can-utils")

    for tool in "${primary_tools[@]}"; do
        case "$tool" in
            "xprobe2")
                # Special handling for xprobe2 with fallback to xprobe
                animate_install "xprobe2" "${tools['xprobe2']}"
                if [ $? -ne 0 ]; then # Check if xprobe2 installation failed
                    echo "${YELLOW}Installation of xprobe2 failed, trying xprobe...${RESET}"
                    animate_install "xprobe" "${tools['xprobe']}"
                    # Note: We don't check the exit status of xprobe installation here,
                    # but animate_install will report if it failed.
                fi
                ;;
            *)
                # Standard installation for other tools
                if [[ -v tools["$tool"] ]]; then # Check if the tool is defined for the current distro
                    animate_install "$tool" "${tools[$tool]}"
                else
                    echo "${YELLOW}Tool '$tool' is not defined for ${DISTRO} distribution. Skipping.${RESET}"
                fi
                ;;
        esac
    done
    echo "${BLUE}Installation process finished.${RESET}"
}

# Handle user choice for update/upgrade
case "$update_choice" in
    A)
        echo ""
        if [ "$DISTRO" == "debian" ]; then
            echo "${BLUE}Updating and upgrading packages before installation...${RESET}"
            $UPDATE_CMD && $UPGRADE_CMD
            if [ $? -eq 0 ]; then
                echo "${GREEN}Update and upgrade complete.${RESET}"
                perform_installation
            else
                echo "${RED}Update or upgrade failed. Installation aborted.${RED}"
                exit 1
            fi
        elif [ "$DISTRO" == "arch" ]; then
             echo "${BLUE}Syncing package databases and upgrading packages before installation...${RESET}"
             $UPDATE_UPGRADE_CMD
             if [ $? -eq 0 ]; then
                echo "${GREEN}Sync and upgrade complete.${RESET}"
                perform_installation
             else
                echo "${RED}Sync or upgrade failed. Installation aborted.${RED}"
                exit 1
             fi
        fi
        ;;
    B)
        perform_installation
        echo ""
        if [ "$DISTRO" == "debian" ]; then
            echo "${BLUE}Updating and upgrading packages after installation...${RESET}"
            $UPDATE_CMD && $UPGRADE_CMD
            if [ $? -eq 0 ]; then
                echo "${GREEN}Update and upgrade complete.${RESET}"
            else
                echo "${RED}Update or upgrade failed.${RED}"
            fi
        elif [ "$DISTRO" == "arch" ]; then
            echo "${BLUE}Syncing package databases and upgrading packages after installation...${RESET}"
            $UPDATE_UPGRADE_CMD
            if [ $? -eq 0 ]; then
                echo "${GREEN}Sync and upgrade complete.${RESET}"
            else
                echo "${RED}Sync or upgrade failed.${RED}"
            fi
        fi
        ;;
    *)
        echo "${RED}Invalid choice. Please run the script again and enter A or B.${RED}"
        exit 1
        ;;
esac

echo ""
echo "${BLUE}Script finished.${RESET}"
