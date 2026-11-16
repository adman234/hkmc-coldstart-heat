#!/bin/bash
# Off-car test of package/svc/coldstart.sh: fake service/sleep, state in a temp dir.
# Uses mksh (what the head unit runs) when installed, else sh.
#   tools/test_coldstart.sh [script]
SRC=${1:-$(cd "$(dirname "$0")/.." && pwd)/package/svc/coldstart.sh}
SH=$(command -v mksh || command -v sh)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/service" <<'E2'
#!/bin/sh
case "$1" in check) echo "Service $2: found" ;; call) shift; echo "$*" >> "$T/sent" ;; esac
E2
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/"*
export T
sed -e "s#^export PATH=.*#export PATH=$T/bin:/usr/bin:/bin#" -e "s#^STATE=.*#STATE=$T/state#" "$SRC" > "$T/cs.sh"
pass=0 fail=0
sc() {  # sc <name> <state k=v,...> <expected sends>
    rm -f "$T/sent" "$T"/state/*
    for kv in ${2//,/ }; do echo "${kv#*=}" > "$T/state/${kv%%=*}"; done
    "$SH" "$T/cs.sh" > "$T/log" 2>&1
    got=$(cat "$T/sent" 2>/dev/null)
    if [ "$got" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo " want: ${3//$'\n'/ | }"; echo " got:  ${got//$'\n'/ | }"; cat "$T/log"; fi
}
W="com.hkmc.vr 16 i32 1"
D6="com.hkmc.micom.usm 213 i32 6"; D7="com.hkmc.micom.usm 213 i32 7"; D8="com.hkmc.micom.usm 213 i32 8"
P8="com.hkmc.micom.usm 214 i32 8"
sc "defaults: wheel only"                      ""                                   "$W"
sc "wheel off, no seats: nothing"              "wheel=0"                            ""
sc "driver low"                                "wheel=0,seat_drv=1"                 "$D6"
sc "driver med"                                "wheel=0,seat_drv=2"                 "$D7"
sc "wheel + driver high"                       "seat_drv=3"                         "$W"$'\n'"$D8"
sc "driver + passenger high"                   "wheel=0,seat_drv=3,seat_pass=3"     "$D8"$'\n'"$P8"
sc "passenger only"                            "wheel=0,seat_pass=3"                "$P8"
sc "disabled: nothing"                         "enabled=0,seat_drv=3"               ""
sc "cool, no vent codes: seat skipped"         "wheel=0,seat_drv=2,seat_mode=1"     ""
sc "cool with vent codes"                      "wheel=0,seat_drv=2,seat_mode=1,vent_enum_2=11" "com.hkmc.micom.usm 213 i32 11"
sc "cool does not touch wheel"                 "seat_mode=1,seat_drv=1"             "$W"
sc "junk config falls back to default"         "wheel=abc,seat_drv=x"               "$W"
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
