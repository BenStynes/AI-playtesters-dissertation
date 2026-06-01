#!/bin/sh
printf '\033c\033]0;%s\a' Dungeon Delve
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Dungeon Delve.x86_64" "$@"
