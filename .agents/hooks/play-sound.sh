#!/usr/bin/env bash
# Notification + Stop hook: play a short sound, best-effort and cross-platform. The event comes
# from stdin (hook_event_name): Notification, and PermissionRequest (Codex's name for it), play
# the "notify" sound; Stop plays the "stop" sound; anything else is silent. Silent no-op when no
# audio player is available. This is the ONE place to edit sounds / OS support.
# Wired from .agents/hooks/notification.json; PLAY_SOUND_DRY_RUN=1 prints the sound kind instead
# of playing it, which is what the fixture asserts on.
# codex: yes
set -u

input=$(cat 2>/dev/null) || exit 0
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$event" in
  Notification|PermissionRequest) kind=notify ;;
  Stop) kind=stop ;;
  *) exit 0 ;;
esac
if [ -n "${PLAY_SOUND_DRY_RUN:-}" ]; then printf '%s\n' "$kind"; exit 0; fi

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
