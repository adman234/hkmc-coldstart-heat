#!/system/bin/sh
# coldstart.heat (always-on edition) - every time the car is started, apply the
# configured steering wheel heat and seat action. No temperature sensor.
#
# WHY THIS IS A MONITOR: mode=background runs a service once per Linux boot.
# When the head unit only sleeps (QuickBoot) and is not fully powered off, the
# service is already running and a car start is just the screen waking up, so
# a run-once script never fires. This service therefore stays resident and
# applies the settings on each start signal:
#   - first pass after the service starts (new kernel boot, or no session marker)
#   - display turning on after being off for MIN_OFF seconds
#   - session marker in /data/local/tmp cleared (QuickBoot wipes it)
#   - a long uptime gap while the display is on (suspend/resume)
# Wake detection follows the same approach as the factory82 package.
#
# Actuation (verified on-car, NEEV.USA...260507):
#   wheel:      service call com.hkmc.vr 16 i32 1
#   drv seat:   service call com.hkmc.micom.usm 213 i32 <enum>
#   pass seat:  service call com.hkmc.micom.usm 214 i32 <enum>
#   heat enum:  2=Off 6=Low 7=Med 8=High ; config level 1/2/3 -> 6/7/8
# Cool/vent enums are NOT verified: cool only acts if vent_enum_1/2/3 are set.
#
# Log of the last runs: /data/nemesis/state/coldstart.heat/run.log
# TEST WHILE PARKED.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

TAG=coldstart.heat
STATE=/data/nemesis/state/$TAG
DUMPSYS=${CS_DUMPSYS_BIN:-/system/bin/dumpsys}
FB_BLANK=${CS_FB_BLANK:-/sys/class/graphics/fb0/blank}
BOOT_ID_FILE=${CS_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
SESSION=${CS_SESSION_MARKER:-/data/local/tmp/coldstart.heat.session}
POLL=${CS_POLL_SECONDS:-3}
MAX_LOOPS=${CS_MAX_LOOPS:-0}          # 0 = run forever (tests set a number)
COOLDOWN=${CS_COOLDOWN_SECONDS:-15}   # ignore wakes this soon after an apply
MIN_OFF=${CS_MIN_OFF_SECONDS:-20}     # screen must have been off this long
GAP_SECONDS=45
mkdir -p "$STATE" 2>/dev/null
RUNLOG=$STATE/run.log
log() { echo "coldstart: $(date 2>/dev/null) $*"; echo "$(date 2>/dev/null) $*" >> "$RUNLOG" 2>/dev/null; }

cfg() { _f="$STATE/$1"; _d="$2"; if [ -r "$_f" ]; then read -r _v < "$_f" 2>/dev/null; case "$_v" in ''|*[!0-9-]*) echo "$_d";; *) echo "$_v";; esac; else echo "$_d"; fi; }

uptime_seconds() {
    UP=0
    [ -r /proc/uptime ] && read -r UP _UNUSED < /proc/uptime
    UP=${UP%%.*}; case "$UP" in ''|*[!0-9]*) UP=0;; esac
    echo "$UP"
}

# on / off / unknown. Prefers the display power policy over general wakefulness.
read_display_state() {
    if [ -x "$DUMPSYS" ]; then
        _p=$($DUMPSYS power 2>/dev/null)
        case "$_p" in
            *'mDisplayPowerRequest=policy=OFF'*|*'mDisplayPowerRequest=policy=0'*) echo off; return;;
            *'mDisplayPowerRequest=policy=BRIGHT'*|*'mDisplayPowerRequest=policy=DIM'*) echo on; return;;
            *'mScreenOn=false'*|*'mInteractive=false'*|*'mWakefulness=Asleep'*|*'mWakefulness=Dozing'*) echo off; return;;
            *'mScreenOn=true'*|*'mInteractive=true'*|*'mWakefulness=Awake'*) echo on; return;;
        esac
    fi
    if [ -r "$FB_BLANK" ]; then
        _b=$(cat "$FB_BLANK" 2>/dev/null)
        case "$_b" in 0) echo on; return;; 1|2|3|4) echo off; return;; esac
    fi
    echo unknown
}

