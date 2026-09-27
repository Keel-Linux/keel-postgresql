# Tests

What a test means for a layer recipe is written in `COVERAGE.md`: the
recipe builds, the result boots in an LXC container, its first boot
completes headless from an instance description, the database accepts the
password that description declared, the panel has the module for it, and
the machine matches the description.

## Layout

- `boot-test.sh`: the boot test. `test-appliance.yml` (reusable workflow of
  `keel-linux/.github`) runs it on the self-hosted LXC runner after pulling
  the layers from `https://mirror.keellinux.org/layers` and checking them
  with `keel verify`. It is the thin main: assemble, mark the tree as a
  container, install the description, the secrets and the conf, start the
  container, wait, connect to the database, check Webmin, `keel diff`. It
  builds nothing, so it needs no fab, deck or buildtasks.
- `lib/boot-test-lib.sh`: the logic (argument parsing, address discovery
  from `lxc-info`, waiting with a deadline, the secret files, the client
  call, the database, module and Webmin verdicts, the diff verdict), as
  functions with no side effects, per decision 0004. Same shape as the one
  in keel-core, keel-nodebb and keel-mariadb.
- `boot-test.bats`: unit tests of that library. `lxc-info` is a stub first
  in `PATH`; the clock and `sleep` are functions. No root, no network, no
  LXC, no database.
- `postgresql.bats`: unit tests of
  `overlay/usr/lib/inithooks/lib/postgresql.sh`, the logic behind the
  first boot hook `36pgsqlverify`.
- `hook.bats`: `36pgsqlverify` itself, run for real against scratch
  directories with every system command stubbed. The hook that sets the
  password, `35pgsqlpass`, belongs to the `common` fork and is tested
  there; this layer uses it rather than rewriting it.
- `coverage.sh`: runs the bats suite under kcov and fails when any measured
  file is below `COVERAGE_THRESHOLD` (default 100).
- `instance.yaml`: the description the test container boots from. It
  declares `secrets.db_password` from a file, which is the point of the
  test.

## Unit tests and coverage

Debian packages `bats` (1.11) and `kcov` (43); no root:

    bats tests/postgresql.bats
    bats tests/hook.bats
    bats tests/boot-test.bats
    COVERAGE_THRESHOLD=100 tests/coverage.sh

`COVERAGE_DIR=coverage tests/coverage.sh` keeps the kcov reports.

## The boot test by hand

Needs root, `keel` on `PATH`, LXC (`lxc-start`, `lxc-info`, `lxc-attach`,
`lxc-stop`), `curl`, and a bridge with IPv6 router advertisements or
DHCPv6.

    tests/boot-test.sh postgresql --layers-dir https://mirror.keellinux.org/layers \
        --bridge lxcbr0

`--layers-dir` is a directory or an http(s) URL, so on the build host it is
`/mnt/builds/layers` and on a runner it is the mirror. The other useful
options are `--bridge`, `--cache-dir`, `--lxc-path`, `--name`, `--timeout`
and `--keep` (leaves the container running; then `lxc-attach -n <name>`).
`tests/boot-test.sh --help` lists them all.

What it does, in order:

1. `keel pull` and `keel assemble` the chain (core, postgresql) into
   `<lxc-path>/<name>/rootfs`.
2. Marks the tree as a container build, which is what `bt_mark_container`
   does and what buildtasks' `patches/container/conf` does for a real
   container image: the marker
   `var/lib/turnkey-info/inithooks.service/lxc` that `keel inspect` reads
   to call the machine a container (`network.managed_by: host`),
   `REDIRECT_OUTPUT=true` in `etc/default/inithooks`, and a drop-in giving
   `inithooks.service` `StandardOutput=journal`. Without the last two the
   hooks write to `/dev/tty1`, which nobody reads in a container, and the
   first hook that prints more than the terminal buffer holds blocks there
   forever.
3. Writes a random `root_password` and `db_password` under
   `etc/keel/secrets` (mode 0600) and installs `tests/instance.yaml` at
   `etc/keel/instance.yaml` and `etc/inithooks.yaml`.
4. Renders the description into the rootfs `etc/inithooks.conf` with
   `keel spec apply`, from a copy whose secret references point inside the
   rootfs. Without the conf the first boot is not headless: `30rootpass`
   would have nothing declared and no terminal, and `36pgsqlverify`
   would fail naming the field the description has to declare.
5. Writes an LXC config for that rootfs on the bridge and starts the
   container. The config asks for `lxc.apparmor.profile = generated` and
   `lxc.apparmor.allow_nesting = 1`: without them systemd cannot give a
   unit a mount namespace, so `systemd-journald`, `systemd-logind` and
   `tmp.mount` fail with `status=226/NAMESPACE` and the hooks that need
   them fail beside the database.
6. Waits for a global IPv6 address (`lxc-info -i`), then for the first boot
   to finish: `RUN_FIRSTBOOT=false` in the rootfs copy of
   `/etc/default/inithooks`, and then confconsole or an SSH banner.
7. **Connects to the database.** `psql --username=postgres --host=::1
   --port=5432 --no-password --command='SELECT 1'` inside the container,
   with the declared password in `PGPASSWORD`. `--no-password` makes psql
   fail rather than prompt, so a password that did not arrive is an error
   and not a hung test. The password comes from the secret
   file the test wrote in step 3 and from nowhere else, so a row back is
   the proof that the declarative path carried it end to end. A listening
   port would prove nothing: the database listens whatever password it
   ended up with.
8. Checks `webmin-postgresql` is installed and that Webmin answers over IPv6 on
   12321.
9. Runs `keel diff --root <rootfs> --spec tests/instance.yaml`; exit 0 or
   13 (no drift) passes.
