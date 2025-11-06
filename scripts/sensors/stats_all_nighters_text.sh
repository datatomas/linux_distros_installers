#!/usr/bin/env bash
interval="${1:-5}"
LOG_DIR="/home/ares/Documents/pcstats"
mkdir -p "$LOG_DIR"

while true; do
  ts="$(date '+%F %T')"
  gpu="$(nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
        | awk -F',' '{gsub(/ /,"",$1); gsub(/ /,"",$2); printf "GPU%s=%sC ", $1, $2}')"
  [ -z "$gpu" ] && gpu="GPU=none"

  cpu="$(sensors 2>/dev/null \
        | awk -F'[:+ ]+' '/Package id 0|Tctl/{print "CPU="$3"C"; f=1; exit} END{if(!f) exit 1}')"
  [ -z "$cpu" ] && cpu="$(sensors 2>/dev/null | awk -F'[:+ ]+' '/temp1/{print "CPU="$3"C"; exit}')"
  [ -z "$cpu" ] && cpu="CPU=unknown"

  sata=""
  for d in /dev/sd?; do
    [ -e "$d" ] || continue
    t="$(sudo smartctl -A "$d" 2>/dev/null \
        | awk '/194 Temperature_Celsius|190 Airflow_Temperature_Cel/ {print $10; exit}
               /Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+$/){print $i; exit}}')"
    [ -n "$t" ] && sata+=$(printf "%s=%sC " "$(basename "$d")" "$t")
  done

  nvme=""
  for n in /dev/nvme*n1; do
    [ -e "$n" ] || continue
    ctrl="${n%n1}"
    t="$(sudo nvme smart-log "$ctrl" 2>/dev/null | awk '/^temperature/ {print $3; exit}')"
    [ -z "$t" ] && t="$(sudo smartctl -A "$n" -d nvme 2>/dev/null | awk '/Temperature/ {for(i=NF;i>=1;i--) if($i ~ /^[0-9]+(\.[0-9]+)?$/){print $i; exit}}')"
    [ -n "$t" ] && nvme+=$(printf "%s=%sC " "$(basename "$ctrl")" "$t")
  done

  line="$ts  $gpu  $cpu  DISKS: $sata$nvme"
  echo "$line"
  printf "%s\n" "$line" >> "$LOG_DIR/temps_$(date +%F).log"
  sleep "$interval"
done
