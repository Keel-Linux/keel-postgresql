keel-postgresql
===============

PostgreSQL database layer for Keel appliances, built on ``core``.
Compatible with TurnKey Linux appliances, and corresponding to the upstream
appliance `turnkeylinux-apps/postgresql
<https://github.com/turnkeylinux-apps/postgresql>`_ for the database half
of what that appliance is::

    bt-layer postgresql --parent core

It is a layer, not a product: LAPP and any other appliance that needs
PostgreSQL is built on it, so the cluster is created, secured and measured
once. Nothing is stopping it being run on its own; it boots, it listens on
loopback, and Webmin administers it.

What is in it
-------------

======================================  ====================================
``Makefile``                            ``mk/turnkey/pgsql.mk`` of ``common``, this overlay, the firewall ports
``plan/main``                           postgresql, webmin-postgresql, the client, the project packages
``conf.d/main``                         the build time password removed; the checks; the project package upgrade
``overlay/usr/lib/inithooks/``          the verification hook and its library
``keel/instance.example.yaml``          the instance description an operator starts from
``tests/``                              bats for the shell, ``boot-test.sh`` for the machine
======================================  ====================================

``mk/turnkey/pgsql.mk`` brings ``conf/pgsql`` (the UTF-8 cluster, password
encryption, the root superuser) and the ``pgsql`` overlay, which carries
``bin/pgsqlconf.py`` and ``firstboot.d/35pgsqlpass``. Those are used as
they are, not rewritten.

Webmin comes from ``core`` and answers on 12321; this layer adds
``webmin-postgresql``, the module that puts the database in it. Batteries
included is a property of this distribution, so the boot test checks both
the module and the panel.

What it deliberately leaves out
-------------------------------

Upstream's ``postgresql`` appliance also bundles **Adminer**, **lighttpd**,
**php-fpm** and a landing page served by them, and **postgis**. None of
that is here.

Adminer needs a web server, and which web server differs by context:
lighttpd in the upstream appliance, Apache in LAMP and LAPP. Putting it in
the database layer forces a choice that the layers above would have to undo
and make again. So Adminer arrives with the web stack, in LAPP, which is
also where upstream puts it for that product.

**Remote access is left out too, and that one is a change of behaviour.**
Upstream's ``conf.d/main`` sets ``listen_addresses = '*'`` and appends
``host all all 0.0.0.0/0 md5`` to ``pg_hba.conf``, so the appliance accepts
password authentication for every database from anywhere. On an IPv6 first,
publicly routable appliance (brief section 5.3) that is not a default this
project can inherit quietly. This layer listens on
``'::1,127.0.0.1'``, the loopback of both families and nothing else, and
asserts at build time that neither of upstream's two changes is present.
Both addresses are written out rather than left to Debian's default of
``'localhost'``: that default binds the IPv4 loopback alone, because
Debian's ``/etc/hosts`` maps ``::1`` to ``ip6-localhost`` and never to
``localhost``, which is a defect this layer shipped once and its own boot
test caught. An appliance that really has remote clients opens the port, says
who may connect and terminates TLS. That is a decision an appliance makes,
not one a database layer makes for everything built on it.

If the maintainer later wants literal parity with the upstream
``postgresql`` appliance, that is a different artefact: the appliance,
built on this layer, with Adminer and a web server of its own.

The password, and the defect these layers exposed
-------------------------------------------------

An instance description declares the database password once::

    secrets:
      db_password:
        file: /etc/keel/secrets/db_password

That renders to ``DB_PASS``: ``SECRET_VARS`` in ``keel/spec/constants.py``
and the same table in ``libinithooks/declarative.py`` of the inithooks
fork. On this side the vocabulary was already right, because common's
``overlays/pgsql`` ``firstboot.d/35pgsqlpass`` reads ``DB_PASS`` and hands
it to ``bin/pgsqlconf.py``. Two things were wrong anyway.

**The layer shipped a known password.** ``conf/pgsql`` opens with ``set
${PGSQL_PASS:=postgres}``, so a build that names no ``PGSQL_PASS`` gives
the superuser of the database the password ``postgres``. For an appliance
that is a bad default; for a published layer it is worse, because the layer
is fetched by name and reused, so every appliance built on it would ship
the same known superuser password, and one whose first boot hook failed
would keep it. ``conf.d/main`` removes the password instead of choosing
another one: a build time value would be identical on every appliance built
from the layer, and a random one would make the layer irreproducible (brief
section 5.4). With no password the role authenticates nothing over TCP
until the first boot sets it, so the failure mode is a database nobody can
reach rather than a database everybody can.

**Nothing said whether the password arrived.** ``35pgsqlpass`` reports on
setting it, not on whether the database will accept it, and ``keel diff``
never compares secrets, on either side. On an appliance whose whole purpose
is the database that is the one failure that must not be silent. So this
layer adds ``firstboot.d/36pgsqlverify``, which runs after it, connects as
a client over TCP on ``::1`` with the declared password and says so. With
nothing declared it fails naming the field to declare.

``PGSQL_PASS``, which ``mk/turnkey/pgsql.mk`` adds to ``CONF_VARS``, is a
build time variable fab passes to ``conf/pgsql`` inside the chroot. It never
reaches the inithooks conf and no hook reads it there. The same defect on
the MariaDB side, where the hook itself was missing, is written up in
``keel-mariadb``.

Tests
-----

``tests/coverage.sh`` gates the shell this layer writes and
``tests/boot-test.sh`` boots the published layer and proves the declarative
path; see ``tests/README.md`` and ``COVERAGE.md``.
