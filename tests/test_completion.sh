#!/bin/bash
# Tests for the bash completion in completions/check_sensor.
# Run: tests/test_completion.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/check_sensor"
COMPLETION="$ROOT/completions/check_sensor"
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

# check_sensor -l, with the chips and sensors in tests/data
cat > "$FAKE_BIN/sensors" <<FAKE
#!/bin/bash
if [ -n "\$2" ]; then
	jq --arg c "\$2" '{(\$c): .[\$c]}' "$ROOT/tests/data/sensors-J.json"
else
	cat "$ROOT/tests/data/sensors-J.json"
fi
FAKE
chmod +x "$FAKE_BIN/sensors"

FAILURES=0
TESTS=0

# the candidates, one per line, bash offers for the last argument, which may be empty
complete_words(){
	PATH="$FAKE_BIN:$PATH" bash -c 'source "$1"; shift; COMP_WORDS=("$@"); COMP_CWORD=$(($# - 1))
		_check_sensor; printf "%s\n" "${COMPREPLY[@]}"' bash "$COMPLETION" "$CHECK" "$@" | grep . | sort
}

# expect NAME EXPECTED ACTUAL
expect(){
	TESTS=$((TESTS + 1))
	if [ "$2" == "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: expected\n%s\n     got\n%s\n' "$1" "$2" "$3"
	fi
}

TESTS=$((TESTS + 1))
if bash -n "$COMPLETION"; then echo "ok   syntax"; else FAILURES=$((FAILURES + 1)); echo "FAIL syntax"; fi

# the options -h lists
HELP_OPTIONS=$("$CHECK" -h | sed -n 's/^\(-[[:alnum:]]\) .*/\1/p' | sort)
expect "-h lists options" 9 "$(wc -l <<< "$HELP_OPTIONS")"
expect "exactly the options of -h" "$HELP_OPTIONS" "$(complete_words "")"
expect "chips" "$(printf '%s\n' acpitz-acpi-0 coretemp-isa-0000 nct6775-isa-0290)" "$(complete_words -a "")"
expect "chip prefix" "nct6775-isa-0290" "$(complete_words -a n)"
expect "sensors of all chips" "$(printf '%s\n' fan1 in0 temp1 temp2 temp7)" "$(complete_words -s "")"
expect "sensors of the chip given with -a" "$(printf '%s\n' temp1 temp2)" "$(complete_words -a coretemp-isa-0000 -s "")"
expect "no candidates for a level" "" "$(complete_words -s temp1 -w "")"

echo "$((TESTS - FAILURES)) of $TESTS tests passed"
[ $FAILURES -eq 0 ]
