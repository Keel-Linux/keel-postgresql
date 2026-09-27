# Coverage

Standard: decisions 0003 (90 percent per repository, 95 for code the
project writes) and 0004 (bats plus kcov for shell; a build and a boot on
LXC as the acceptance test of a recipe, docs/org-plan.md section 1).

## Measured 2026-09-27

| File | Test | Lines | Note |
| --- | --- | --- | --- |
| overlay/usr/lib/inithooks/lib/postgresql.sh | tests/postgresql.bats (11 tests) | 100 percent (41/41) under kcov | every function and every branch |
| overlay/usr/lib/inithooks/firstboot.d/36pgsqlverify | tests/hook.bats (10 tests) | 100 percent (15/15) under kcov | every path, including the two failures that matter |
| tests/lib/boot-test-lib.sh | tests/boot-test.bats (37 tests) | 100 percent (141/141) under kcov | argument parsing, address discovery, deadlines, the database, module, Webmin and diff verdicts |
| conf.d/main | the build | integration only | build time script, 0004 pragmatic limits |
| tests/boot-test.sh | itself | integration only | the thin main of the acceptance test: keel and LXC as root |
| overlay ... firstboot.d/35pgsqlpass | common | not this repository | the hook that sets the password belongs to the `common` fork and is used, not rewritten |

Total over the three measured shell files: **100 percent (197/197)**,
58 bats tests. `tests/coverage.sh` fails below `COVERAGE_THRESHOLD`, which
the workflow sets to 100, the measured number. It is only ever raised
(decision 0006).

    $ COVERAGE_THRESHOLD=100 tests/coverage.sh
    kcov line coverage (threshold 100 percent):
     100.00  41/41  postgresql.sh
     100.00  15/15  36pgsqlverify
     100.00  141/141  boot-test-lib.sh

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

State on 2026-09-27: **the layer is not published yet, so the job skips
with a notice and passes.** It becomes a required status on `main` the day
the first `postgresql` layer reaches the mirror.

## Plan

- Publish the layer, then require `appliance / build-and-boot` on `main`.
- Measure `conf.d/main`. A build time script that runs inside a chroot as
  root is the case decision 0003 splits, and what is left here after the
  logic moved to `lib/postgresql.sh` is SQL, three assertions about the
  cluster configuration and the apt calls.
- `35pgsqlpass` and `bin/pgsqlconf.py` belong to the `common` fork and are
  measured there; `common`'s own COVERAGE.md carries that plan.
