# GMHelper CLI

A simple Bash CLI tool to manage Garry's Mod addons from the terminal. It wraps `gmad` and `gmpublish` into an interactive menu so you don't have to remember every flag and path while working with Workshop addons — downloading, extracting, packing, publishing, and updating, all in one place.

---

## Requirements

Before running the script, make sure the following tools are available in your system PATH:

- **[SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD)** — used to download Workshop addons anonymously
- **[7-Zip](https://www.7-zip.org/)** (`7z` command) — required to handle legacy `.bin` addon containers

You also need a working installation of **Garry's Mod** on your machine, since the script relies on two binaries that ship with it: `gmad` and `gmpublish`.

---

## Configuration

Open `gmhelper.sh` and update the path at the top of the file to point to your own Garry's Mod `bin/linux64` folder:

```bash
GMOD_BIN="/run/media/nap/5c9fedcc-bafb-4b4d-8f71-77262f56b6e8/SteamLibrary/steamapps/common/GarrysMod/bin/linux64"
```

The two variables derived from it are:

```bash
GMAD="$GMOD_BIN/gmad"
GMPUBLISH="$GMOD_BIN/gmpublish"
```

You don't need to touch anything else — just get that base path right and the rest follows.

---

## Usage

```bash
chmod +x gmhelper.sh
./gmhelper.sh
```

The script opens an interactive menu. Here's what each option does:

### 1. Pack Addon (.gma)
Takes a folder containing your addon files and packs it into a `.gma` file using `gmad create`. If a Work Folder is set, the output goes automatically into its `/builds` subdirectory.

### 2. Publish New Addon to the Workshop
Calls `gmpublish create` to upload a brand new addon to the Steam Workshop. You'll be asked for the path to your `.gma` file and a `.jpg` icon (512x512).

### 3. Update Existing Addon
Calls `gmpublish update` with a Workshop item ID and an updated `.gma` file. Use this when you've made changes to an already published addon.

### 4. Download & Extract Addon
Downloads a Workshop addon by ID using SteamCMD and immediately extracts its contents. The script handles both modern `.gma` files and legacy `.bin` containers automatically (see the note below). Extracted files end up in the `/extracted` subdirectory if a Work Folder is active.

### 5. Download Raw File Only
Downloads a Workshop addon by ID and saves the raw `.gma` or `.bin` file without extracting it. Useful when you just want to grab the file and deal with it later. Saved to `/downloads` when using a Work Folder.

### 6. Extract Local File
Extracts a `.gma` or `.bin` file you already have on disk. Drop the path in and the script figures out which method to use.

### 7. Set Work Folder
Defines a working directory for the current session. Once set, all operations will automatically organize their output into subdirectories:

```
your-work-folder/
├── builds/      ← packed .gma files
├── downloads/   ← raw downloaded files
└── extracted/   ← extracted addon contents
```

This is optional — without it, the script will ask you for a path on each operation.

---

## A Note on Legacy `.bin` Files

Older Workshop addons downloaded via SteamCMD sometimes come as `.bin` files instead of `.gma`. These are **not** native GMA files — they're 7-Zip archives containing the actual GMA inside. Feeding them directly to `gmad` will fail.

GMHelper handles this automatically: when it detects a `.bin` file, it extracts the archive with `7z`, renames the raw file inside to `.gma`, and then passes it to `gmad` for proper extraction. You don't need to do anything differently — just point the script at the file and it takes care of the rest.

---

## Notes

- This script is Linux-only and was written for **openSUSE Tumbleweed**, but should work on any modern Linux distribution.
- SteamCMD downloads addons under app ID `4000` (Garry's Mod). This is hardcoded and correct for GMod Workshop items.
- The script uses anonymous Steam login for downloads, so no Steam account is required for that part.
- Publishing and updating addons does require being logged into Steam through `gmpublish`, which uses your local Steam session.
