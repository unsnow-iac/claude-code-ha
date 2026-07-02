#!/bin/bash

# Claude Authentication Helper
# Provides alternative authentication methods when clipboard paste doesn't work

show_auth_menu() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               🔐 Claude Authentication Helper                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Having trouble pasting the authentication code?"
    echo ""
    echo "Options:"
    echo "  1) 📋 Manual input (type or paste the code)"
    echo "  2) 📁 Read code from file (/config/auth-code.txt)"
    echo "  3) 🔄 Retry standard authentication"
    echo "  4) ❌ Exit"
    echo ""
}

manual_auth_input() {
    echo ""
    echo "Please enter your authentication code:"
    echo "(You can try pasting with Ctrl+Shift+V, right-click, or type manually)"
    echo ""
    echo -n "Code: "
    read -r auth_code

    if [ -z "$auth_code" ]; then
        echo "❌ No code provided"
        return 1
    fi

    echo ""
    echo "✅ Code received. Starting Claude authentication..."
    sleep 1

    # Pipe the code straight to Claude — never write it to a file. (A previous
    # version staged it in /tmp/claude-auth-code and left the plaintext secret
    # behind.)
    printf '%s\n' "$auth_code" | claude
}

read_auth_from_file() {
    local auth_file="/config/auth-code.txt"

    echo ""
    echo "Looking for authentication code in: $auth_file"

    if [ -f "$auth_file" ]; then
        auth_code=$(cat "$auth_file")
        # Delete the on-disk secret immediately after reading it — before doing
        # anything else — so the plaintext code never lingers in /config (which may
        # be backed up or synced) regardless of what happens next.
        rm -f "$auth_file"
        echo "🧹 Cleaned up auth code file"

        if [ -z "$auth_code" ]; then
            echo "❌ File exists but is empty"
            return 1
        fi

        echo "✅ Code found. Starting Claude authentication..."
        sleep 1

        # Pipe the code to Claude (already removed from disk above)
        printf '%s\n' "$auth_code" | claude
    else
        echo "❌ File not found: $auth_file"
        echo ""
        echo "To use this method:"
        echo "1. Create the file in Home Assistant's config directory"
        echo "2. Paste your authentication code in the file"
        echo "3. Save the file and try again"
        return 1
    fi
}

retry_standard_auth() {
    echo ""
    echo "🔄 Starting standard Claude authentication..."
    echo ""
    echo "Tips for pasting in the web terminal:"
    echo "• Try Ctrl+Shift+V"
    echo "• Try right-clicking"
    echo "• Try the browser's Edit menu > Paste"
    echo "• On mobile, long-press may show paste option"
    echo ""
    sleep 2
    exec claude
}

main() {
    while true; do
        show_auth_menu

        echo -n "Enter your choice [1-4]: "
        read -r choice

        case "$choice" in
            1)
                manual_auth_input
                if [ $? -eq 0 ]; then
                    exit 0
                fi
                echo ""
                echo "Press Enter to continue..."
                read -r
                ;;
            2)
                read_auth_from_file
                if [ $? -eq 0 ]; then
                    exit 0
                fi
                echo ""
                echo "Press Enter to continue..."
                read -r
                ;;
            3)
                retry_standard_auth
                ;;
            4)
                echo "👋 Exiting..."
                exit 0
                ;;
            *)
                echo "❌ Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Run main function
main "$@"