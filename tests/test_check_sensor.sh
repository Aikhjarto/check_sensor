#!/bin/bash
# Tests for check_sensor with a fake sensors command, for the JSON of
# sensors -J (lm-sensors 3.6.2 and later) and sensors -j (older versions).
# Run: tests/test_check_sensor.sh

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$TESTS_DIR/../check_sensor"
FAKE_BIN=$(mktemp -d)
NO_SENSORS=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN" "$NO_SENSORS"' EXIT

# sensors, controlled by FAKE_* variables:
# FAKE_FORMAT new or old, FAKE_SET "CHIP FEATURE SUBFEATURE VALUE" (VALUE NaN for an unreadable one)
cat > "$FAKE_BIN/sensors" <<FAKE
#!/bin/bash
DATA="$TESTS_DIR/data"
FAKE
cat >> "$FAKE_BIN/sensors" <<'FAKE'
[ -z "$FAKE_SLEEP" ] || sleep "$FAKE_SLEEP"
if [ "${FAKE_FORMAT:-new}" == new ]; then
	[ "$1" == "-J" ] || { echo "unexpected $1" >&2; exit 1; }
	json=$(cat "$DATA/sensors-J.json")
	set_value='.[$c][$f][$s].value = $v'
	nan=NaN
else
	if [ "$1" == "-J" ]; then
		echo "sensors: invalid option -- 'J'" >&2
		echo "Usage: sensors [OPTION]... [CHIP]..." >&2
		exit 1
	fi
	json=$(cat "$DATA/sensors-j.json")
	set_value='.[$c] |= with_entries(if (.value | type) == "object" and (.value | keys | any(startswith($f + "_"))) then .value[$f + "_" + $s] = $v else . end)'
	nan=nan
fi
if [ -n "$FAKE_SET" ]; then
	read -r c f s v <<< "$FAKE_SET"
	if [ "$v" == NaN ]; then
		json=$(jq --arg c "$c" --arg f "$f" --arg s "$s" --arg v __NAN__ "$set_value" <<< "$json" | sed "s/\"__NAN__\"/$nan/")
	else
		json=$(jq --arg c "$c" --arg f "$f" --arg s "$s" --argjson v "$v" "$set_value" <<< "$json")
	fi
