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

%.o: %.tr
	$(TRILL) $< -emit-timing > $@
% : %.o
	$(CLANG) -lc++ -L/usr/local/lib -ltrillRuntime $< -o $@

