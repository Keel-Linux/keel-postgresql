#!/usr/bin/env bats
# The services screen of confconsole (overlay/etc/confconsole/services.txt):
# each line names a service the image has. On BR1, 2026-11-06, the screen
# named a web shell on port 12320, and nothing listened there: Keel Core
# has no shellinabox (TurnKey removed it in 18.0, keel-core's changelog).

bats_require_minimum_version 1.5.0

SERVICES=overlay/etc/confconsole/services.txt

@test "services: Webmin, SSH and PostgreSQL, for both address families" {
    [ "$(grep -c '^Webmin: ' "$SERVICES")" -eq 2 ]
    [ "$(grep -c '^SSH/SFTP: ' "$SERVICES")" -eq 2 ]
    [ "$(grep -c '^PostgreSQL: ' "$SERVICES")" -eq 2 ]
}

@test "services: no web shell, which the image does not have" {
    run ! grep -qi 'web shell' "$SERVICES"
    run ! grep -q ':12320' "$SERVICES"
}
