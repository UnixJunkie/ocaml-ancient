# Mark objects as 'ancient' so they are taken out of the OCaml heap.

include Makefile.config

CC	:= gcc
CFLAGS	:= -g -fPIC -Wall -Werror \
	-DOCAML_VERSION_MAJOR=$(OCAML_VERSION_MAJOR) \
	-DOCAML_VERSION_MINOR=$(OCAML_VERSION_MINOR) \
	-I$(shell ocamlc -where)

OCAMLCFLAGS	:= -g
OCAMLCPACKAGES	:= -package unix
OCAMLCLIBS	:= -linkpkg

OCAMLOPTFLAGS	:=
OCAMLOPTPACKAGES := $(OCAMLCPACKAGES)
OCAMLOPTLIBS	:= -linkpkg

OCAMLDOCFLAGS := -html -stars -sort $(OCAMLCPACKAGES)

TARGETS		:= mmalloc ancient.cma ancient.cmxa META \
		   test_ancient_dict_write.opt \
		   test_ancient_dict_verify.opt \
		   test_ancient_dict_read.opt

all:	$(TARGETS)

ancient.cma: ancient.cmo ancient_c.o
	ocamlmklib -o ancient -Lmmalloc -lmmalloc $^

ancient.cmxa: ancient.cmx ancient_c.o
	ocamlmklib -o ancient -Lmmalloc -lmmalloc $^

test_ancient_dict_write.opt: ancient.cmxa test_ancient_dict_write.cmx
	LIBRARY_PATH=.:$$LIBRARY_PATH \
	ocamlfind ocamlopt $(OCAMLOPTFLAGS) $(OCAMLOPTPACKAGES) $(OCAMLOPTLIBS) -o $@ $^

test_ancient_dict_verify.opt: ancient.cmxa test_ancient_dict_verify.cmx
	LIBRARY_PATH=.:$$LIBRARY_PATH \
	ocamlfind ocamlopt $(OCAMLOPTFLAGS) $(OCAMLOPTPACKAGES) $(OCAMLOPTLIBS) -o $@ $^

test_ancient_dict_read.opt: ancient.cmxa test_ancient_dict_read.cmx
	LIBRARY_PATH=.:$$LIBRARY_PATH \
	ocamlfind ocamlopt $(OCAMLOPTFLAGS) $(OCAMLOPTPACKAGES) $(OCAMLOPTLIBS) -o $@ $^

# Build the mmalloc library.

mmalloc:
	$(MAKE) -C mmalloc

# Common rules for building OCaml objects.

.mli.cmi:
	ocamlfind ocamlc $(OCAMLCFLAGS) $(OCAMLCINCS) $(OCAMLCPACKAGES) -c $<
.ml.cmo:
	ocamlfind ocamlc $(OCAMLCFLAGS) $(OCAMLCINCS) $(OCAMLCPACKAGES) -c $<
.ml.cmx:
	ocamlfind ocamlopt $(OCAMLOPTFLAGS) $(OCAMLOPTINCS) $(OCAMLOPTPACKAGES) -c $<

# Findlib META file.

META:	META.in Makefile.config
	sed  -e 's/@PACKAGE@/$(PACKAGE)/' \
	     -e 's/@VERSION@/$(VERSION)/' \
	     < $< > $@

# Clean.

clean:
	rm -f *.cmi *.cmo *.cmx *.cma *.cmxa *.o *.a *.so *~ core META \
	   *.opt .depend
	$(MAKE) -C mmalloc clean

# Dependencies.

depend: .depend

.depend: $(wildcard *.mli) $(wildcard *.ml)
	rm -f .depend
	ocamldep $^ > $@

ifeq ($(wildcard .depend),.depend)
include .depend
endif

# Install.

install:
	rm -rf $(DESTDIR)$(OCAMLLIBDIR)/ancient
	install -c -m 0755 -d $(DESTDIR)$(OCAMLLIBDIR)/ancient
	install -c -m 0644 *.cmi *.mli *.cma *.cmxa *.a META \
	  $(DESTDIR)$(OCAMLLIBDIR)/ancient

# Distribution.

dist:
	$(MAKE) check-manifest
	rm -rf $(PACKAGE)-$(VERSION)
	mkdir $(PACKAGE)-$(VERSION)
	tar -cf - -T MANIFEST | tar -C $(PACKAGE)-$(VERSION) -xf -
	tar zcf $(PACKAGE)-$(VERSION).tar.gz $(PACKAGE)-$(VERSION)
	rm -rf $(PACKAGE)-$(VERSION)
	ls -l $(PACKAGE)-$(VERSION).tar.gz

check-manifest:
	git ls-files | sort > .check-manifest; \
	sort MANIFEST > .orig-manifest; \
	diff -u .orig-manifest .check-manifest; rv=$$?; \
	rm -f .orig-manifest .check-manifest; \
	exit $$rv

# Debian packages.

dpkg:
	@if [ 0 != `cvs -q update | wc -l` ]; then \
	echo Please commit all changes to CVS first.; \
	exit 1; \
	fi
	$(MAKE) dist
	rm -rf /tmp/dbuild
	mkdir /tmp/dbuild
	cp $(PACKAGE)-$(VERSION).tar.gz \
	  /tmp/dbuild/$(PACKAGE)_$(VERSION).orig.tar.gz
	export CVSROOT=`cat CVS/Root`; \
	  cd /tmp/dbuild && \
	  cvs export \
	  -d $(PACKAGE)-$(VERSION) \
	  -D now merjis/freeware/ancient
	cd /tmp/dbuild/$(PACKAGE)-$(VERSION) && dpkg-buildpackage -rfakeroot
	rm -rf /tmp/dbuild/$(PACKAGE)-$(VERSION)
	ls -l /tmp/dbuild

# Developer documentation (in html/ subdirectory).

doc:
	rm -rf html
	mkdir html
	-ocamlfind ocamldoc $(OCAMLDOCFLAGS) -d html ancient.ml{i,}

.PHONY:	depend dist check-manifest dpkg doc mmalloc

.SUFFIXES:	.cmo .cmi .cmx .ml .mli
