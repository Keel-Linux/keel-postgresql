#!/usr/bin/env bats
# The ports that the Webmin firewall of the recipe opens (WEBMIN_FW_TCP_
# INCOMING of the Makefile; common's conf/turnkey.d/webmin-fw writes an
# accept rule for each of them). keel makes its nftables table from the
# manifests and opens a port of "expose: mesh" only on the WireGuard
# interface (keel/manifest/firewall.py, decision 0041, item 6). 5432 is a
# mesh port in the manifest, so it is not in this list. Keel Core has no
# web shell on 12320 (TurnKey removed shellinabox in 18.0), so 12320 is
# not in it either. tests/services.bats holds the services screen to what
# the image has. The same tests are in keel-mariadb (#40) and keel-redis.

bats_require_minimum_version 1.5.0

MAKEFILE="$BATS_TEST_DIRNAME/../Makefile"

# the ports of the one WEBMIN_FW_TCP_INCOMING line, one a line
incoming() {
    [ "$(grep -c '^WEBMIN_FW_TCP_INCOMING *=' "$MAKEFILE")" -eq 1 ]
    sed -n 's/^WEBMIN_FW_TCP_INCOMING *= *//p' "$MAKEFILE" | tr -s ' ' '\n'
}

@test "firewall: the uplink list opens SSH and Webmin, and nothing else" {
    run incoming
    [ "$status" -eq 0 ]
    [ "$(sort -n <<< "$output" | tr '\n' ' ')" = "22 12321 " ]
}

@test "firewall: the uplink list does not open 5432, a mesh port" {
    run incoming
    [ "$status" -eq 0 ]
    run ! grep -qx 5432 <<< "$output"
}

@test "firewall: the uplink list does not open 12320, no web shell is there" {
    run incoming
    [ "$status" -eq 0 ]
    run ! grep -qx 12320 <<< "$output"
}
