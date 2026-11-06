#!/usr/bin/env bats
# The appliance manifest the overlay ships: present, named for the file,
# honest about Core as its base. The full schema check is keel's own
# (keel.manifest resolves it on the machine); these checks keep the file
# itself from drifting in this repository, with no dependency beyond grep.
# Found by the 2026-10-13 BR1+BR2 pair test (evidence/2026-10-13-step12-pair-br1-br2.md):
# the image carried only core.yaml, so a spec could not name the appliance
# and the pair flow was unreachable.

bats_require_minimum_version 1.5.0

MANIFEST=overlay/usr/share/keel/appliances/postgresql.yaml

@test "manifest: the overlay ships it" {
    [[ -f $MANIFEST ]]
}

@test "manifest: the name matches the file, the base is core" {
    grep -qx "name: postgresql" "$MANIFEST"
    grep -qx "base: core" "$MANIFEST"
    grep -qx "manifest_version: 1" "$MANIFEST"
}

@test "manifest: it declares the mesh port and a check on it" {
    grep -q "port: 5432" "$MANIFEST"
    grep -q "protocol: pgsql" "$MANIFEST"
}

@test "manifest: it declares the shared database secret" {
    grep -q "name: db_password" "$MANIFEST"
    grep -q "shared: true" "$MANIFEST"
}

@test "manifest: no tabs, no CRLF" {
    run ! grep -q $'\t' "$MANIFEST"
    run ! grep -q $'\r' "$MANIFEST"
}

# keel_as_root ARGS...: keel from KEEL_SRC as root: keel refuses a hook
# file that root does not own, and the scratch root is the test's own, so a
# test that is not root runs it in a user namespace where it is root
keel_as_root() {
    local wrap=()
    [ "$(id -u)" = 0 ] || wrap=(unshare -r)
    "${wrap[@]}" env PYTHONPATH="$KEEL_SRC" python3 -m keel "$@"
}

@test "manifest: keel resolves it along core (KEEL_SRC and KEEL_MANIFEST_SOURCES)" {
    [ -n "${KEEL_SRC:-}" ] || skip "KEEL_SRC is not set"
    run tests/lib/manifest-root.sh "$BATS_TEST_TMPDIR/root" "$MANIFEST"
    [ "$status" -eq 0 ]
    run keel_as_root manifest validate --root "$BATS_TEST_TMPDIR/root" postgresql
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "manifest: the example spec and the boot test's spec hold against it, with no warning" {
    # keel 0.23.83 takes a spec that names no appliance with no check of
    # the manifests, and the example then named an option no manifest
    # declares: a first boot that named postgresql refused it (BR1 and
    # BR2, 2026-11-06)
    [ -n "${KEEL_SRC:-}" ] || skip "KEEL_SRC is not set"
    run tests/lib/manifest-root.sh "$BATS_TEST_TMPDIR/root" "$MANIFEST"
    [ "$status" -eq 0 ]
    for spec in keel/instance.example.yaml tests/instance.yaml; do
        run keel_as_root spec validate --spec "$spec" --no-secret-files --root "$BATS_TEST_TMPDIR/root"
        echo "$spec: $output"
        [ "$status" -eq 0 ]
        [[ "$output" != *Warning* ]]
    done
}

@test "manifest: every spec names the postgresql appliance, its mode and the five overlays of Core" {
    for spec in keel/instance.example.yaml tests/instance.yaml; do
        python3 - "$spec" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d["appliance"]["name"] == "postgresql", "appliance.name"
assert d["installation"]["mode"] == "simple", "installation.mode"
assert sorted(d["overlays"]) == ["crowdsec", "etcd", "installer", "vip", "wireguard"], d["overlays"]
assert "options" not in (d.get("app") or {}), "app.options: the manifest declares none"
assert d["secrets"]["db_password"], "secrets.db_password"
PY
    done
}

@test "manifest: the commissioning contract's instance is the example's shape" {
    python3 - keel/instance.example.yaml tests/commission.yaml <<'PY'
import sys, yaml
example = yaml.safe_load(open(sys.argv[1]))
instance = yaml.safe_load(open(sys.argv[2]))["instance"]
for key in ("version", "network", "tls", "appliance", "installation", "overlays", "hub", "first_login_wizard"):
    assert instance[key] == example[key], key
assert sorted(instance["secrets"]) == sorted(example["secrets"]), "secrets"
assert "instance" not in instance, "the machine keeps the name pct create gave it"
PY
}
