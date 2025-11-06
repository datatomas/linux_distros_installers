#!/usr/bin/env bash
# CSV system logger: temps + GPU/CPU/RAM/DiskIO/Fans/Voltage (single file, live console)

interval="${1:-5}"
LOG_DIR="${LOG_DIR:-/home/ares/Documents/pcstats}"
mkdir -p "$LOG_DIR"

# -------- filename (no per-run timestamp) ----------
read -rp "Base CSV filename (no extension): " BASE
BASE="${BASE:-temps}"
BASE_CLEAN="$(printf '%s' "$BASE" | tr ' ' '_' | tr -cd '[:alnum:]_.-')"
case "$BASE_CLEAN" in
  *.csv) OUTFILE="$LOG_DIR/$BASE_CLEAN" ;;
  *)     OUTFILE="$LOG_DIR/${BASE_CLEAN}.csv" ;;
esac

# -------- discover hardware once (stable columns for this run) ----------
GPUS=()
if command -v nvidia-smi >/dev/null 2>&1; then
  while read -r idx; do
    idx="$(printf '%s' "$idx" | tr -d ' ')"
    [ -n "$idx" ] && GPUS+=("$idx")
  done < <(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null)
fi

SATAS=()
for d in /dev/sd?; do [ -e "$d" ] && SATAS+=("$(basename "$d")"); done

NVMES_CTRL=()
for n in /dev/nvme*n1; do
  [ -e "$n" ] || continue
  ctrl="${n%n1}"
  NVMES_CTRL+=("$(basename "$ctrl")")     # nvme0, nvme1...
done
# disk devices for iostat (%util)
DISK_IO_DEVS=()
for s in "${SATAS[@]}"; do DISK_IO_DEVS+=("$s"); done
for c in "${NVMES_CTRL[@]}"; do
  [ -e "/dev/${c}n1" ] && DISK_IO_DEVS+=("${c}n1")
done

# fans from sysfs (rpm)
FAN_FILES=()
FAN_COLS=()
for f in /sys/class/hwmon/hwmon*/fan*_input; do
  [ -r "$f" ] || continue
  bn="$(basename "$f")"                             # fan1_input
  col="${bn%_input}_rpm"                            # fan1_rpm
  # de-dup if multiple chips have fan1_input
  if [[ " ${FAN_COLS[*]} " != *" $col "* ]]; then
    FAN_COLS+=("$col"); FAN_FILES+=("$f")
  fi
done

# device string (models)
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

# -------- header (only if file is new/empty) ----------
if [ ! -s "$OUTFILE" ]; then
  {
    printf "timestamp"
    # temps
    for g in "${GPUS[@]}";  do printf ",GPU%s" "$g"; done
    printf ",CPU"
    for s in "${SATAS[@]}"; do printf ",%s" "$s"; done
    for n in "${NVMES_CTRL[@]}"; do printf ",%s" "$n"; done
    # GPU extras
    for g in "${GPUS[@]}"; do
      printf ",GPU%s_util,GPU%s_memutil,GPU%s_powerW,GPU%s_fan" "$g" "$g" "$g" "$g"
    done
    # CPU usage
    printf ",cpu_pct"
    # RAM
    printf ",mem_used_mb,mem_total_mb,mem_used_pct"
    # Disk I/O util
    for d in "${DISK_IO_DEVS[@]}"; do printf ",%s_util" "$d"; done
    # Fans rpm
    for c in "${FAN_COLS[@]}"; do printf ",%s" "$c"; done
    # Voltage
    printf ",vcore_v"
    # Device string
    printf ",device\n"
  } > "$OUTFILE"
fi

echo "Logging to: $OUTFILE"
echo "Interval: ${interval}s. Press Ctrl+C to stop."
echo "Device column: ${DEVICE_STR}"

trap 'echo; echo "Saved to: '"$OUTFILE"'"; exit 0' INT TERM

# -------- CPU usage baseline (from /proc/stat) ----------
read -r _ u n s i ow irq si st _ < /proc/stat
prev_total=$((u+n+s+i+ow+irq+si+st))
prev_idle=$((i+ow))

