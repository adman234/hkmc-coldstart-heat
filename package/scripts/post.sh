#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
STATE=/data/nemesis/state/coldstart.heat
mkdir -p "$STATE" 2>/dev/null
# seed defaults only if not already set (settings from older versions are kept)
[ -r "$STATE/enabled" ]   || echo 1 > "$STATE/enabled"
[ -r "$STATE/wheel" ]     || echo 1 > "$STATE/wheel"
[ -r "$STATE/seat_drv" ]  || echo 0 > "$STATE/seat_drv"
[ -r "$STATE/seat_pass" ] || echo 0 > "$STATE/seat_pass"
[ -r "$STATE/seat_mode" ] || echo 0 > "$STATE/seat_mode"
echo "coldstart.heat installed (always-on)"
exit 0