write_session_marker() {
    _par=${SESSION%/*}
    if [ -d "$_par" ] && ( echo "$(uptime_seconds) $BOOT_ID" > "$SESSION" ) 2>/dev/null; then SESSION_WATCH=1
    else SESSION_WATCH=0; fi
}

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

apply_once() {
    _why=$1
    NOW=$(uptime_seconds)
    if [ "$NOW" -gt 0 ] && [ "$LAST_APPLY" -gt 0 ]; then
        _el=$((NOW - LAST_APPLY))
        if [ "$_el" -ge 0 ] && [ "$_el" -lt "$COOLDOWN" ]; then
            log "coalesced start signal ($_why; ${_el}s since last apply)"; write_session_marker; return
        fi
    fi
    LAST_APPLY=$NOW
    # settings are re-read each time so changes in the app take effect without a reboot
    ENABLED=$(cfg enabled 1); WHEEL=$(cfg wheel 1)
    SEAT_DRV=$(cfg seat_drv 0); SEAT_PASS=$(cfg seat_pass 0); SEAT_MODE=$(cfg seat_mode 0)
    MAX_WAIT=$(cfg max_wait 120); DELAY=$(cfg start_delay 3)
    log "START SIGNAL: $_why; display=$DISPLAY_STATE; uptime=$NOW; enabled=$ENABLED wheel=$WHEEL drv=$SEAT_DRV pass=$SEAT_PASS mode=$SEAT_MODE"
    if [ "$ENABLED" != "1" ]; then log "disabled; no action"; write_session_marker; return; fi

    i=0; ready=0
    while [ "$i" -lt "$MAX_WAIT" ]; do
        service check com.hkmc.vr 2>/dev/null | grep -q ': found' && { ready=1; break; }
        sleep 2; i=$((i + 2))
    done
    if [ "$ready" = "1" ]; then log "vr ready after ${i}s"; else log "vr not ready after ${MAX_WAIT}s; trying anyway"; fi
    [ "$DELAY" -gt 0 ] 2>/dev/null && sleep "$DELAY"

    if [ "$WHEEL" = "1" ]; then
        service call com.hkmc.vr 16 i32 1 >/dev/null 2>&1; log "wheel on (exit $?)"
    fi
    seat_apply drv 213 "$SEAT_DRV"
    seat_apply pass 214 "$SEAT_PASS"
    log "done"
    write_session_marker
}

# keep the log small
_sz=$(wc -c < "$RUNLOG" 2>/dev/null || echo 0); case "$_sz" in ''|*[!0-9]*) _sz=0;; esac
[ "$_sz" -gt 65536 ] && mv "$RUNLOG" "$RUNLOG.1" 2>/dev/null

BOOT_ID=unknown
[ -r "$BOOT_ID_FILE" ] && BOOT_ID=$(cat "$BOOT_ID_FILE" 2>/dev/null)
LAST_APPLY=0; SESSION_WATCH=1; LAST_SEEN=0; LAST_DISPLAY=unknown; OFF_SINCE=0
INITIAL=1; DISPLAY_STATE=unknown; LOOPS=0
log "monitor started; boot_id=$BOOT_ID; session=$SESSION"

while :; do
    DISPLAY_STATE=$(read_display_state)
    NOW=$(uptime_seconds)
    [ "$DISPLAY_STATE" != "$LAST_DISPLAY" ] && log "display: $LAST_DISPLAY -> $DISPLAY_STATE"
    [ "$DISPLAY_STATE" = off ] && [ "$LAST_DISPLAY" != off ] && OFF_SINCE=$NOW

    REASON=''
    if [ "$INITIAL" -eq 1 ]; then
        _sb=''
        if [ -f "$SESSION" ]; then read -r _su _sb < "$SESSION" || :; fi
        if [ "$DISPLAY_STATE" != off ]; then
            if [ ! -f "$SESSION" ]; then REASON=service-start-no-marker
            elif [ -z "$_sb" ]; then REASON=service-start-invalid-marker
            elif [ "$BOOT_ID" != unknown ] && [ "$_sb" != "$BOOT_ID" ]; then REASON=new-kernel-boot
            else log "marker matches this boot; waiting for the next start signal"; fi
        else
            log "display off at service start; waiting for it to turn on"
        fi
        INITIAL=0
    else
        if [ "$DISPLAY_STATE" = on ] && [ "$LAST_DISPLAY" = off ]; then
            if [ $((NOW - OFF_SINCE)) -ge "$MIN_OFF" ] || [ "$NOW" -le 0 ]; then REASON=display-wake
            else log "screen was off only $((NOW - OFF_SINCE))s; not a car start"; fi
        elif [ "$SESSION_WATCH" -eq 1 ] && [ ! -f "$SESSION" ] && [ "$DISPLAY_STATE" != off ]; then
            REASON=quickboot-marker-cleared
        elif [ "$NOW" -gt 0 ] && [ "$LAST_SEEN" -gt 0 ] && [ "$DISPLAY_STATE" != off ]; then
            GAP=$((NOW - LAST_SEEN))
            [ "$GAP" -ge "$GAP_SECONDS" ] && REASON="resume-gap-${GAP}s"
        fi
    fi

    if [ -n "$REASON" ]; then
        apply_once "$REASON"
        NOW=$(uptime_seconds)   # time spent applying is not a suspend gap
    fi
    LAST_DISPLAY=$DISPLAY_STATE
    LAST_SEEN=$NOW
    LOOPS=$((LOOPS + 1))
    if [ "$MAX_LOOPS" -gt 0 ] && [ "$LOOPS" -ge "$MAX_LOOPS" ]; then exit 0; fi
    sleep "$POLL"
done
