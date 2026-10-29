# keel-postgresql: PostgreSQL, the Webmin module for it, and nothing else.
# Compatible with TurnKey Linux appliances: this is the database half of
# turnkeylinux-apps/postgresql, built as a layer on core so that LAPP and
# any other appliance that needs PostgreSQL is built on it instead of
# installing its own.
#
#     bt-layer postgresql --parent core
#
# What it deliberately leaves out, and why, is in README.rst: Adminer needs
# a web server, and which web server differs by context (lighttpd upstream,
# Apache in LAPP), so it arrives with the web stack, not with the database.

include $(FAB_PATH)/common/mk/turnkey/pgsql.mk

# After pgsql.mk, so a file of this overlay wins over the shared one.
COMMON_OVERLAYS += $(CURDIR)/overlay

# Webmin comes from core and answers on 12321; plan/main adds the database
# module for it. Nothing here serves a web page, so 80 and 443 stay shut:
# 5432 is the database, 12321 the panel, 12320 the web shell core carries.
WEBMIN_FW_TCP_INCOMING = 22 5432 12320 12321

include $(FAB_PATH)/common/mk/turnkey.mk

# The project's own packages (inithooks, confconsole, keel) come from the
# Keel archive, archive.keellinux.org, like every other Keel package: the
# parent layer carries its source and the 990 pin (common's
# overlays/turnkey.d/keel-apt, Keel-Linux/common#30), and a build with
# KEEL_APT_TRACK=testing reads trixie-testing as well (common#32). There is
# no build time archive any more. The build host's staging distribution held
# versions far older than the archive's, and pinned at 1001 it would have
# downgraded the layer to them.
#
# conf.d/main upgrades the three and then proves, with bin/keel-project-
# packages, that each is installed at apt's candidate and that the candidate
# is the Keel archive's, in the suite of the track. The check runs inside the
# tree while its apt lists are still there, so it is copied in before the
# conf scripts run and conf.d/main removes it again.
KEEL_BUILD_TOOLS ?= /usr/local/lib/keel-build
define _keel_root.patched/pre

	install -D -m 755 $(CURDIR)/bin/keel-project-packages $O/root.patched$(KEEL_BUILD_TOOLS)/keel-project-packages;
endef
root.patched/pre += $(_keel_root.patched/pre)
