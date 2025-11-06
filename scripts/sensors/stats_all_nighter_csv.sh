#!/usr/bin/env bash
interval="${1:-5}"
LOG_DIR="/home/ares/Documents/pcstats"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/temps_$(date +%F).csv"

# Write header once
[ -f "$LOG_FILE" ] || echo "timestamp,source,id,value_c" > "$LOG_FILE"

while true; do
  ts="$(date '+%F %T')"

  # ---- GPU(s) ----
  # outputs lines like: 0,55
  nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
  | awk -v ts="$ts" -F',' '{
      gsub(/ /,"",$1); gsub(/ /,"",$2);
      printf "%s,gpu,GPU%s,%s\n", ts, $1, $2
    }' >> "$LOG_FILE"

  # ---- CPU ----
  cpu_val="$(sensors 2>/dev/null \
    | awk -F'[:+ ]+' '/Package id 0|Tctl/{print $3; f=1; exit} END{if(!f) exit 1}')"
  [ -z "$cpu_val" ] && cpu_val="$(sensors 2>/dev/null | awk -F'[:+ ]+' '/temp1/{print $3; exit}')"
  if [ -n "$cpu_val" ]; then
    cpu_val="${cpu_val%[!0-9.]*}"   # strip any trailing non-numeric like °C
    echo "$ts,cpu,CPU,$cpu_val" >> "$LOG_FILE"
  else
    echo "$ts,cpu,CPU," >> "$LOG_FILE"
  fi

  # ---- SATA/SAS disks (/dev/sd?) ----
  for d in /dev/sd?; do
    [ -e "$d" ] || continue
    t="$(sudo smartctl -A "$d" 2>/dev/null \
        | awk '/194 Temperature_Celsius|190 Airflow_Temperature_Cel/ {print $10; exit}
               /Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+$/){print $i; exit}}')"
    [ -n "$t" ] && echo "$ts,disk,${d#/dev/},$t" >> "$LOG_FILE"
  done

  # ---- NVMe disks (/dev/nvme*n1) ----
  for n in /dev/nvme*n1; do
    [ -e "$n" ] || continue
    ctrl="${n%n1}"                   # /dev/nvme0n1 -> /dev/nvme0
    t="$(sudo nvme smart-log "$ctrl" 2>/dev/null | awk '/^temperature/ {print $3; exit}')"
    if [ -z "$t" ]; then
      t="$(sudo smartctl -A "$n" -d nvme 2>/dev/null \
          | awk '/Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+(\.[0-9]+)?$/){print $i; exit}}')"
    fi
    [ -n "$t" ] && echo "$ts,disk,${ctrl#/dev/},$t" >> "$LOG_FILE"
  done

  sleep "$interval"
done
