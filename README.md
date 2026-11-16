# check_sensor

A Nagios/Icinga plugin that checks a hardware sensor read by lm-sensors: a
temperature, fan speed, voltage, power or current.

```sh
check_sensor -l
check_sensor -s "Package id 0"
check_sensor -a nct6775-isa-0290 -s fan1 -w 800 -c 500
check_sensor -s temp2 -w 70 -c 85
```

```
SENSOR WARNING - Package id 0 on ISA adapter is 85°C (above max 80°C)|coretemp-isa-0000-temp1=85;80;100;;
```

| Option | Meaning |
|---|---|
| `-s` | The sensor, by name (`temp1`) or label (`Package id 0`) |
| `-a` | The chip (`coretemp-isa-0000`); only needed if several chips have a sensor of that name |
| `-w`, `-c` | Warning and critical level; they replace the limits of the chip |
| `-l` | List the sensors: chip, name, label, value and the limits of the chip |
| `-t` | Give up after this many seconds (default: 10) |
| `-v` | Verbose mode for debugging |
| `-V` | Show the version |
| `-h` | Show the help |

Load the modules for your hardware first; `sensors-detect` finds them. Then
`check_sensor -l` shows what can be checked.

## States

Without `-w` and `-c`, the limits the chip reports decide:

| State | When |
|---|---|
| CRITICAL | above `crit` or below `lcrit`; above `max` or below `min` if the chip has no `crit` or `lcrit` for that side; a critical alarm of the chip |
| WARNING | above `max` or below `min` if the chip also has `crit` or `lcrit`; another alarm of the chip |

With `-w` and/or `-c`, the limits and alarms of the chip are ignored. If the
critical level is greater than the warning level, as for temperatures, values
above them alert. If it is less, as for fan speeds, values below them alert. A
single `-w` or `-c` is an upper limit. A value equal to a level is still OK.

A sensor fault is always CRITICAL. A sensor without a readable value, an
unknown sensor or chip, and an ambiguous sensor name are UNKNOWN.

The value goes into the performance data as `CHIP-SENSOR`, with the levels as
ranges (`300:` for a lower limit). Units other than `%` are left out there, as
Nagios knows only `s`, `%`, `B` and `c`; the text shows the unit.

## lm-sensors versions

lm-sensors 3.6.2 and later print `sensors -J`, a JSON format with the name,
label, value and unit of each sensor. Older versions only have `sensors -j`,
keyed by the label. The plugin uses `-J` and falls back to `-j`, so both work,
with the same names and labels.

## Requirements

bash, coreutils (`timeout`, `mktemp`), grep, sed, awk, jq and lm-sensors.

## Tests

```sh
tests/test_check_sensor.sh
tests/test_completion.sh
```

The tests use a fake `sensors` command with the output of both formats in
`tests/data`, so no sensor hardware is needed.

## License

GPL-2.0-or-later
