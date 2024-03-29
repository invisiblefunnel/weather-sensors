# shellcheck disable=SC2155

set -e

main () {
  # Default to env vars
  local email="${1:-$SENSORPUSH_EMAIL}"
  local password="${2:-$SENSORPUSH_PASSWORD}"
  local channel="${3:-$SLACK_CHANNEL}"

  # Get a temporary api token
  local token=$(refresh_token "$email" "$password")

  # Request data from the sensorpush API
  local sensors=$(fetch_sensors "$token")
  local samples=$(fetch_samples "$token" "$sensors")

  # Format the data into a slack message
  local message=$(format_slack_message "$sensors" "$samples")

  # Post results to slack
  /slack chat send "$message" "$channel"
}

refresh_token () {
  local code=$(authenticate "$1" "$2")
  local token=$(authorize "$code")
  echo "$token"
}

authenticate () {
  curl -X POST "https://api.sensorpush.com/api/v1/oauth/authorize" \
    -fSs -H "Accept: application/json" -H "Content-Type: application/json" \
    -d "{\"email\": \"$1\", \"password\": \"$2\"}" \
  | jq -r .authorization
}

authorize () {
  curl -X POST "https://api.sensorpush.com/api/v1/oauth/accesstoken" \
    -fSs -H "Accept: application/json" -H "Content-Type: application/json" \
    -d "{\"authorization\": \"$1\"}" \
  | jq -r .accesstoken
}

fetch_sensors () {
  curl -X POST "https://api.sensorpush.com/api/v1/devices/sensors" \
    -fSs -H "Accept: application/json" -H "Content-Type: application/json" \
    -H "Authorization: $1" \
    -d '{}'
}

fetch_samples () {
  local sensor_ids=$(echo "$2" | jq -r keys)
  curl -X POST "https://api.sensorpush.com/api/v1/samples" \
    -fSs -H "Accept: application/json" -H "Content-Type: application/json" \
    -H "Authorization: $1" \
    -d "{\"sensors\": $sensor_ids, \"limit\": 1}"
}

format_slack_message () {
  local sensor_ids=$(echo $1 | jq -j '
    to_entries
    | sort_by(.value.name)
    | map(.key)
    | join(" ")
  ')

  for sensor_id in $sensor_ids; do
    local name=$(echo "$1" | jq -r ".[""\"$sensor_id\"""].name")
    local last_observation=$(echo "$2" | jq -r ".sensors[""\"$sensor_id\"""][0]")
    local temperature=$(echo "$last_observation" | jq -r .temperature)
    local humidity=$(echo "$last_observation" | jq -r .humidity)
    local utc_ts=$(timestamp_to_epoch "$(echo "$last_observation" | jq -r .observed)")
    local now=$(date +%s)
    local time_ago=$(time_ago_in_words "$now" "$utc_ts")

    echo -e "*$name*"
    echo -e "\tTemperature: $temperature°F"
    echo -e "\tRelative Humidity: $humidity%"
    echo -e "\t_ $time_ago _"
  done
}

timestamp_to_epoch () {
  local ts=$(echo "$1" | cut -d. -f1)
  local dt=$(echo "$ts" | cut -dT -f1)
  local tm=$(echo "$ts" | cut -dT -f2)
  date -d "$dt $tm" +%s
}

time_ago_in_words () {
  awk -v now="$1" -v then="$2" '
    BEGIN {
       diff = now - then;
       if (diff > (24*60*60)) printf "%.0f days ago", diff/(24*60*60);
       else if (diff > (60*60)) printf "%.0f hours ago", diff/(60*60);
       else if (diff > 60) printf "%.0f minutes ago", diff/60;
       else printf "%s seconds ago", diff;
    }'
}

main "$1" "$2"
