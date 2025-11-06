sudo apt update
sudo apt install -y lm-sensors smartmontools nvme-cli
# Optional, if not installed already:
# sudo apt install -y nvidia-utils-535  # or whatever provides `nvidia-smi` on your system
sudo sensors-detect --auto   # one-time sensor setup

watch -n 5 '
echo -n "$(date "+%F %T")  ";

# GPU temps
nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
 | awk -F"," '\''{gsub(/ /,""); printf "GPU%s=%sC ",$1,$2} END{if(NR==0) printf "GPU=none "}'\''

# CPU temp (Package id 0 or Tctl, fallback to first temp1)
(sensors 2>/dev/null | awk -F"[:+ ]+" '\''/Package id 0|Tctl/{print "CPU="$3"C"; f=1; exit} END{if(!f) exit 1}'\'') \
  || (sensors 2>/dev/null | awk -F"[:+ ]+" '\''/temp1/{print "CPU="$3"C"; exit}'\'')

# SATA/SAS disk temps
for d in /dev/sd?; do
  [ -e "$d" ] || continue
  t=$(sudo smartctl -A "$d" 2>/dev/null | awk '\''/194 Temperature_Celsius|190 Airflow_Temperature_Cel/ {print $10; exit}'\'')
  [ -n "$t" ] && printf " %s=%sC" "$(basename "$d")" "$t"
done

# NVMe disk temps
for n in /dev/nvme*n1; do
  [ -e "$n" ] || continue
  ctrl=${n%n1}
  t=$(sudo nvme smart-log "$ctrl" 2>/dev/null | awk '\''/^temperature/ {print $3; exit}'\'')
  [ -n "$t" ] && printf " %s=%sC" "$(basename "$ctrl")" "$t"
done

echo
'
