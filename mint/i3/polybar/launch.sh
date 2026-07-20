#!/usr/bin/env bash
# Lance/relance Polybar (appelé par i3 via exec_always)
killall -q polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done

if command -v xrandr &>/dev/null; then
  # primaire d'abord : une seule instance du tray possible (polybar 3.7),
  # il s'attache à la première barre lancée
  primary="$(xrandr --query | awk '/ connected primary/ {print $1}')"
  others="$(xrandr --query | awk '/ connected/ {print $1}' | grep -vx "${primary:-__none__}")"
  for m in ${primary} ${others}; do
    MONITOR="$m" polybar --reload main &
  done
else
  polybar --reload main &
fi
