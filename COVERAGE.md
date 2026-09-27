# Coverage

Standard: decisions 0003 (90 percent per repository, 95 for code the
project writes) and 0004 (bats plus kcov for shell; a build and a boot on
LXC as the acceptance test of a recipe, docs/org-plan.md section 1).

## Measured 2026-09-27

| File | Test | Lines | Note |
| --- | --- | --- | --- |
| overlay/usr/lib/inithooks/lib/postgresql.sh | tests/postgresql.bats (11 tests) | 100 percent (41/41) under kcov | every function and every branch |
| overlay/usr/lib/inithooks/firstboot.d/36pgsqlverify | tests/hook.bats (10 tests) | 100 percent (15/15) under kcov | every path, including the two failures that matter |
| tests/lib/boot-test-lib.sh | tests/boot-test.bats (44 tests) | 100 percent (154/154) under kcov | argument parsing, address discovery, deadlines, the container marks, the database, module, Webmin and diff verdicts |
| bin/keel-archive-check | tests/archive-check.bats (27 tests) | 100 percent (54/54) under kcov | the build time check: the archive copy in the build tree is the live archive, the source entry names the keyring through signed-by, nothing says trusted=yes, and the signature on the copied InRelease verifies against the staging key (tracker#7) |
| conf.d/main | the build | integration only | build time script, 0004 pragmatic limits |
| tests/boot-test.sh | itself | integration only | the thin main of the acceptance test: keel and LXC as root |
| overlay ... firstboot.d/35pgsqlpass | common | not this repository | the hook that sets the password belongs to the `common` fork and is used, not rewritten |

Total over the four measured shell files: **100 percent (264/264)**,
92 bats tests. `tests/coverage.sh` fails below `COVERAGE_THRESHOLD`, which
the workflow sets to 100, the measured number. It is only ever raised
(decision 0006).

    $ COVERAGE_THRESHOLD=100 tests/coverage.sh
    kcov line coverage (threshold 100 percent):
     100.00  41/41  postgresql.sh
     100.00  15/15  36pgsqlverify
     100.00  154/154  boot-test-lib.sh
     100.00  54/54  keel-archive-check

## What the hook tests cover

The hook is executed for real against scratch directories, with PATH stubs
for `systemctl`, `pg_isready` and `psql` under a scratch `INITHOOKS_PATH`
whose `lib` is a symlink to the real library, so kcov measures the file the
layer ships. The `psql` stub answers the probe only for the password the
description declared, the way a server does. No test needs root, a
database or a network.

What they are about is the half of the password defect that is this
layer's: the declared password is proved against the database, a password
the database refuses fails the hook, an answer that is not the probe's
fails it, nothing declared fails naming the field and never prompts, a
`PGSQL_PASS` in the conf is not a password and is ignored, `APP_DB_USER`
renames the role and a name that would need quoting is refused before
anything runs, and the cluster is started and waited for on the address the
client will use.

## The appliance gate

`appliance / build-and-boot` runs through the organization's
`test-appliance.yml` on the self-hosted `keel-lxc` runner, which fetches
the published layer from `https://mirror.keellinux.org/layers`, verifies
it, assembles it, boots it in LXC and runs `tests/boot-test.sh`. Nothing is
built there.

### What the gate found once the layer booted (2026-09-27)

The `postgresql` layer was published (104,170,947 bytes, parent `core`
7acf2c53) and the job ran for real. It failed, on two defects at once,
one in the test and one in the layer:

    INFO: [35pgsqlpass] successfully completed
    ERR: [36pgsqlverify] failed - exit code 1
    psql: error: connection to server at "::1", port 5432 failed: Connection refused
    ERR: [15regen-sslcert] failed - exit code 1
    ERR: [95secupdates] failed - exit code 1

Reproduced on the build host from the published chain.

1. **The test.** Under the stock LXC container apparmor profile systemd
   cannot give a unit a mount namespace, so `systemd-journald`,
   `systemd-logind`, `systemd-sysusers`, `systemd-sysctl` and
   `tmp.mount` failed with `status=226/NAMESPACE`, which is why
   `15regen-sslcert` and `95secupdates` failed and why the container had
   no journal. `bt_lxc_config` now writes
   `lxc.apparmor.profile = generated` and
   `lxc.apparmor.allow_nesting = 1`, and `bt_mark_container` does what
   buildtasks' container patch does, both ported from keel-nodebb.
2. **The layer**, and the hook was right to report it. The cluster was
   online and listening on `127.0.0.1:5432` alone: Debian's `/etc/hosts`
   maps `::1` to `ip6-localhost` and never to `localhost`, so
   `listen_addresses = 'localhost'` binds the IPv4 loopback only. Fixed
   by naming both addresses, in the changelog as version 2.

Measured on the build host with both in place: every hook from
`01ipconfig` to `98finalize` completes, the only failed unit is
`inithooks-restart-getty1.service`, which needs a tty no container has,
and

    $ psql --username=postgres --host=::1 --port=5432 --no-password \
        --command='SELECT 1, current_user, inet_server_addr()'
    1|postgres|::1

with the declared password in `PGPASSWORD`, while the wrong password
gives `FATAL:  password authentication failed for user "postgres"`.

State on 2026-09-27: green once this and the layer rebuild land. It
becomes a required status on `main` then.

## Plan

- Publish the layer, then require `appliance / build-and-boot` on `main`.
- Measure `conf.d/main`. A build time script that runs inside a chroot as
  root is the case decision 0003 splits, and what is left here after the
  logic moved to `lib/postgresql.sh` is SQL, three assertions about the
  cluster configuration and the apt calls.
- `35pgsqlpass` and `bin/pgsqlconf.py` belong to the `common` fork and are
  measured there; `common`'s own COVERAGE.md carries that plan.
