#!/usr/bin/env bash
# Wallpaper selector for hyprpaper (2025 version)
# Features: rofi with thumbnails, random, video→image preview, SDDM sync, startup config update

# ── Config ───────────────────────────────────────────────────────────────────
terminal=kitty
wallDIR="$HOME/Pictures/wallpaper"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
iDIR="$HOME/.config/swaync/images"

# Cache directories for previews
CACHE_GIF="$HOME/.cache/gif_preview"
CACHE_VIDEO="$HOME/.cache/video_preview"
mkdir -p "$CACHE_GIF" "$CACHE_VIDEO"

# Rofi theme
rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi" # adjust if you use a different one

# ── Dependencies check ───────────────────────────────────────────────────────
for cmd in hyprctl rofi jq bc magick ffmpeg; do
  command -v "$cmd" >/dev/null || {
    notify-send "Missing $cmd" "Install it first"
    exit 1
  }
done

# ── Monitor info (for nice icon size in rofi) ───────────────────────────────
focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
[[ -z "$focused_monitor" ]] && {
  notify-send "Error" "No focused monitor detected"
  exit 1
}

scale=$(hyprctl monitors -j | jq -r --arg m "$focused_monitor" '.[] | select(.name==$m) | .scale')
height=$(hyprctl monitors -j | jq -r --arg m "$focused_monitor" '.[] | select(.name==$m) | .height')
icon_size=$(echo "scale=0; ($height * 3) / ($scale * 150)" | bc)
icon_size=${icon_size%.*}
[[ $icon_size -lt 15 ]] && icon_size=20
[[ $icon_size -gt 30 ]] && icon_size=25
rofi_override="element-icon{size:${icon_size}.0000%;}"

# ── Kill & restart hyprpaper cleanly ───────────────────────────────────────
restart_hyprpaper() {
  pkill hyprpaper
  hyprpaper &>/dev/null 2>&1 &
  # Small delay so it’s ready for preload commands
  sleep 0.3
}

# ── Apply wallpaper with hyprpaper (auto to all monitors) ───────────────────
apply_wallpaper() {
  local path="$1"
  restart_hyprpaper

  # Preload + apply to ALL monitors (the empty field = magic)
  hyprctl hyprpaper preload "$path"
  hyprctl hyprpaper wallpaper ",$path,cover" # cover | contain | stretch | tile

  # Optional: save current wallpaper so scripts can read it later (for theming)
  realpath "$path" >"$HOME/.cache/current_wallpaper"

  notify-send -i "$path" "Wallpaper changed" "$(basename "$path")"
}

# ── Optional: Set as SDDM background (Sequoia theme) ───────────────────────
set_sddm() {
  local wp="$1"
  local theme_dir="/usr/share/sddm/themes/sequoia_2"
  [[ ! -d "$theme_dir" ]] && return

  if yad --question --title="SDDM Background" --text="Set this wallpaper as SDDM login background?" \
    --button="Yes:0" --button="No:1" --timeout=8; then
    $terminal -e bash -c "sudo cp '$wp' '$theme_dir/backgrounds/default' && echo 'SDDM background updated' || echo 'Failed'"
  fi
}

# ── Update startup config so the same wallpaper loads on login ─────────────
update_startup_config() {
  local path="$1"
  local conf="$HOME/.config/hypr/UserConfigs/Startup_Apps.conf" # change if yours is elsewhere

  # Convert /home/user → $HOME for portability
  local portable_path="${path/#$HOME/\$HOME}"

  # Simple approach: just write the path to a variable many dotfiles already read
  grep -q "current_wallpaper=" "$conf" 2>/dev/null &&
    sed -i "s|current_wallpaper=.*|current_wallpaper=$portable_path|" "$conf" ||
    echo "current_wallpaper=$portable_path" >>"$conf"
}

# ── Build rofi menu with thumbnails ───────────────────────────────────────
menu() {
  # Random entry
  printf ". random\x00icon\x1f$wallDIR/$(ls "$wallDIR" | shuf -n1)\n"

  while IFS= read -r -d '' file; do
    name=$(basename "$file")
    preview=""

    if [[ "$file" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
      cache="$CACHE_VIDEO/${name}.jpg"
      [[ ! -f "$cache" ]] && ffmpeg -y -i "$file" -vf thumbnail -frames:v 1 "$cache" >/dev/null 2>&1
      preview="$cache"
      printf "%s\x00icon\x1f%s\n" "$name" "$preview"
    elif [[ "$file" =~ \.gif$ ]]; then
      cache="$CACHE_GIF/${name}.png"
      [[ ! -f "$cache" ]] && magick "$file[0]" -resize 512x512 "$cache" >/dev/null 2>&1
      preview="$cache"
      printf "%s\x00icon\x1f%s\n" "$name" "$preview"
    else
      printf "%s\x00icon\x1f%s\n" "${name%.*}" "$file"
    fi
  done < <(find -L "$wallDIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) -print0 | sort -z)
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
  choice=$(menu | rofi -dmenu -i -config "$rofi_theme" -theme-str "$rofi_override" -p "Wallpaper")

  [[ -z "$choice" ]] && exit 0

  if [[ "$choice" == ". random" ]]; then
    selected=$(find -L "$wallDIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | shuf -n1)
  else
    # Find the actual file (handles different extensions)
    selected=$(find -L "$wallDIR" -iname "*${choice##*/}*" -print -quit)
  fi

  [[ -z "$selected" || ! -f "$selected" ]] && {
    notify-send "Error" "Wallpaper not found"
    exit 1
  }

  # Apply
  apply_wallpaper "$selected"

  # Optional goodies
  update_startup_config "$selected"
  [[ "$selected" =~ \.(jpg|jpeg|png|webp)$ ]] && set_sddm "$selected" # only static images for SDDM
}

# Kill any stray rofi first
pkill rofi 2>/dev/null

main
