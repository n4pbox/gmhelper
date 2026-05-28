#!/bin/bash
# ==========================================
# GMHelper CLI - Bin/Gma Fix
# ==========================================

# --- Script Location ---
SCRIPT_DIR=$(dirname "$(realpath "$0")")
CONFIG_FILE="$SCRIPT_DIR/config.conf"
LOG_FILE="$SCRIPT_DIR/gmhelper.log"

# --- Defaults (overridden by config.conf if present) ---
GMOD_BIN="/your/path/here"
WORK_FOLDER=""

# --- Load External Config ---
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# --- Derived Binary Paths ---
GMAD="$GMOD_BIN/gmad"
GMPUBLISH="$GMOD_BIN/gmpublish"

# --- Colors ---
CYAN='\033;36m'
GREEN='\033;32m'
YELLOW='\033[1;33m'
RED='\033;31m'
MAGENTA='\033;35m'
BOLD='\033[1m'
NC='\033[0m'

# ==========================================
# UTILITY FUNCTIONS
# ==========================================

function log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" >> "$LOG_FILE"
}

function log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

function pause() {
    echo -e "\n${CYAN}Press [ENTER] to return to the menu...${NC}"
    read -r
}

function validate_workshop_id() {
    local id="$1"
    if ! echo "$id" | grep -qE '^[0-9]+$'; then
        echo -e "${RED}Invalid ID! The Workshop ID must contain only numbers.${NC}"
        return 1
    fi
    return 0
}

function validate_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}File not found: $file${NC}"
        return 1
    fi
    return 0
}

function validate_folder() {
    local folder="$1"
    if [ ! -d "$folder" ]; then
        echo -e "${RED}Folder not found: $folder${NC}"
        return 1
    fi
    return 0
}

function backup_if_exists() {
    local file="$1"
    if [ -f "$file" ]; then
        local timestamp
        timestamp=$(date '+%Y%m%d_%H%M')
        # Preserves base name without extension + timestamp + .gma
        local backup="${file%.gma}_${timestamp}.gma"
        mv "$file" "$backup"
        echo -e "${YELLOW}Backup of the previous file created: $(basename "$backup")${NC}"
        log_action "BACKUP: $file -> $backup"
    fi
}

# Fetches the addon name from the Workshop via curl and sanitizes it.
# Returns the sanitized name, or the ID if it's not possible to obtain it.
function fetch_addon_name() {
    local id="$1"

    if ! command -v curl &>/dev/null; then
        echo "$id"
        return
    fi

    local raw_title
    raw_title=$(curl -sL --max-time 8 \
        "https://steamcommunity.com/sharedfiles/filedetails/?id=$id" \
        2>/dev/null \
        | grep -o '<title>[^<]*</title>' \
        | sed 's/<title>//;s/<\/title>//' \
        | head -n 1)

    # The page title follows the pattern: "Steam Workshop::Addon Name"
    local name
    name=$(echo "$raw_title" | sed 's/.*Steam Workshop::\(.*\)/\1/')

    # If nothing was extracted or the substitution failed (no "::")
    if [ -z "$name" ] || [ "$name" = "$raw_title" ]; then
        echo "$id"
        return
    fi

    # Sanitization: lowercase, removes everything that is not alphanumeric
    local sanitized
    sanitized=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')

    if [ -z "$sanitized" ]; then
        echo "$id"
        return
    fi

    echo "$sanitized"
}

# Asks the user if they want to use the addon name as the folder name.
# Prints the resolved name to stdout (for capture with $()).
# Status messages go to stderr to avoid polluting the capture.
function ask_use_addon_name() {
    local id="$1"
    local resolved="$id"

    if command -v curl &>/dev/null; then
        read -p "Try using the addon name as the folder name? (y/N): " use_name
        if [[ "$use_name" =~ ^[yYsS]$ ]]; then
            echo -e "${CYAN}Fetching name from Workshop...${NC}" >&2
            resolved=$(fetch_addon_name "$id")
            if [ "$resolved" != "$id" ]; then
                echo -e "${GREEN}Name found: $resolved${NC}" >&2
            else
                echo -e "${YELLOW}Could not obtain the name. Using ID as folder name.${NC}" >&2
            fi
        fi
    fi

    echo "$resolved"
}

