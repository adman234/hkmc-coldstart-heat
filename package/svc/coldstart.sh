#!/system/bin/sh
# coldstart.heat (always-on edition) - on every start, apply the configured
# steering wheel heat and seat action. No temperature sensor is used at all.
# Config lives in one-value files written by the UI app.
#
# Verified actuation on-car (NEEV.USA...260507):
#   wheel:      service call com.hkmc.vr 16 i32 1              (on)
#   drv seat:   service call com.hkmc.micom.usm 213 i32 <enum>
#   pass seat:  service call com.hkmc.micom.usm 214 i32 <enum>
#   heat enum:  2=Off 6=Low 7=Med 8=High ; config level 1/2/3 maps to 6/7/8
# Cool/vent enums are NOT verified. Cool mode only acts if you supply the three
# codes (vent_enum_1/2/3 for level 1/2/3, found with EXTENDING.md); otherwise
# it logs and does nothing, rather than guess at a hardware value.
#
# Runs once per boot (mode=background). TEST WHILE PARKED.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

TAG=coldstart.heat
STATE=/data/nemesis/state/$TAG
mkdir -p "$STATE" 2>/dev/null
log() { echo "coldstart: $(date 2>/dev/null) $*"; echo "$(date 2>/dev/null) $*" >> "$STATE/run.log" 2>/dev/null; }

cfg() { _f="$STATE/$1"; _d="$2"; if [ -r "$_f" ]; then read -r _v < "$_f" 2>/dev/null; case "$_v" in ''|*[!0-9-]*) echo "$_d";; *) echo "$_v";; esac; else echo "$_d"; fi; }

ENABLED=$(cfg enabled 1)
WHEEL=$(cfg wheel 1)           # 0/1: always apply wheel heat
SEAT_DRV=$(cfg seat_drv 0)     # 0 = no action, 1..3 = level
SEAT_PASS=$(cfg seat_pass 0)
SEAT_MODE=$(cfg seat_mode 0)   # 0 = heat, 1 = cool/vent (needs vent_enum_*)
MAX_WAIT=$(cfg max_wait 120)

: > "$STATE/run.log" 2>/dev/null
log "start enabled=$ENABLED wheel=$WHEEL drv=$SEAT_DRV pass=$SEAT_PASS mode=$SEAT_MODE"
[ "$ENABLED" = "1" ] || { log "disabled; no action"; exit 0; }

# UI level 1/2/3 -> hardware enum, or empty if unknown
seat_enum() {
    if [ "$SEAT_MODE" = "1" ]; then
        _e=$(cfg "vent_enum_$1" "")
        [ -n "$_e" ] && echo "$_e"
    else
        case "$1" in 1) echo 6;; 2) echo 7;; 3) echo 8;; esac
    fi
}
seat_apply() { # $1=name $2=binder code $3=level
    [ "$3" -gt 0 ] 2>/dev/null || return 0
    _e=$(seat_enum "$3")
    if [ -z "$_e" ]; then log "$1 seat: no enum for mode=$SEAT_MODE level=$3; skipped"; return 0; fi
    service call com.hkmc.micom.usm "$2" i32 "$_e" >/dev/null 2>&1
    log "$1 seat mode=$SEAT_MODE lvl$3 -> enum$_e (exit $?)"
}

# wait for the VR service (framework up)
i=0; ready=0
while [ "$i" -lt "$MAX_WAIT" ]; do
    service check com.hkmc.vr 2>/dev/null | grep -q ': found' && { ready=1; log "vr ready"; break; }
    sleep 2; i=$((i + 2))
done
[ "$ready" = "1" ] || log "vr not ready after ${MAX_WAIT}s; trying anyway"

if [ "$WHEEL" = "1" ]; then
    service call com.hkmc.vr 16 i32 1 >/dev/null 2>&1; log "wheel on (exit $?)"
fi
seat_apply drv 213 "$SEAT_DRV"
seat_apply pass 214 "$SEAT_PASS"
log "done"
exit 0
