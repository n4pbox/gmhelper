#!/bin/bash
# ==========================================
# GMHelper CLI - Old & Modern Version!
# ==========================================

GMOD_BIN="/your/path/here"
GMAD="$GMOD_BIN/gmad"
GMPUBLISH="$GMOD_BIN/gmpublish"

WORK_FOLDER=""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

function pause() {
    echo -e "\n${CYAN}Press [ENTER] to return to the menu...${NC}"
    read -r
}

# Internal function to extract files handling gma and bin!
function extract_logic() {
    local file="$1"
    local dest="$2"
    local filename=$(basename "$file")

    mkdir -p "$dest"

    # If it's a .bin file (Steam Legacy)
    if [[ "$filename" == *.bin ]]; then
        echo -e "${YELLOW}Legacy .bin detected! Unpacking 7-Zip container... 📦${NC}"

        # Creates a temp folder for 7z decompression
        local temp_extract="/tmp/gmfurry_bin_$(date +%s)"
        mkdir -p "$temp_extract"

        # Extracts hidden binary using 7z (redirects payload errors to the void)
        7z x "$file" -o"$temp_extract" -y > /dev/null 2>&1

        # Finds the extensionless file that 7z spit out inside
        local raw_file=$(find "$temp_extract" -type f | head -n 1)

        if [ -n "$raw_file" ]; then
            local gma_converted="$temp_extract/converted.gma"
            mv "$raw_file" "$gma_converted"

            echo -e "${GREEN}7z success! Sending converted gma to gmad...${NC}"
            "$GMAD" extract -file "$gma_converted" -out "$dest"
            local status=$?

            rm -rf "$temp_extract"
            return $status
        else
            rm -rf "$temp_extract"
            return 1
        fi
    else
        # If it's a regular .gma, goes straight to gmad!
        "$GMAD" extract -file "$file" -out "$dest"
        return $?
    fi
}

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
    echo "1) 📦 Pack Addon (.gma)"
    echo "2) 🚀 Publish NEW Addon to Workshop"
    echo "3) ♻️ Update existing Addon"
    echo "4) 📥 Download & Extract Addon"
    echo "5) 💾 Only Download Raw File (.gma/.bin)"
    echo "6) 🔓 Only Extract a Local File"
    echo "7) 🗂️ Set Work Folder for this session"
    echo "8) ❌ Exit"
    echo -e "${CYAN}============================================${NC}"
    read -p "Choose an option (1-8): " escolha

    case $escolha in
        1)
            echo -e "\n${YELLOW}=== Creating GMA package ===${NC}"
            read -p "Path to your addon folder: " folder_path
            if [ -n "$WORK_FOLDER" ]; then
                out_path="$WORK_FOLDER/builds/$(basename "$folder_path").gma"
                mkdir -p "$WORK_FOLDER/builds"
            else
                read -p "Where to save the .gma?: " out_path
            fi
            "$GMAD" create -folder "$folder_path" -out "$out_path"
            pause
            ;;
        2)
            echo -e "\n${YELLOW}=== Publishing New Addon ===${NC}"
            read -p "Path to .gma file: " gma_path
            read -p "Path to icon (.jpg 512x512): " icon_path
            "$GMPUBLISH" create -addon "$gma_path" -icon "$icon_path"
            pause
            ;;
        3)
            echo -e "\n${YELLOW}=== Updating Addon ===${NC}"
            read -p "Workshop ID: " workshop_id
            read -p "Path to updated .gma file: " gma_path
            "$GMPUBLISH" update -id "$workshop_id" -addon "$gma_path"
            pause
            ;;
        4)
            echo -e "\n${YELLOW}=== Downloading & Extracting Addon ===${NC}"
            read -p "What is the Workshop ID? " workshop_id
            if [ -n "$WORK_FOLDER" ]; then
                target_dir="$WORK_FOLDER/extracted/$workshop_id"
            else
                read -p "Target directory: " target_dir
            fi

            mkdir -p "$target_dir"
            echo -e "${GREEN}Downloading everything from Steam...${NC}"
            steamcmd +force_install_dir "$target_dir" +login anonymous +workshop_download_item 4000 "$workshop_id" +quit

            GMA_FILE=$(find "$target_dir" -type f \( -name "*.gma" -o -name "*.bin" \) | head -n 1)

            if [ -n "$GMA_FILE" ]; then
                extract_logic "$GMA_FILE" "$target_dir"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Success! Everything extracted to: $target_dir${NC}"
                else
                    echo -e "${RED}Critical error! gmad or 7z failed to process the file!${NC}"
                fi
                rm -rf "$target_dir/steamapps" "$target_dir"/*.bin "$target_dir"/*.gma 2>/dev/null
            else
                echo -e "${RED}No files found after download!${NC}"
            fi
            pause
            ;;
        5)
            echo -e "\n${YELLOW}=== Only Downloading Raw File ===${NC}"
            read -p "What is the Workshop ID? " workshop_id
            if [ -n "$WORK_FOLDER" ]; then
                target_dir="$WORK_FOLDER/downloads"
            else
                read -p "Target directory: " target_dir
            fi
            mkdir -p "$target_dir"
            TEMP_DL="$target_dir/temp_$workshop_id"
            mkdir -p "$TEMP_DL"
            steamcmd +force_install_dir "$TEMP_DL" +login anonymous +workshop_download_item 4000 "$workshop_id" +quit
            GMA_FILE=$(find "$TEMP_DL" -type f \( -name "*.gma" -o -name "*.bin" \) | head -n 1)
            if [ -n "$GMA_FILE" ]; then
                mv "$GMA_FILE" "$target_dir/"
                echo -e "${GREEN}Successfully saved to: $target_dir/$(basename "$GMA_FILE")${NC}"
                rm -rf "$TEMP_DL"
            else
                echo -e "${RED}Download failed!${NC}"
                rm -rf "$TEMP_DL"
            fi
            pause
            ;;
        6)
            echo -e "\n${YELLOW}=== Only Extract a Local File ===${NC}"
            read -p "Full path to the file (.gma or .bin): " local_file
            if [ -f "$local_file" ]; then
                if [ -n "$WORK_FOLDER" ]; then
                    NOME_SEM_EXT=$(basename "$local_file" | sed 's/\.[^.]*$//')
                    target_dir="$WORK_FOLDER/extracted/$NOME_SEM_EXT"
                else
                    read -p "Directory where you want to extract the files: " target_dir
                fi

                extract_logic "$local_file" "$target_dir"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Success! Everything extracted to: $target_dir${NC}"
                else
                    echo -e "${RED}Error extracting! The file is corrupted or invalid!${NC}"
                fi
            else
                echo -e "${RED}File not found!${NC}"
            fi
            pause
            ;;
        7)
            echo -e "\n${YELLOW}=== Set Work Folder ===${NC}"
            read -p "Enter the Work Folder path: " input_wf
            if [ -n "$input_wf" ]; then
                WORK_FOLDER=$(echo "$input_wf" | sed 's/\/\+$//') # Removes double slashes at the end!
                mkdir -p "$WORK_FOLDER"
                echo -e "${GREEN}Work Folder set: $WORK_FOLDER${NC}"
            fi
            pause
            ;;
        8)
            echo -e "\n${GREEN}Closing. See ya!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option!${NC}"
            sleep 2
            ;;
    esac
done