# Verifies if all dependencies are accessible.
# Returns 1 if any critical dependency is missing.
function check_deps() {
    local status=0

    if ! command -v steamcmd &>/dev/null; then
        echo -e "  ${RED}[MISSING]${NC} steamcmd not found in PATH"
        log_error "Missing dependency: steamcmd"
        status=1
    else
        echo -e "  ${GREEN}[OK]${NC}      steamcmd"
    fi

    if ! command -v 7z &>/dev/null; then
        echo -e "  ${RED}[MISSING]${NC} 7z not found in PATH"
        log_error "Missing dependency: 7z"
        status=1
    else
        echo -e "  ${GREEN}[OK]${NC}      7z"
    fi

    if [ ! -x "$GMAD" ]; then
        echo -e "  ${RED}[MISSING]${NC} gmad not found or lacks execution permission"
        echo -e "            Verified path: $GMAD"
        echo -e "            ${YELLOW}Tip: edit GMOD_BIN in $CONFIG_FILE${NC}"
        log_error "Missing dependency: gmad at $GMAD"
        status=1
    else
        echo -e "  ${GREEN}[OK]${NC}      gmad"
    fi

    if [ ! -x "$GMPUBLISH" ]; then
        echo -e "  ${YELLOW}[WARN]${NC}    gmpublish not found — publishing/updating unavailable"
        echo -e "            Verified path: $GMPUBLISH"
        log_error "Missing dependency: gmpublish at $GMPUBLISH"
        # Non-fatal: the script works without gmpublish for download/extraction/pack
    else
        echo -e "  ${GREEN}[OK]${NC}      gmpublish"
    fi

    return $status
}

# ==========================================
# CORE LOGIC
# ==========================================

function extract_logic() {
    local file="$1"
    local dest="$2"
    local filename
    filename=$(basename "$file")

    mkdir -p "$dest"

    if [[ "$filename" == *.bin ]]; then
        echo -e "${YELLOW}Detected Legacy .bin! Unpacking 7-Zip container... 📦${NC}"

        # PID in the name avoids collision if two instances run together
        local temp_extract="/tmp/gmhelper_bin_$(date +%s)_$$"
        mkdir -p "$temp_extract"

        7z x "$file" -o"$temp_extract" -y > /dev/null 2>&1

        local raw_file
        raw_file=$(find "$temp_extract" -type f | head -n 1)

        if [ -n "$raw_file" ]; then
            local gma_converted="$temp_extract/converted.gma"
            mv "$raw_file" "$gma_converted"

            echo -e "${GREEN}7z success! Sending converted gma to gmad...${NC}"
            "$GMAD" extract -file "$gma_converted" -out "$dest"
            local status=$?

            rm -rf "$temp_extract"
            return $status
        else
            echo -e "${RED}Error: 7z did not extract any file from the .bin container.${NC}"
            log_error "extract_logic: no files extracted from .bin: $file"
            rm -rf "$temp_extract"
            return 1
        fi
    else
        "$GMAD" extract -file "$file" -out "$dest"
        return $?
    fi
}

# ==========================================
# CLEANUP
# ==========================================

function do_clean() {
    echo -e "\n${YELLOW}=== Temporary Files Cleanup ===${NC}"

    # Cleans temporary gmhelper and legacy folders in /tmp
    local tmp_count
    tmp_count=$(find /tmp -maxdepth 1 -type d \( -name "gmhelper_bin_*" -o -name "gmfurry_bin_*" \) 2>/dev/null | wc -l)

    if [ "$tmp_count" -gt 0 ]; then
        echo -e "${CYAN}Found $tmp_count temporary directory(ies) in /tmp. Removing...${NC}"
        find /tmp -maxdepth 1 -type d \( -name "gmhelper_bin_*" -o -name "gmfurry_bin_*" \) \
            -exec rm -rf {} + 2>/dev/null
        echo -e "${GREEN}Temporary files cleaned.${NC}"
        log_action "CLEAN: $tmp_count temporary directory(ies) in /tmp removed"
    else
        echo -e "${GREEN}No temporary directories found in /tmp.${NC}"
    fi

    # Optional cleanup of old builds by age
    if [ -n "$WORK_FOLDER" ] && [ -d "$WORK_FOLDER/builds" ]; then
        echo ""
        read -p "Clean builds older than how many days? (leave empty to skip): " days_old
        if echo "$days_old" | grep -qE '^[0-9]+$'; then
            local old_count
            old_count=$(find "$WORK_FOLDER/builds" -type f -name "*.gma" -mtime "+$days_old" | wc -l)
            if [ "$old_count" -gt 0 ]; then
                echo -e "${YELLOW}Found $old_count .gma file(s) older than $days_old days in builds/.${NC}"
                read -p "Confirm deletion? (y/N): " confirm
                if [[ "$confirm" =~ ^[yYsS]$ ]]; then
                    find "$WORK_FOLDER/builds" -type f -name "*.gma" -mtime "+$days_old" -delete
                    echo -e "${GREEN}Old builds removed.${NC}"
                    log_action "CLEAN: $old_count build(s) older than $days_old days removed from $WORK_FOLDER/builds"
                else
                    echo -e "${CYAN}Operation canceled.${NC}"
                fi
            else
                echo -e "${GREEN}No builds older than $days_old days found.${NC}"
            fi
        fi
    fi
}

