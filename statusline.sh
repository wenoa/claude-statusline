#!/bin/bash

# Read JSON input from stdin (Claude Code passes context info)
STDIN_INPUT=$(cat)

FIVE_HOUR_WINDOW_SECONDS=18000
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TIME_TO_LIVE_SECONDS=60

# Usage and pace thresholds (percentages)
LOW_USAGE_THRESHOLD=20
RELAXED_PACE_THRESHOLD=-20
GOOD_PACE_THRESHOLD=0
FAST_PACE_THRESHOLD=30
CRITICAL_PACE_THRESHOLD=60
GREEN_ZONE_TIME_PERCENTAGE=7
MIN_TIME_PERCENTAGE=1

COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_ORANGE='\033[38;5;208m'
COLOR_RED='\033[31m'
COLOR_GRAY='\033[90m'
COLOR_RESET='\033[0m'

get_token() {
  security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | \
    jq -r '.claudeAiOauth.accessToken // empty'
}

fetch_usage() {
  curl -s "https://api.anthropic.com/api/oauth/usage" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $1" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.0.31"
}

# Strips fractional seconds, timezone offset and Z suffix from ISO 8601 timestamp
normalize_iso_timestamp() {
  local timestamp="$1"
  timestamp="${timestamp%%.*}"   # Strip .123456
  timestamp="${timestamp%%+*}"   # Strip +00:00
  echo "${timestamp%Z}"          # Strip Z
}

convert_to_timestamp() {
  date -u -j -f "%Y-%m-%dT%H:%M:%S" "$1" "+%s" 2>/dev/null
}

# Rounds to nearest minute (up if seconds >= 30)
round_to_nearest_minute() {
  local timestamp=$1
  local seconds_in_minute=$2
  if (( seconds_in_minute >= 30 )); then
    echo $((timestamp + 60 - seconds_in_minute))
  else
    echo "$timestamp"
  fi
}

parse_reset_timestamp() {
  local clean_timestamp=$(normalize_iso_timestamp "$1")
  local timestamp=$(convert_to_timestamp "$clean_timestamp")
  local seconds_in_minute="${clean_timestamp##*:}"
  round_to_nearest_minute "$timestamp" "$seconds_in_minute"
}

calculate_remaining_seconds() {
  local reset_timestamp="$1"
  local current_timestamp="$2"
  local remaining=$((reset_timestamp - current_timestamp))
  (( remaining < 0 )) && remaining=0
  echo "$remaining"
}

format_seconds_as_duration() {
  local seconds=$1
  if (( seconds <= 0 )); then echo "0m"
  elif (( seconds < 3600 )); then echo "$((seconds / 60))m"
  else echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
  fi
}

format_seconds_as_days_hours() {
  local seconds=$1
  if (( seconds <= 0 )); then echo "0h"
  elif (( seconds < 86400 )); then echo "$((seconds / 3600))h"
  else echo "$((seconds / 86400))d $((seconds % 86400 / 3600))h"
  fi
}

round_to_integer() {
  printf "%.0f" "$1"
}

calculate_pace_deviation_percentage() {
  local time_percentage=$1
  local usage_percentage=$2
  (( time_percentage <= 0 )) && time_percentage=$MIN_TIME_PERCENTAGE
  echo $(( (usage_percentage - time_percentage) * 100 / time_percentage ))
}

is_in_green_zone_by_remaining_time() {
  local remaining_seconds=$1
  (( remaining_seconds <= 0 )) && return 1
  local green_threshold_seconds=$((FIVE_HOUR_WINDOW_SECONDS * GREEN_ZONE_TIME_PERCENTAGE / 100))
  (( remaining_seconds < green_threshold_seconds ))
}

get_pace_emoji() {
  local pace_deviation=$1
  local usage_percentage=$2

  (( usage_percentage == 0 )) && { echo "🧊"; return; }

  if (( pace_deviation < RELAXED_PACE_THRESHOLD )); then echo "🧊"
  elif (( pace_deviation <= GOOD_PACE_THRESHOLD )); then echo "🌿"
  elif (( pace_deviation <= FAST_PACE_THRESHOLD )); then echo "🔥"
  else echo "💀"
  fi
}

get_color_code() {
  local pace_deviation=$1
  local usage_percentage=$2
  local remaining_seconds=$3

  (( usage_percentage < LOW_USAGE_THRESHOLD )) && { echo "$COLOR_GREEN"; return; }
  is_in_green_zone_by_remaining_time "$remaining_seconds" && { echo "$COLOR_GREEN"; return; }

  if (( pace_deviation <= GOOD_PACE_THRESHOLD )); then echo "$COLOR_GREEN"
  elif (( pace_deviation <= FAST_PACE_THRESHOLD )); then echo "$COLOR_YELLOW"
  elif (( pace_deviation <= CRITICAL_PACE_THRESHOLD )); then echo "$COLOR_ORANGE"
  else echo "$COLOR_RED"
  fi
}

is_cache_valid() {
  local current_timestamp=$1
  [[ ! -f "$CACHE_FILE" ]] && return 1
  local cache_timestamp=$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null)
  (( current_timestamp - cache_timestamp < CACHE_TIME_TO_LIVE_SECONDS ))
}