fi
if [ -n "$2" ]; then
	if [ "$(jq --arg c "$2" 'has($c)' <<< "${json//NaN/null}")" != true ]; then
		echo "Specified sensor(s) not found!" >&2
		exit 1
	fi
	json=$(jq --arg c "$2" '{($c): .[$c]}' <<< "${json//NaN/null}")
fi
echo "$json"
FAKE
chmod +x "$FAKE_BIN/sensors"

# a PATH with the tools check_sensor needs, but without sensors
for tool in bash timeout grep mktemp rm awk sed jq wc head; do
	ln -s "$(command -v $tool)" "$NO_SENSORS/$tool"
done

export PATH="$FAKE_BIN:$PATH"

FAILURES=0
TESTS=0

# expect NAME EXIT_CODE OUTPUT_REGEX [ENV=VALUE ...] -- [ARGS ...]
expect(){
	local name=$1 code=$2 regex=$3 envs=() out rc
	shift 3
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
	shift
	out=$(env "${envs[@]}" "$CHECK" "$@" 2>&1)
	rc=$?
	TESTS=$((TESTS + 1))
	if [ $rc -ne "$code" ] || ! [[ "$out" =~ $regex ]] || [ "$(wc -l <<< "$out")" -ne 1 ]; then
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: exit %s (expected %s)\n     %s\n' "$name" $rc "$code" "$out"
	else
		printf 'ok   %s\n' "$name"
	fi
}

for FORMAT in new old; do
	F="FAKE_FORMAT=$FORMAT"
	if [ $FORMAT == new ]; then echo "--- sensors -J"; else echo "--- sensors -j"; fi

	expect "by label" 0 '^SENSOR OK - Package id 0 on ISA adapter is 45°C\|coretemp-isa-0000-temp1=45;80;100;;$' "$F" -- -s "Package id 0"
	expect "by name, unique" 0 '^SENSOR OK - Core 0 on ISA adapter is 43°C\|coretemp-isa-0000-temp2=43;80;100;;$' "$F" -- -s temp2
	expect "by name on several chips" 3 '^SENSOR UNKNOWN - several sensors match temp1, choose one with -a or by name: coretemp-isa-0000 temp1, acpitz-acpi-0 temp1$' "$F" -- -s temp1
	expect "chosen with -a" 0 '^SENSOR OK - temp1 on ACPI interface is 27\.8°C\|acpitz-acpi-0-temp1=27\.8;;105;;$' "$F" -- -a acpitz-acpi-0 -s temp1
	expect "above max" 1 '^SENSOR WARNING - Package id 0 on ISA adapter is 85°C \(above max 80°C\)\|coretemp-isa-0000-temp1=85;80;100;;$' \
		"$F" "FAKE_SET=coretemp-isa-0000 temp1 input 85" -- -s "Package id 0"
	expect "above crit" 2 '^SENSOR CRITICAL - Package id 0 on ISA adapter is 101°C \(above crit 100°C\)' \
		"$F" "FAKE_SET=coretemp-isa-0000 temp1 input 101" -- -s "Package id 0"
	expect "critical alarm" 2 '^SENSOR CRITICAL - Core 0 on ISA adapter is 43°C \(critical alarm of the chip\)' \
		"$F" "FAKE_SET=coretemp-isa-0000 temp2 crit_alarm 1" -- -s "Core 0"
	expect "voltage within min and max" 0 '^SENSOR OK - Vcore on ISA adapter is 1\.104V\|nct6775-isa-0290-in0=1\.104;;0\.5:1\.744;;$' "$F" -- -s Vcore
	expect "voltage below min" 2 '^SENSOR CRITICAL - Vcore on ISA adapter is 0\.4V \(below min 0\.5V\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 in0 input 0.4" -- -s in0
	expect "voltage at max" 0 '^SENSOR OK - Vcore on ISA adapter is 1\.744V' "$F" "FAKE_SET=nct6775-isa-0290 in0 input 1.744" -- -s Vcore
	expect "fan above min" 0 '^SENSOR OK - fan1 on ISA adapter is 1205RPM\|nct6775-isa-0290-fan1=1205;;300:;;$' "$F" -- -s fan1
	expect "fan below min" 2 '^SENSOR CRITICAL - fan1 on ISA adapter is 200RPM \(below min 300RPM\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 fan1 input 200" -- -s fan1
	expect "chip alarm" 1 '^SENSOR WARNING - fan1 on ISA adapter is 1205RPM \(alarm of the chip\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 fan1 alarm 1" -- -s fan1
	expect "sensor fault" 2 '^SENSOR CRITICAL - fan1 on ISA adapter is 1205RPM \(sensor fault\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 fan1 fault 1" -- -s fan1
	expect "unreadable value" 3 '^SENSOR UNKNOWN - SYSTIN on nct6775-isa-0290 has no readable value$' \
		"$F" "FAKE_SET=nct6775-isa-0290 temp7 input NaN" -- -s SYSTIN
	expect "unreadable limit" 0 '^SENSOR OK - SYSTIN on ISA adapter is 35°C\|nct6775-isa-0290-temp7=35;;;;$' \
		"$F" "FAKE_SET=nct6775-isa-0290 temp7 max NaN" -- -s SYSTIN

	expect "levels: below -w" 0 '^SENSOR OK - .*\|coretemp-isa-0000-temp1=45;70;90;;$' "$F" -- -s "Package id 0" -w 70 -c 90
	expect "levels: above -w" 1 '^SENSOR WARNING - Package id 0 on ISA adapter is 75°C \(above 70°C\)' \
		"$F" "FAKE_SET=coretemp-isa-0000 temp1 input 75" -- -s "Package id 0" -w 70 -c 90
	expect "levels: above -c" 2 '^SENSOR CRITICAL - .*\(above 90°C\)' \
		"$F" "FAKE_SET=coretemp-isa-0000 temp1 input 95" -- -s "Package id 0" -w 70 -c 90
	expect "levels override the chip" 0 '^SENSOR OK - Package id 0 on ISA adapter is 85°C\|' \
		"$F" "FAKE_SET=coretemp-isa-0000 temp1 input 85" -- -s "Package id 0" -w 90 -c 95
	expect "levels: only -c" 2 '^SENSOR CRITICAL - .*\(above 40°C\)\|coretemp-isa-0000-temp1=45;;40;;$' "$F" -- -s "Package id 0" -c 40
	expect "low levels: fan OK" 0 '^SENSOR OK - .*\|nct6775-isa-0290-fan1=1205;800:;500:;;$' "$F" -- -s fan1 -w 800 -c 500
	expect "low levels: fan below -w" 1 '^SENSOR WARNING - fan1 on ISA adapter is 600RPM \(below 800RPM\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 fan1 input 600" -- -s fan1 -w 800 -c 500
	expect "low levels: fan below -c" 2 '^SENSOR CRITICAL - fan1 on ISA adapter is 0RPM \(below 500RPM\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 fan1 input 0" -- -s fan1 -w 800 -c 500
	expect "fault with levels" 2 '^SENSOR CRITICAL - .*\(sensor fault\)' \
		"$F" "FAKE_SET=nct6775-isa-0290 fan1 fault 1" -- -s fan1 -w 800 -c 500

	expect "unknown sensor" 3 '^SENSOR UNKNOWN - no sensor temp9; -l lists the sensors$' "$F" -- -s temp9
	expect "unknown sensor on a chip" 3 '^SENSOR UNKNOWN - no sensor Vcore on coretemp-isa-0000; -l lists the sensors$' "$F" -- -a coretemp-isa-0000 -s Vcore
	expect "unknown chip" 3 '^SENSOR UNKNOWN - sensors failed with status 1: Specified sensor\(s\) not found!$' "$F" -- -a nosuch-isa-0000 -s temp1

	out=$(env "$F" "$CHECK" -l)
	rc=$?
	TESTS=$((TESTS + 1))
	expected=$(printf '%s\t%s\t%s\t%s\t%s\n' CHIP SENSOR LABEL VALUE LIMITS \
		coretemp-isa-0000 temp1 "Package id 0" 45°C "max 80 crit 100" \
		coretemp-isa-0000 temp2 "Core 0" 43°C "max 80 crit 100" \
		nct6775-isa-0290 in0 Vcore 1.104V "min 0.5 max 1.744" \
		nct6775-isa-0290 fan1 fan1 1205RPM "min 300" \
		nct6775-isa-0290 temp7 SYSTIN 35°C "max 80" \
		acpitz-acpi-0 temp1 temp1 27.8°C "crit 105")
	if [ $rc -eq 0 ] && [ "$out" == "$expected" ]; then
		echo "ok   list"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL list: exit %s, expected\n%s\n     got\n%s\n' $rc "$expected" "$out"
	fi
done

echo "--- options and errors"
expect "timeout" 3 '^SENSOR UNKNOWN - sensors did not answer within 1s$' FAKE_SLEEP=3 -- -s temp2 -t 1
expect "sensors missing" 3 '^SENSOR UNKNOWN - sensors not found, install lm-sensors$' PATH="$NO_SENSORS" -- -s temp2
expect "no sensor given" 3 '^SENSOR UNKNOWN - the sensor must be given with -s; -l lists them$' --
expect "bad warning level" 3 "^SENSOR UNKNOWN - the warning level must be a number, not 'x'$" -- -s temp2 -w x
expect "bad critical level" 3 "^SENSOR UNKNOWN - the critical level must be a number, not '1,5'$" -- -s temp2 -c 1,5
expect "negative level" 0 '^SENSOR OK - Core 0' -- -s temp2 -w -10 -c -20
expect "bad timeout" 3 "^SENSOR UNKNOWN - the timeout must be a positive number of seconds, not '0'$" -- -s temp2 -t 0
expect "missing option argument" 3 '^SENSOR UNKNOWN - option -s needs an argument$' -- -s
expect "unknown option" 3 '^SENSOR UNKNOWN - unknown option -x$' -- -x
expect "extra argument" 3 '^SENSOR UNKNOWN - unexpected argument foo$' -- -s temp2 foo
expect "version" 3 '^check_sensor 0\.1$' -- -V

TESTS=$((TESTS + 1))
if "$CHECK" -h | grep -q '^Usage: check_sensor'; then echo "ok   help"; else FAILURES=$((FAILURES + 1)); echo "FAIL help"; fi

echo "$((TESTS - FAILURES)) of $TESTS tests passed"
[ $FAILURES -eq 0 ]