# ==========================================
# GENERATE DEFAULT CONFIG (first run)
# ==========================================

function generate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
# ==========================================
# GMHelper CLI - Configuration File
# ==========================================
# Edit the values below to match your system.
# This file is sourced by gmhelper.sh at startup.

# Absolute path to the GarrysMod bin/linux64 directory
# (where gmad and gmpublish are located)
GMOD_BIN="/run/media/nap/5c9fedcc-bafb-4b4d-8f71-77262f56b6e8/SteamLibrary/steamapps/common/GarrysMod/bin/linux64"

# Default Work Folder — leave empty to always ask manually
WORK_FOLDER=""
EOF
        echo -e "${GREEN}Configuration file created: $CONFIG_FILE${NC}"
        echo -e "${YELLOW}Edit it to adjust the paths to your environment before continuing.${NC}"
        echo ""
    fi
}

# ==========================================
# CLI ARGUMENT HANDLER
# ==========================================

function show_help() {
    echo -e "${BOLD}GMHelper CLI — Direct usage via arguments${NC}"
    echo ""
    echo "  ./gmhelper.sh --pack    <addon_folder> [output.gma]"
    echo "  ./gmhelper.sh --publish <gma_file> <icon.jpg>"
    echo "  ./gmhelper.sh --update  <workshop_id> <gma_file>"
    echo "  ./gmhelper.sh --download <workshop_id>"
    echo "  ./gmhelper.sh --rawdl    <workshop_id>"
    echo "  ./gmhelper.sh --extract <gma_file|.bin>"
    echo "  ./gmhelper.sh --clean"
    echo "  ./gmhelper.sh --help"
    echo ""
    echo "  If WORK_FOLDER is defined in config.conf, the output paths"
    echo "  follow the default structure: builds/, downloads/, extracted/."
}

