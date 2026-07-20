#!/usr/bin/env bash
# Lance/relance Polybar (appelé par i3 via exec_always)
killall -q polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done

if command -v xrandr &>/dev/null; then
  for m in $(xrandr --query | awk '/ connected/ {print $1}'); do
    MONITOR="$m" polybar --reload main &
  done
else
  polybar --reload main &
fi
