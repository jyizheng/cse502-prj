.PHONY: run clean submit

RUNELF=$(PWD)/prog1

TRACE=--trace

LIBPATH=/home/stufs1/vagrawal/cse502-tools/lib
INCPATH=/home/stufs1/vagrawal/cse502-tools/include
INCPATH_N=/home/stufs1/vagrawal/cse502-tools/include/ncurses

VFILES=$(wildcard *.sv)
CFILES=$(wildcard *.cpp)

obj_dir/Vtop: obj_dir/Vtop.mk
	$(MAKE) -j2 -C obj_dir/ -f Vtop.mk CXX="ccache g++"

obj_dir/Vtop.mk: $(VFILES) $(CFILES)
	verilator -Wall -Wno-LITENDIAN -O3 $(TRACE) --no-skip-identical --cc top.sv --exe $(CFILES) ../dramsim2/libdramsim.so -CFLAGS -I$(INCPATH) -I$(INCPATH_N) -LDFLAGS -Wl,-rpath=../dramsim2/ -LDFLAGS -L$(LIBPATH) -LDFLAGS -lncurses

run: obj_dir/Vtop
	cd obj_dir/ && ./Vtop $(RUNELF)

clean:
	rm -rf obj_dir/

SUBMITTO:=~mferdman/submit/
submit: clean
	tar -czvf $(USER).tgz --exclude=.*.sw? --exclude=$(USER).tgz* --exclude=*~ --exclude=.git .
	@gpg --quiet --import submit-pubkey.txt
	gpg --yes --encrypt --recipient 'submit' $(USER).tgz
	rm -fv $(SUBMITTO)$(USER)=*.tgz.gpg
	cp -v $(USER).tgz.gpg $(SUBMITTO)$(USER)=`date +%F=%T`.tgz.gpg
