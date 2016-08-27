TRILL=$(shell which trill)
CLANG=$(shell which clang)
SOURCES=$(wildcard *.tr)
OBJECTS=$(subst .tr,.o,$(SOURCES))
LLFILES=$(subst .tr,.ll,$(SOURCES))
BCFILES=$(subst .tr,.bc,$(SOURCES))
BINARIES=$(basename $(SOURCES))
LLVM_DIR=/usr/local/llvm/bin
OPT=$(LLVM_DIR)/opt
LLC=$(LLVM_DIR)/llc

all: $(BINARIES)

clean:
	rm -f $(OBJECTS)
	rm -f $(BCFILES)
	rm -f $(LLFILES)

purge: clean
	rm -f $(BINARIES)

%.ll : %.tr
	$(TRILL) $< -O2 -emit-llvm > $@
%.o : %.ll
	$(LLC) -filetype obj $<
% : %.o
	$(CLANG) -lobjc -framework Foundation -L/usr/local/lib -ltrillRuntime $< -o $@

