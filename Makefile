SHELL = /bin/sh
########################################################################################
# Makefile for the installation of DAMASK
########################################################################################
.PHONY : spectral
spectral:
	@$(MAKE) clean -C code >/dev/null
	$(MAKE) -C code

.PHONY : marc
marc:
	@./installation/mods_Marc/apply_DAMASK_modifcation.py ${MAKEFLAGS}

.PHONY : processing
processing:
	@$(MAKE) tidy -C code >/dev/null
	@./installation/compile_CoreModule.py ${MAKEFLAGS}

.PHONY : tidy
tidy: 
	@$(MAKE) tidy -C code >/dev/null

.PHONY : clean
clean: 
	@$(MAKE) clean -C code >/dev/null

.PHONY : install
install:
	@./installation/symlink_Code.py ${MAKEFLAGS}
	@./installation/symlink_Processing.py ${MAKEFLAGS}