# -------- main loop ----------
while true; do
  ts="$(date '+%F %T')"
  declare -A V

  # ---- GPU: temp + util + mem util + power + fan ----
  if command -v nvidia-smi >/dev/null 2>&1 && ((${#GPUS[@]})); then
    while IFS=, read -r idx t util memutil power fan; do
      idx="$(printf '%s' "$idx" | tr -d ' ')"
      t="$(printf '%s' "$t" | tr -d ' ')"
      util="$(printf '%s' "$util" | tr -d ' ')"
      memutil="$(printf '%s' "$memutil" | tr -d ' ')"
      power="$(printf '%s' "$power" | tr -d ' ')"
      fan="$(printf '%s' "$fan" | tr -d ' ')"
      [ -n "$t" ] && V["GPU$idx"]="$t"
      V["GPU${idx}_util"]="$util"
      V["GPU${idx}_memutil"]="$memutil"
      V["GPU${idx}_powerW"]="$power"
      V["GPU${idx}_fan"]="$fan"
    done < <(nvidia-smi --query-gpu=index,temperature.gpu,utilization.gpu,utilization.memory,power.draw,fan.speed --format=csv,noheader,nounits 2>/dev/null)
  fi

  # ---- CPU temp (robust) ----
  cpu_temp="$(sensors 2>/dev/null | awk '
    /^(Package id 0|Tctl|Tdie|CPU Temp|CPU Temperature|Composite):/ { if (match($0, /[0-9]+(\.[0-9]+)?/)) { print substr($0,RSTART,RLENGTH); exit } }
    /^temp1:/ { if (match($0, /[0-9]+(\.[0-9]+)?/)) { print substr($0,RSTART,RLENGTH); exit } }
  ')"
  [ -z "$cpu_temp" ] && cpu_temp="$(sensors -u 2>/dev/null | awk '/^temp[0-9]*_input:/ {print $2; exit}')"
  [ -n "$cpu_temp" ] && V["CPU"]="$cpu_temp"

  # ---- CPU usage % (delta from /proc/stat) ----
  read -r _ u n s i ow irq si st _ < /proc/stat
  total=$((u+n+s+i+ow+irq+si+st))
  idle_all=$((i+ow))
  dt=$((total - prev_total))
  di=$((idle_all - prev_idle))
  cpu_pct=""
  if (( dt > 0 )); then
    cpu_pct="$(awk -v dt="$dt" -v di="$di" 'BEGIN{printf "%.1f", (dt-di)*100.0/dt}')"
  fi
  prev_total=$total; prev_idle=$idle_all
  V["cpu_pct"]="$cpu_pct"

  # ---- SATA temps ----
  for d in "${SATAS[@]}"; do
    t="$(sudo smartctl -A "/dev/$d" 2>/dev/null \
        | awk '/194 Temperature_Celsius|190 Airflow_Temperature_Cel/ {print $10; exit}
               /Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+$/){print $i; exit}}')"
    [ -n "$t" ] && V["$d"]="$t"
  done

  # ---- NVMe temps (controller) ----
  for n in "${NVMES_CTRL[@]}"; do
    t="$(sudo nvme smart-log "/dev/$n" 2>/dev/null | awk '/^temperature/ {print $3; exit}')"
    [ -z "$t" ] && t="$(sudo smartctl -A "/dev/${n}n1" -d nvme 2>/dev/null \
                       | awk '/Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+(\.[0-9]+)?$/){print $i; exit}}')"
    [ -n "$t" ] && V["$n"]="$t"
  done

  # ---- RAM usage ----
  mem_total_kb="$(awk '/MemTotal:/{print $2}' /proc/meminfo)"
  mem_avail_kb="$(awk '/MemAvailable:/{print $2}' /proc/meminfo)"
  if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ]; then
    mem_used_kb=$((mem_total_kb - mem_avail_kb))
    mem_used_mb=$((mem_used_kb / 1024))
    mem_total_mb=$((mem_total_kb / 1024))
    mem_used_pct="$(awk -v u="$mem_used_kb" -v t="$mem_total_kb" 'BEGIN{printf "%.1f", (u*100.0)/t}')"
    V["mem_used_mb"]="$mem_used_mb"
    V["mem_total_mb"]="$mem_total_mb"
    V["mem_used_pct"]="$mem_used_pct"
  fi

  # ---- Disk I/O %util (needs iostat from sysstat) ----
  declare -A IO_UTIL
  if command -v iostat >/dev/null 2>&1 && ((${#DISK_IO_DEVS[@]})); then
    while read -r dev util; do
      IO_UTIL["$dev"]="$util"
    done < <(iostat -dx 1 1 2>/dev/null | awk 'NR>3 && $1 ~ /^[a-z]/ {print $1, $(NF)}')
  fi

  # ---- Fans (rpm) ----
  for i in "${!FAN_FILES[@]}"; do
    rpm="$(cat "${FAN_FILES[$i]}" 2>/dev/null)"
    V["${FAN_COLS[$i]}"]="$rpm"
  done

  # ---- Voltage (vcore best-effort) ----
  vcore="$(sensors 2>/dev/null | awk '
    tolower($0) ~ /vcore|vddcr|vdd_cpu|svi2|vcore soc/ {
      if (match($0, /[0-9]+(\.[0-9]+)?/)) { print substr($0,RSTART,RLENGTH); exit }
    }')"
  [ -z "$vcore" ] && vcore="$(sensors -u 2>/dev/null | awk '/^in[0-9]+_input:/ {print $2; exit}')"
  V["vcore_v"]="$vcore"

  # -------- CSV row (keep column order same as header) ----------
  row="\"$ts\""
  for g in "${GPUS[@]}";  do row+=",${V["GPU$g"]}"; done
  row+=","${V["CPU"]}
  for s in "${SATAS[@]}"; do row+=",${V["$s"]}"; done
  for n in "${NVMES_CTRL[@]}"; do row+=",${V["$n"]}"; done
  for g in "${GPUS[@]}"; do
    row+=",${V["GPU${g}_util"]},${V["GPU${g}_memutil"]},${V["GPU${g}_powerW"]},${V["GPU${g}_fan"]}"
  done
  row+=","${V["cpu_pct"]}
  row+=","${V["mem_used_mb"]}","${V["mem_total_mb"]}","${V["mem_used_pct"]}
  for d in "${DISK_IO_DEVS[@]}"; do row+=",${IO_UTIL["$d"]}"; done
  for c in "${FAN_COLS[@]}"; do row+=",${V["$c"]}"; done
  row+=","${V["vcore_v"]}
  row+=",\"$DEVICE_STR\""

  # -------- LIVE line (human-readable) ----------
  live="[LIVE $ts] "
  for g in "${GPUS[@]}"; do
    live+="GPU$g=${V["GPU$g"]}°C(util:${V["GPU${g}_util"]}%%,mem:${V["GPU${g}_memutil"]}%%,P:${V["GPU${g}_powerW"]}W,fan:${V["GPU${g}_fan"]}%%) "
  done
  [ -n "${V["CPU"]}" ] && live+="CPU=${V["CPU"]}°C(${V["cpu_pct"]}%%) " || live+="CPU=NA "
  live+="RAM=${V["mem_used_mb"]}/${V["mem_total_mb"]}MB(${V["mem_used_pct"]}%%) "
  if ((${#DISK_IO_DEVS[@]})); then
    live+="DISK:"
    for d in "${DISK_IO_DEVS[@]}"; do
      util="${IO_UTIL["$d"]}"; [ -n "$util" ] || util="NA"
      live+=" ${d}=${util}%%"
    done
    live+=" "
  fi
  for i in "${!FAN_COLS[@]}"; do
    rpm="${V["${FAN_COLS[$i]}"]}"; [ -n "$rpm" ] || rpm="NA"
    live+="${FAN_COLS[$i]}=${rpm}rpm "
  done
  [ -n "${V["vcore_v"]}" ] && live+="Vcore=${V["vcore_v"]}V "
  printf '%s\n' "$live"

  # -------- write + info ----------
  echo "$row" | tee -a "$OUTFILE"
  printf '[INFO %s] appended row to %s (%d chars)\n' "$ts" "$OUTFILE" "${#row}" >&2

  sleep "$interval"
done
