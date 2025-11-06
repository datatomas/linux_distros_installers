#!/usr/bin/env bash
# CSV hardware temperature logger (single file, live console, device column)

interval="${1:-5}"
LOG_DIR="${LOG_DIR:-/home/ares/Documents/pcstats}"
mkdir -p "$LOG_DIR"

# --- Ask user for base filename (no per-run timestamp) ---
read -rp "Base CSV filename (no extension): " BASE
BASE="${BASE:-temps}"
BASE_CLEAN="$(printf '%s' "$BASE" | tr ' ' '_' | tr -cd '[:alnum:]_.-')"
case "$BASE_CLEAN" in
  *.csv) OUTFILE="$LOG_DIR/$BASE_CLEAN" ;;
  *)     OUTFILE="$LOG_DIR/${BASE_CLEAN}.csv" ;;
esac

# --- Discover devices once (stable columns for this run) ---
GPUS=()
if command -v nvidia-smi >/dev/null 2>&1; then
  while read -r idx; do
    idx="$(printf '%s' "$idx" | tr -d ' ')"
    [ -n "$idx" ] && GPUS+=("$idx")
  done < <(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null)
fi

SATAS=()
for d in /dev/sd?; do
  [ -e "$d" ] || continue
  SATAS+=("$(basename "$d")")
done

NVMES_RAW=()
for n in /dev/nvme*n1; do
  [ -e "$n" ] || continue
  ctrl="${n%n1}"
  NVMES_RAW+=("$(basename "$ctrl")")
done
declare -A _seen_nv
NVMES=()
for v in "${NVMES_RAW[@]}"; do
  [[ ${_seen_nv[$v]} ]] || { NVMES+=("$v"); _seen_nv[$v]=1; }
done
unset _seen_nv NVMES_RAW

# --- Build a "device" string: GPU model(s) + CPU model ---
GPU_NAME_STR="none"
if command -v nvidia-smi >/dev/null 2>&1; then
  mapfile -t _GPU_NAMES < <(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)
  if ((${#_GPU_NAMES[@]})); then
    GPU_NAME_STR=""
    for i in "${!_GPU_NAMES[@]}"; do
      name="${_GPU_NAMES[$i]}"
      name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
      GPU_NAME_STR+="GPU${i}: ${name}; "
    done
    GPU_NAME_STR="${GPU_NAME_STR%; }"
  fi
fi

CPU_NAME="$(lscpu 2>/dev/null | awk -F: '/Model name|Model Name/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"
[ -z "$CPU_NAME" ] && CPU_NAME="$(awk -F: '/model name/ {sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
[ -z "$CPU_NAME" ] && CPU_NAME="unknown"

DEVICE_STR="GPU: ${GPU_NAME_STR} | CPU: ${CPU_NAME}"

# --- Header (only if file is new/empty) ---
if [ ! -s "$OUTFILE" ]; then
  {
    printf "timestamp"
    for g in "${GPUS[@]}";  do printf ",GPU%s" "$g"; done
    printf ",CPU"
    for s in "${SATAS[@]}"; do printf ",%s" "$s"; done
    for n in "${NVMES[@]}"; do printf ",%s" "$n"; done
    printf ",device\n"
  } > "$OUTFILE"
fi

echo "Logging to: $OUTFILE"
echo "Interval: ${interval}s. Press Ctrl+C to stop."
echo "Device column: ${DEVICE_STR}"
trap 'echo; echo "Saved to: '"$OUTFILE"'"; exit 0' INT TERM

# --- Main loop ---
while true; do
  ts="$(date '+%F %T')"

  declare -A V

  # GPUs (numeric °C)
  if command -v nvidia-smi >/dev/null 2>&1; then
    while IFS=, read -r idx temp; do
      idx="$(printf '%s' "$idx" | tr -d ' ')"
      temp="$(printf '%s' "$temp" | tr -d ' ')"
      [[ -n "$idx" && -n "$temp" ]] && V["GPU$idx"]="$temp"
    done < <(nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
  fi

  # CPU (portable awk: use RSTART/RLENGTH; then fallback to sensors -u temp*_input)
  cpu="$(sensors 2>/dev/null | awk '
    /^(Package id 0|Tctl|Tdie|CPU Temp|CPU Temperature|Composite):/ {
      if (match($0, /[0-9]+(\.[0-9]+)?/)) { print substr($0, RSTART, RLENGTH); exit }
    }
    /^temp1:/ {
      if (match($0, /[0-9]+(\.[0-9]+)?/)) { print substr($0, RSTART, RLENGTH); exit }
    }
  ')"
  [ -z "$cpu" ] && cpu="$(sensors -u 2>/dev/null | awk '/^temp[0-9]*_input:/ {print $2; exit}')"
  [ -n "$cpu" ] && V["CPU"]="$cpu"

  # SATA disks
  for d in "${SATAS[@]}"; do
    t="$(sudo smartctl -A "/dev/$d" 2>/dev/null \
        | awk '/194 Temperature_Celsius|190 Airflow_Temperature_Cel/ {print $10; exit}
               /Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+$/){print $i; exit}}')"
    [ -n "$t" ] && V["$d"]="$t"
  done

  # NVMe controllers
  for n in "${NVMES[@]}"; do
    t="$(sudo nvme smart-log "/dev/$n" 2>/dev/null | awk '/^temperature/ {print $3; exit}')"
    [ -z "$t" ] && t="$(sudo smartctl -A "/dev/${n}n1" -d nvme 2>/dev/null \
                       | awk '/Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+(\.[0-9]+)?$/){print $i; exit}}')"
    [ -n "$t" ] && V["$n"]="$t"
  done

  # CSV row (quote fields that may contain spaces/commas)
  row="\"$ts\""
  for g in "${GPUS[@]}";  do row+=",${V["GPU$g"]}"; done
  row+=",${V["CPU"]}"
  for s in "${SATAS[@]}"; do row+=",${V["$s"]}"; done
  for n in "${NVMES[@]}"; do row+=",${V["$n"]}"; done
  row+=",\"$DEVICE_STR\""

  # Live human-readable line
  live="[LIVE $ts] "
  for g in "${GPUS[@]}"; do
    val="${V["GPU$g"]}"; [ -n "$val" ] && live+="GPU$g=${val}°C " || live+="GPU$g=NA "
  done
  [ -n "${V["CPU"]}" ] && live+="CPU=${V["CPU"]}°C " || live+="CPU=NA "
  disk_str=""
  for s in "${SATAS[@]}"; do
    val="${V["$s"]}"; [ -n "$val" ] && disk_str+="$s=${val}°C " || disk_str+="$s=NA "
  done
  for n in "${NVMES[@]}"; do
    val="${V["$n"]}"; [ -n "$val" ] && disk_str+="$n=${val}°C " || disk_str+="$n=NA "
  done
  [ -n "$disk_str" ] && live+="DISKS: $disk_str"
  printf '%s\n' "$live"

  # Append CSV row (and show it)
  echo "$row" | tee -a "$OUTFILE"
  printf '[INFO %s] appended row to %s (%d chars)\n' "$ts" "$OUTFILE" "${#row}" >&2

  sleep "$interval"
done
