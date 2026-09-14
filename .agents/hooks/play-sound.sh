#!/usr/bin/env bash
# Play a short notification sound for a given event, best-effort and cross-platform.
# Usage: play-sound.sh [notify|stop]   (notify = a permission prompt is waiting; stop = Claude finished)
# Silent no-op if no audio player is available. This is the ONE place to edit sounds / OS support.
set -u

kind="${1:-stop}"

case "$(uname -s)" in
  Darwin)
    case "$kind" in
      notify) sound=/System/Library/Sounds/Submarine.aiff ;;
      *)      sound=/System/Library/Sounds/Purr.aiff ;;
    esac
    command -v afplay >/dev/null 2>&1 && exec afplay "$sound"
    ;;
  Linux)
    case "$kind" in
      notify) event=message ;;
      *)      event=complete ;;
    esac
    command -v canberra-gtk-play >/dev/null 2>&1 && exec canberra-gtk-play -i "$event"
    if command -v paplay >/dev/null 2>&1 && [ -f "/usr/share/sounds/freedesktop/stereo/${event}.oga" ]; then
      exec paplay "/usr/share/sounds/freedesktop/stereo/${event}.oga"
    fi
    ;;
esac

exit 0
