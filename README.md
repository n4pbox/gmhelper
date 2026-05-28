# 🛠️ GMHelper CLI

> Lightweight automation utility for **Garry's Mod** addon developers — a smart wrapper around `gmad` and `gmpublish` for packing, extracting, downloading, and managing Workshop content.

## ⚠️⚠️ THIS SCRIPT WAS **NOT** MADE BY ME BUT BY AI AND IS AN ONGOING EXPERIMENT WHICH I WOULD LIKE TO SHARE. THEREFORE, IT SHALL NOT BE USED RELIABLY. YOU WERE ADVISED ⚠️⚠️

---

## ✨ Features

| Feature | Description |
|---|---|
| 🖥️ **Interactive Menu** | Text interface for quick manual operations |
| ⚡ **Direct CLI Arguments** | Scriptable flags for power users and automated workflows |
| 📦 **Legacy Support** | Auto-detects and decompresses legacy `.bin` containers via 7-Zip before processing |
| 🔍 **Smart Name Resolution** | Fetches and sanitizes real addon titles from Steam Workshop via `curl` |
| 🔒 **Safe Overwrites** | Creates timestamped backups of old `.gma` files before packing new ones |
| 📝 **Persistent Logs** | All tasks, backups, and errors logged to `gmhelper.log` with timestamps |

---

## 📋 Dependencies

| Tool | Required | Purpose |
|---|---|---|
| `steamcmd` | ✅ Required | Downloading Workshop items |
| `7z` | ✅ Required | Extracting legacy `.bin` formats |
| `curl` | ⚪ Optional | Looking up addon names on Steam |

---

## ⚙️ Installation & Setup

### 1. Configure `config.conf`

If `config.conf` does not exist in the script directory, it will be generated automatically on first run. Open it in your preferred text editor and set your paths:

```bash
# Absolute path to the GarrysMod bin/linux64 directory
GMOD_BIN="/path/to/SteamLibrary/steamapps/common/GarrysMod/bin/linux64"

# Default Work Folder (leave empty to always ask manually)
WORK_FOLDER="/path/to/your/workspace"
```

| Variable | Description |
|---|---|
| `GMOD_BIN` | Absolute path to the `bin/linux64` directory where `gmad` and `gmpublish` binaries are stored |
| `WORK_FOLDER` | Workspace root — outputs are sorted into `builds/`, `downloads/`, and `extracted/` subfolders. Leave empty `""` to be prompted on every action |

### 2. Set Permissions

```bash
chmod +x gmhelper.sh
```

---

## 🚀 Usage

GMHelper CLI supports two operational modes.

### Interactive Menu Mode

Run without arguments to open the interactive console manager:

```bash
./gmhelper.sh
```

### Direct CLI Mode

Bypass the menu entirely with dedicated flags:

| Command | Description |
|---|---|
| `./gmhelper.sh --pack <folder> [output.gma]` | Packs an addon folder into a `.gma` file. Uses `WORK_FOLDER/builds/` automatically if no output path is given |
| `./gmhelper.sh --publish <gma> <icon>` | Publishes a new addon to the Steam Workshop using the specified `.gma` and a 512×512 `.jpg` thumbnail |
| `./gmhelper.sh --update <id> <gma>` | Updates an existing Workshop item by its unique ID with a freshly built `.gma` |
| `./gmhelper.sh --download <id>` | Downloads a Workshop item anonymously via SteamCMD and extracts its source files immediately |
| `./gmhelper.sh --rawdl <id>` | Downloads a Workshop item and saves the raw `.gma` or legacy `.bin` without automatic extraction |
| `./gmhelper.sh --extract <file>` | Extracts a local `.gma` or legacy `.bin` file into a source folder |
| `./gmhelper.sh --clean` | Sweeps temporary extraction folders and offers to purge old builds by age |
| `./gmhelper.sh --help` / `-h` | Prints the help manual with all valid flags |

---

## 🧹 Maintenance & Logs

| Feature | Details |
|---|---|
| 📄 **Log File** | `gmhelper.log` — every task, backup, and critical error is logged with a timestamp |
| 🗑️ **Temp Cleanup** | `--clean` safely wipes `/tmp` cache folders generated during extractions, keeping your system clutter-free |
