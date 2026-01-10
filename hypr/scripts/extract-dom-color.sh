#!/bin/bash
WALLPAPER=$(cat ~/.config/hypr/.current_wall)
DOMINANT=$(wallust run "$WALLPAPER" --backend kmeans --of hex | head -n1) # Grabs first (dominant) hex color
sed -i "s/col=[^ ]*/col=$DOMINANT/" ~/.config/hypr/hyprlauncher.conf      # Assumes your config uses 'col=hex' for text/background