save_to_cache() {
  local response=$1
  local timestamp=$2
  echo "$response" | jq --arg ts "$timestamp" '. + {cached_at: ($ts | tonumber)}' > "$CACHE_FILE"
}

get_cached_or_fetch() {
  local current_timestamp=$1

  if is_cache_valid "$current_timestamp"; then
    cat "$CACHE_FILE"
    return
  fi

  local access_token=$(get_token)
  if [[ -z "$access_token" ]]; then
    echo '{"error": "no_token"}'
    return
  fi

  local response=$(fetch_usage "$access_token")

  if [[ -z "$response" ]] || has_error_in_response "$response"; then
    if [[ -f "$CACHE_FILE" ]]; then
      cat "$CACHE_FILE"
    else
      echo '{"error": "api_error"}'
    fi
    return
  fi

  save_to_cache "$response" "$current_timestamp"
  cat "$CACHE_FILE"
}

extract_usage_data() {
  local usage_json="$1"
  jq -r '[
    .five_hour.utilization // 0,
    .five_hour.resets_at // "",
    .seven_day.utilization // 0,
    .seven_day.resets_at // ""
  ] | @tsv' <<< "$usage_json"
}

has_error_in_response() {
  echo "$1" | jq -e '.error' >/dev/null 2>&1
}

render_error() {
  local error_type="$1"
  if [[ "$error_type" == "no_token" ]]; then
    echo -e "${COLOR_GRAY}⚠️ No session${COLOR_RESET}"
  else
    echo -e "${COLOR_GRAY}⚠️ Error API${COLOR_RESET}"
  fi
}

extract_context_data() {
  local input="$1"
  [[ -z "$input" ]] && return 1

  jq -r '
    if .context_window.current_usage != null and .context_window.context_window_size != null then
      [
        (.context_window.current_usage.input_tokens +
         .context_window.current_usage.cache_creation_input_tokens +
         .context_window.current_usage.cache_read_input_tokens),
        .context_window.context_window_size
      ] | @tsv
    else
      empty
    end
  ' <<< "$input"
}

format_tokens_as_thousands() {
  local tokens=$1
  echo "$(( (tokens + 500) / 1000 ))k"
}

calculate_percentage() {
  local current=$1
  local total=$2
  (( total <= 0 )) && { echo 0; return; }
  echo $((current * 100 / total))
}

render_status_line() {
  local usage_json="$1"
  local current_timestamp="$2"
  local stdin_input="$3"

  IFS=$'\t' read -r five_hour_utilization five_hour_reset_timestamp seven_day_utilization seven_day_reset_timestamp < <(extract_usage_data "$usage_json")

  local reset_at=$(parse_reset_timestamp "$five_hour_reset_timestamp")
  local remaining_seconds=$(calculate_remaining_seconds "$reset_at" "$current_timestamp")

  local elapsed_seconds=$((FIVE_HOUR_WINDOW_SECONDS - remaining_seconds))
  (( elapsed_seconds < 0 )) && elapsed_seconds=0
  local time_percentage=$((elapsed_seconds * 100 / FIVE_HOUR_WINDOW_SECONDS))

  local five_hour_usage=$(round_to_integer "$five_hour_utilization")
  local seven_day_usage=$(round_to_integer "$seven_day_utilization")
  local pace_deviation=$(calculate_pace_deviation_percentage "$time_percentage" "$five_hour_usage")

  local color=$(get_color_code "$pace_deviation" "$five_hour_usage" "$remaining_seconds")
  local emoji=$(get_pace_emoji "$pace_deviation" "$five_hour_usage")
  local time_remaining=$(format_seconds_as_duration "$remaining_seconds")

  local seven_day_remaining=""
  if [[ -n "$seven_day_reset_timestamp" ]]; then
    local seven_day_reset_at=$(parse_reset_timestamp "$seven_day_reset_timestamp")
    local seven_day_remaining_seconds=$(calculate_remaining_seconds "$seven_day_reset_at" "$current_timestamp")
    seven_day_remaining=" $(format_seconds_as_days_hours "$seven_day_remaining_seconds")"
  fi

  local context_display=""
  local context_data=$(extract_context_data "$stdin_input")
  if [[ -n "$context_data" ]]; then
    IFS=$'\t' read -r current_tokens context_size <<< "$context_data"
    local current_k=$(format_tokens_as_thousands "$current_tokens")
    local max_k=$(format_tokens_as_thousands "$context_size")
    local context_percent=$(calculate_percentage "$current_tokens" "$context_size")
    context_display=" · 🧠 ${current_k}/${max_k} (${context_percent}%)"
  fi

  echo -e "${emoji} · ${color}${five_hour_usage}%${COLOR_RESET} (${time_remaining}) / ${seven_day_usage}% (${seven_day_remaining## })${context_display}"
}

# --- Main ---
current_timestamp=$(date "+%s")
usage_json=$(get_cached_or_fetch "$current_timestamp")

if has_error_in_response "$usage_json"; then
  render_error "$(echo "$usage_json" | jq -r '.error')"
  exit 0
fi

render_status_line "$usage_json" "$current_timestamp" "$STDIN_INPUT"