function handle_cli_args() {
    case "$1" in

        --pack)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: --pack <addon_folder> [output.gma]${NC}"; exit 1
            fi
            validate_folder "$2" || exit 1
            if [ -n "$WORK_FOLDER" ]; then
                out_path="$WORK_FOLDER/builds/$(basename "$2").gma"
                mkdir -p "$WORK_FOLDER/builds"
            elif [ -n "$3" ]; then
                out_path="$3"
            else
                echo -e "${RED}Specify the output file or define WORK_FOLDER in config.conf.${NC}"; exit 1
            fi
            backup_if_exists "$out_path"
            "$GMAD" create -folder "$2" -out "$out_path"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Addon packed: $out_path${NC}"
                log_action "PACK: $2 -> $out_path"
            else
                log_error "PACK: failed to pack $2"; exit 1
            fi
            ;;

        --publish)
            if [ -z "$2" ] || [ -z "$3" ]; then
                echo -e "${RED}Usage: --publish <gma_file> <icon.jpg>${NC}"; exit 1
            fi
            validate_file "$2" || exit 1
            validate_file "$3" || exit 1
            "$GMPUBLISH" create -addon "$2" -icon "$3"
            if [ $? -eq 0 ]; then
                log_action "PUBLISH: $2"
            else
                log_error "PUBLISH: failed to publish $2"; exit 1
            fi
            ;;

        --update)
            if [ -z "$2" ] || [ -z "$3" ]; then
                echo -e "${RED}Usage: --update <workshop_id> <gma_file>${NC}"; exit 1
            fi
            validate_workshop_id "$2" || exit 1
            validate_file "$3" || exit 1
            "$GMPUBLISH" update -id "$2" -addon "$3"
            if [ $? -eq 0 ]; then
                log_action "UPDATE: ID=$2 file=$3"
            else
                log_error "UPDATE: failed to update ID=$2"; exit 1
            fi
            ;;

        --download)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: --download <workshop_id>${NC}"; exit 1
            fi
            validate_workshop_id "$2" || exit 1
            if [ -z "$WORK_FOLDER" ]; then
                echo -e "${RED}Define WORK_FOLDER in config.conf to use --download via CLI.${NC}"; exit 1
            fi
            dl_target="$WORK_FOLDER/extracted/$2"
            mkdir -p "$dl_target"
            steamcmd +force_install_dir "$dl_target" +login anonymous \
                +workshop_download_item 4000 "$2" +quit
            dl_file=$(find "$dl_target" -type f \( -name "*.gma" -o -name "*.bin" \) | head -n 1)
            if [ -n "$dl_file" ]; then
                extract_logic "$dl_file" "$dl_target"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Extracted to: $dl_target${NC}"
                    log_action "DOWNLOAD+EXTRACT: ID=$2 -> $dl_target"
                    rm -rf "$dl_target/steamapps" "$dl_target"/*.bin "$dl_target"/*.gma 2>/dev/null
                else
                    log_error "DOWNLOAD+EXTRACT: extraction failed ID=$2"; exit 1
                fi
            else
                echo -e "${RED}No file found after download.${NC}"
                log_error "DOWNLOAD: no file found after download ID=$2"; exit 1
            fi
            ;;

        --rawdl)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: --rawdl <workshop_id>${NC}"; exit 1
            fi
            validate_workshop_id "$2" || exit 1
            if [ -z "$WORK_FOLDER" ]; then
                echo -e "${RED}Define WORK_FOLDER in config.conf to use --rawdl via CLI.${NC}"; exit 1
            fi
            rdl_target="$WORK_FOLDER/downloads"
            rdl_temp="$rdl_target/temp_$2"
            mkdir -p "$rdl_temp"
            steamcmd +force_install_dir "$rdl_temp" +login anonymous \
                +workshop_download_item 4000 "$2" +quit
            rdl_file=$(find "$rdl_temp" -type f \( -name "*.gma" -o -name "*.bin" \) | head -n 1)
            if [ -n "$rdl_file" ]; then
                mv "$rdl_file" "$rdl_target/"
                echo -e "${GREEN}Saved to: $rdl_target/$(basename "$rdl_file")${NC}"
                log_action "RAWDL: ID=$2 -> $rdl_target/$(basename "$rdl_file")"
                rm -rf "$rdl_temp"
            else
                echo -e "${RED}Download failed.${NC}"
                log_error "RAWDL: download failed ID=$2"
                rm -rf "$rdl_temp"; exit 1
            fi
            ;;

        --extract)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: --extract <gma_file|.bin>${NC}"; exit 1
            fi
            validate_file "$2" || exit 1
            if [ -z "$WORK_FOLDER" ]; then
                echo -e "${RED}Define WORK_FOLDER in config.conf to use --extract via CLI.${NC}"; exit 1
            fi
            ex_name=$(basename "$2" | sed 's/\.[^.]*$//')
            ex_target="$WORK_FOLDER/extracted/$ex_name"
            extract_logic "$2" "$ex_target"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Extracted to: $ex_target${NC}"
                log_action "EXTRACT: $2 -> $ex_target"
            else
                log_error "EXTRACT: failed to extract $2"; exit 1
            fi
            ;;

        --clean)
            do_clean
            ;;

        --help|-h)
            show_help
            ;;

        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            show_help
            exit 1
            ;;
    esac
    exit 0
}

# ==========================================
# STARTUP
# ==========================================

generate_config

# Process command line arguments before opening the menu
if [ $# -gt 0 ]; then
    handle_cli_args "$@"
fi

# Dependency verification — pauses only if there are problems
echo -e "${CYAN}Checking dependencies...${NC}"
if ! check_deps; then
    echo -e "\n${YELLOW}One or more dependencies are missing. Some features may not work.${NC}"
    echo -e "${YELLOW}Verify and edit: $CONFIG_FILE${NC}"
    sleep 3
fi
echo ""

# ==========================================
# INTERACTIVE MENU
# ==========================================

while true; do
    clear
    echo -e "${CYAN}============================================${NC}"
    echo -e "${GREEN} GMHelper CLI Manager (Bin/Gma Fix)         ${NC}"
    echo -e "${CYAN}============================================${NC}"
    if [ -n "$WORK_FOLDER" ]; then
        echo -e "${MAGENTA}📁 Work Folder: ${GREEN}$WORK_FOLDER${NC}"
    else
        echo -e "${MAGENTA}📁 Work Folder: ${RED}None (Manual Mode)${NC}"
    fi
    echo -e "${CYAN}============================================${NC}"
    echo " 1) 📦 Pack Addon (.gma)"
    echo " 2) 🚀 Publish NEW Addon to Workshop"
    echo " 3) ♻️  Update Existing Addon"
    echo " 4) 📥 Download & Extract Addon"
    echo " 5) 💾 Download Raw File Only (.gma/.bin)"
    echo " 6) 🔓 Extract Local File Only"
    echo " 7) 🗂️  Set Work Folder for This Session"
    echo " 8) 📋 View Log"
    echo " 9) 🧹 Clean Temporary Files"
    echo "10) ❌ Exit"
    echo -e "${CYAN}============================================${NC}"
    read -p "Choose an option (1-10): " escolha

    case $escolha in

        1)
            echo -e "\n${YELLOW}=== Creating GMA Package ===${NC}"
            read -p "Path to your addon folder: " folder_path
            if ! validate_folder "$folder_path"; then pause; continue; fi
            if [ -n "$WORK_FOLDER" ]; then
                out_path="$WORK_FOLDER/builds/$(basename "$folder_path").gma"
                mkdir -p "$WORK_FOLDER/builds"
            else
                read -p "Where to save the .gma?: " out_path
            fi
            backup_if_exists "$out_path"
            "$GMAD" create -folder "$folder_path" -out "$out_path"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Addon successfully packed: $out_path${NC}"
                log_action "PACK: $folder_path -> $out_path"
            else
                echo -e "${RED}Error packing the addon.${NC}"
                log_error "PACK: failed to pack $folder_path"
            fi
            pause
            ;;

        2)
            echo -e "\n${YELLOW}=== Publishing New Addon ===${NC}"
            read -p "Path to .gma file: " gma_path
            if ! validate_file "$gma_path"; then pause; continue; fi
            read -p "Path to icon (.jpg 512x512): " icon_path
            if ! validate_file "$icon_path"; then pause; continue; fi
            "$GMPUBLISH" create -addon "$gma_path" -icon "$icon_path"
            if [ $? -eq 0 ]; then
                log_action "PUBLISH: $gma_path"
            else
                echo -e "${RED}Error publishing the addon.${NC}"
                log_error "PUBLISH: failed to publish $gma_path"
            fi
            pause
            ;;

        3)
            echo -e "\n${YELLOW}=== Updating Addon ===${NC}"
            read -p "Workshop ID: " workshop_id
            if ! validate_workshop_id "$workshop_id"; then pause; continue; fi
            read -p "Path to updated .gma file: " gma_path
            if ! validate_file "$gma_path"; then pause; continue; fi
            "$GMPUBLISH" update -id "$workshop_id" -addon "$gma_path"
            if [ $? -eq 0 ]; then
                log_action "UPDATE: ID=$workshop_id file=$gma_path"
            else
                echo -e "${RED}Error updating the addon.${NC}"
                log_error "UPDATE: failed to update ID=$workshop_id"
            fi
            pause
            ;;

        4)
            echo -e "\n${YELLOW}=== Downloading & Extracting Addon ===${NC}"
            read -p "What is the Workshop ID? " workshop_id
            if ! validate_workshop_id "$workshop_id"; then pause; continue; fi

            addon_dirname=$(ask_use_addon_name "$workshop_id")

            if [ -n "$WORK_FOLDER" ]; then
                target_dir="$WORK_FOLDER/extracted/$addon_dirname"
            else
                read -p "Target directory: " target_dir
            fi

            mkdir -p "$target_dir"
            echo -e "${GREEN}Downloading from Steam...${NC}"
            steamcmd +force_install_dir "$target_dir" +login anonymous \
                +workshop_download_item 4000 "$workshop_id" +quit

            GMA_FILE=$(find "$target_dir" -type f \( -name "*.gma" -o -name "*.bin" \) | head -n 1)

            if [ -n "$GMA_FILE" ]; then
                extract_logic "$GMA_FILE" "$target_dir"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Success! Everything extracted to: $target_dir${NC}"
                    log_action "DOWNLOAD+EXTRACT: ID=$workshop_id dirname=$addon_dirname -> $target_dir"
                else
                    echo -e "${RED}Critical error! gmad or 7z failed to process the file!${NC}"
                    log_error "DOWNLOAD+EXTRACT: extraction failed ID=$workshop_id"
                fi
                rm -rf "$target_dir/steamapps" "$target_dir"/*.bin "$target_dir"/*.gma 2>/dev/null
            else
                echo -e "${RED}No file found after download!${NC}"
                log_error "DOWNLOAD+EXTRACT: no file found after download ID=$workshop_id"
            fi
            pause
            ;;

        5)
            echo -e "\n${YELLOW}=== Downloading Raw File Only ===${NC}"
            read -p "What is the Workshop ID? " workshop_id
            if ! validate_workshop_id "$workshop_id"; then pause; continue; fi

            addon_dirname=$(ask_use_addon_name "$workshop_id")

            if [ -n "$WORK_FOLDER" ]; then
                target_dir="$WORK_FOLDER/downloads"
            else
                read -p "Target directory: " target_dir
            fi
            mkdir -p "$target_dir"
            TEMP_DL="$target_dir/temp_$workshop_id"
            mkdir -p "$TEMP_DL"
            steamcmd +force_install_dir "$TEMP_DL" +login anonymous \
                +workshop_download_item 4000 "$workshop_id" +quit
            GMA_FILE=$(find "$TEMP_DL" -type f \( -name "*.gma" -o -name "*.bin" \) | head -n 1)
            if [ -n "$GMA_FILE" ]; then
                raw_ext="${GMA_FILE##*.}"
                final_path="$target_dir/${addon_dirname}.${raw_ext}"
                mv "$GMA_FILE" "$final_path"
                echo -e "${GREEN}Successfully saved to: $final_path${NC}"
                log_action "RAWDL: ID=$workshop_id -> $final_path"
                rm -rf "$TEMP_DL"
            else
                echo -e "${RED}Download failed!${NC}"
                log_error "RAWDL: download failed ID=$workshop_id"
                rm -rf "$TEMP_DL"
            fi
            pause
            ;;

        6)
            echo -e "\n${YELLOW}=== Extract Local File Only ===${NC}"
            read -p "Full file path (.gma or .bin): " local_file
            if ! validate_file "$local_file"; then pause; continue; fi
            if [ -n "$WORK_FOLDER" ]; then
                NOME_SEM_EXT=$(basename "$local_file" | sed 's/\.[^.]*$//')
                target_dir="$WORK_FOLDER/extracted/$NOME_SEM_EXT"
            else
                read -p "Directory where you want to extract the files: " target_dir
            fi

            extract_logic "$local_file" "$target_dir"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Success! Everything extracted to: $target_dir${NC}"
                log_action "EXTRACT: $local_file -> $target_dir"
            else
                echo -e "${RED}Error extracting! The file is corrupted or invalid!${NC}"
                log_error "EXTRACT: failed to extract $local_file"
            fi
            pause
            ;;

        7)
            echo -e "\n${YELLOW}=== Set Work Folder ===${NC}"
            read -p "Enter the Work Folder path: " input_wf
            if [ -n "$input_wf" ]; then
                WORK_FOLDER=$(echo "$input_wf" | sed 's/\/\+$//') # Removes trailing slashes!
                mkdir -p "$WORK_FOLDER"
                echo -e "${GREEN}Work Folder set to: $WORK_FOLDER${NC}"
            fi
            pause
            ;;

        8)
            echo -e "\n${YELLOW}=== Action Log (last 50 entries) ===${NC}"
            if [ -f "$LOG_FILE" ]; then
                echo -e "${CYAN}File: $LOG_FILE${NC}"
                echo -e "${CYAN}--------------------------------------------${NC}"
                tail -n 50 "$LOG_FILE"
            else
                echo -e "${YELLOW}No log found yet.${NC}"
            fi
            pause
            ;;

        9)
            do_clean
            pause
            ;;

        10)
            echo -e "\n${GREEN}Exiting. See you later!${NC}"
            exit 0
            ;;

        *)
            echo -e "\n${RED}Invalid option!${NC}"
            sleep 2
            ;;
    esac
done
