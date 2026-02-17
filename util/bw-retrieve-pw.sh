#!/bin/bash
set -euo pipefail

# Check for required dependencies
if ! command -v bw &> /dev/null; then
    echo "Error: Bitwarden CLI (bw) is not installed or not in PATH"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Install it with your package manager (e.g., apt install jq, brew install jq)"
    exit 1
fi

# Check login status and handle authentication
needs_lock=false
if ! bw login --check &> /dev/null; then
    echo "Not logged in to Bitwarden. Please log in:"
    if ! bw login; then
        echo "Login failed"
        exit 1
    fi
fi

# Check if vault is locked and unlock if needed
if bw unlock --check &> /dev/null; then
    echo "Vault is already unlocked"
else
    echo "Vault is locked. Please unlock:"
    unlock_output=$(bw unlock --raw)
    if [ -z "$unlock_output" ]; then
        echo "Unlock failed"
        exit 1
    fi
    export BW_SESSION="$unlock_output"
    needs_lock=true
fi

# Ensure vault is locked on exit
trap 'if [ "$needs_lock" = true ]; then bw lock &> /dev/null; echo "Vault locked"; fi' EXIT

# Prompt user for search term
read -p "Enter search term: " search_term

# Search Bitwarden items and store results
items=$(bw list items --search "$search_term" 2>&1)

# Check if command failed or returned invalid JSON
if [ $? -ne 0 ] || ! echo "$items" | jq empty 2>/dev/null; then
    echo "Error retrieving items from Bitwarden"
    exit 1
fi

# Check if any items were found
if [ "$items" == "[]" ]; then
    echo "No items found matching '$search_term'"
    exit 1
fi

# Parse and display items with numbered keys
echo ""
echo "Found items:"
echo "------------"

# Store item IDs in an array
declare -a item_ids
declare -a item_names

index=1
while IFS= read -r line; do
    # Handle potentially malformed JSON lines
    if ! echo "$line" | jq empty 2>/dev/null; then
        continue
    fi
    
    id=$(echo "$line" | jq -r '.id // empty')
    name=$(echo "$line" | jq -r '.name // empty')
    
    # Skip if id or name is empty
    if [ -z "$id" ] || [ -z "$name" ]; then
        continue
    fi
    
    item_ids+=("$id")
    item_names+=("$name")
    
    # Escape special characters in name for display
    display_name=$(printf '%s' "$name" | tr '\n\r\t' ' ' | tr -s ' ')
    echo "$index) $display_name"
    ((index++))
done < <(echo "$items" | jq -c '.[]')

# Check if we actually found any valid items
if [ ${#item_ids[@]} -eq 0 ]; then
    echo "No valid items found"
    exit 1
fi

# Prompt user to select an item
echo ""
read -p "Select item number (1-$((index-1))): " selection

# Validate selection
if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $((index-1)) ]; then
    echo "Invalid selection"
    exit 1
fi

# Get the selected item's ID (arrays are 0-indexed, so subtract 1)
selected_id="${item_ids[$((selection-1))]}"
selected_name="${item_names[$((selection-1))]}"

# Retrieve the password for the selected item
password=$(bw get password "$selected_id" 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    if echo "$password" | grep -q "Not found"; then
        echo "Error: Item '$selected_name' does not have a password field"
        echo "This might be a secure note, identity, or card item without a password"
    else
        echo "Error retrieving password for item: $selected_name"
    fi
    exit 1
fi

if [ -z "$password" ]; then
    echo "Error: Password is empty for item: $selected_name"
    exit 1
fi

# Copy password to clipboard
if command -v xclip &> /dev/null; then
    printf '%s' "$password" | xclip -selection clipboard
    echo "Password for '$selected_name' copied to clipboard!"
elif command -v wl-copy &> /dev/null; then
    printf '%s' "$password" | wl-copy
    echo "Password for '$selected_name' copied to clipboard!"
elif command -v pbcopy &> /dev/null; then
    printf '%s' "$password" | pbcopy
    echo "Password for '$selected_name' copied to clipboard!"
else
    echo "Error: No clipboard utility found (xclip, wl-copy, or pbcopy)"
    echo "Please install one to use this script securely"
    exit 1
fi