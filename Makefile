PREFIX ?= /usr
SYSCONFDIR ?= /etc
LOCALSTATEDIR ?= /var
BINDIR = $(DESTDIR)$(PREFIX)/bin
LIBDIR = $(DESTDIR)$(PREFIX)/lib/inhibit-charge
UNITDIR = $(DESTDIR)/lib/systemd/system
STATEDIR = $(DESTDIR)$(LOCALSTATEDIR)/lib/inhibit-charge
DOCDIR = $(DESTDIR)$(PREFIX)/share/doc/inhibit-charge

.PHONY: all install uninstall lint check deb clean

all:
	@echo "Nothing to build. Run 'make install', 'make check' to lint, or 'make deb' to build a .deb."

deb:
	bash scripts/build-deb.sh

install:
	install -d $(BINDIR) $(LIBDIR) $(UNITDIR) $(STATEDIR) $(DOCDIR)
	install -m 0755 bin/inhibit-charge              $(BINDIR)/inhibit-charge
	install -m 0755 lib/inhibit-charge/inhibit-charged $(LIBDIR)/inhibit-charged
	install -m 0644 systemd/inhibit-charged.service $(UNITDIR)/inhibit-charged.service
	install -m 0644 README.md                       $(DOCDIR)/README.md
	install -m 0644 LICENSE                         $(DOCDIR)/LICENSE
	# Seed default state if not present. The postinst (or local installer)
	# is responsible for ownership; here we only create the files so a raw
	# `make install` on a dev machine works.
	[ -e $(STATEDIR)/mode ]   || echo home > $(STATEDIR)/mode
	[ -e $(STATEDIR)/target ] || echo 60   > $(STATEDIR)/target
	chmod 0664 $(STATEDIR)/mode $(STATEDIR)/target

uninstall:
	rm -f $(BINDIR)/inhibit-charge
	rm -f $(LIBDIR)/inhibit-charged
	rmdir --ignore-fail-on-non-empty $(LIBDIR) 2>/dev/null || true
	rm -f $(UNITDIR)/inhibit-charged.service
	rm -f $(DOCDIR)/README.md $(DOCDIR)/LICENSE
	rmdir --ignore-fail-on-non-empty $(DOCDIR) 2>/dev/null || true

lint:
	shellcheck -x bin/inhibit-charge lib/inhibit-charge/inhibit-charged scripts/build-deb.sh debian/postinst debian/postrm

check: lint

clean:
	@true
