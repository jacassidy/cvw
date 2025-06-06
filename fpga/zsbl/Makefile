CEXT		:= c
CPPEXT		:= cpp
AEXT		:= s
SEXT		:= S
SRCEXT 		:= \([$(CEXT)$(AEXT)$(SEXT)]\|$(CPPEXT)\)
OBJEXT		:= o
DEPEXT		:= d
SRCDIR		:= .
BUILDDIR	:= OBJ

SOURCES		?= $(shell find $(SRCDIR) -type f -regex ".*\.$(SRCEXT)" | sort)
OBJECTS		:= $(SOURCES:.$(CEXT)=.$(OBJEXT))
OBJECTS		:= $(OBJECTS:.$(AEXT)=.$(OBJEXT))
OBJECTS		:= $(OBJECTS:.$(SEXT)=.$(OBJEXT))
OBJECTS		:= $(OBJECTS:.$(CPPEXT)=.$(OBJEXT))
OBJECTS		:= $(patsubst $(SRCDIR)/%,$(BUILDDIR)/%,$(OBJECTS))

TARGETDIR	:= bin
TARGET		:= $(TARGETDIR)/boot
MEMFILES    := $(TARGETDIR/boot.mem $(TARGETDIR)/data.mem
ROOT		:= ..
LIBRARY_DIRS	:= 
LIBRARY_FILES	:=

MARCH           :=-march=rv64imfdc_zifencei
MABI            :=-mabi=lp64d
LINK_FLAGS      :=$(MARCH) $(MABI) -nostartfiles -L $(RISCV)/riscv64-unknown-elf/lib
LINKER		:=linker1000.x

# FGPA parameters
SYSTEMCLOCK   ?= 20000000
MAXSDCCLOCK   ?=  5000000
EXT_MEM_BASE  ?= 0x80000000
EXT_MEM_RANGE ?= 0x10000000


AFLAGS =$(MARCH) $(MABI) -W
# Override directive allows us to prepend other options on the command line
# e.g. $ make CFLAGS=-g
override CFLAGS +=$(MARCH) $(MABI) -mcmodel=medany -O2 -g  -DSYSTEMCLOCK=${SYSTEMCLOCK} -DMAXSDCCLOCK=${MAXSDCCLOCK} -DEXT_MEM_BASE=${EXT_MEM_BASE} -DEXT_MEM_RANGE=${EXT_MEM_RANGE}
AS=riscv64-unknown-elf-as
CC=riscv64-unknown-elf-gcc
AR=riscv64-unknown-elf-ar


#Default Make
all: directories $(TARGET).memfile

#Remake
remake: clean all

#Make the Directories
directories:
	@mkdir -p $(TARGETDIR)
	@mkdir -p $(BUILDDIR)

clean:
	rm -rf $(BUILDDIR) $(TARGETDIR) *.memfile *.objdump boot.mem data.mem


#Needed for building additional library projects
ifdef LIBRARY_DIRS
LIBS+=${LIBRARY_DIRS:%=-L%}  ${LIBRARY_FILES:%=-l%}
INC+=${LIBRARY_DIRS:%=-I%}

${LIBRARY_DIRS}: 
	$(MAKE) -C $@ -j 1

.PHONY: $(LIBRARY_DIRS) $(TARGET)
endif


#Pull in dependency info for *existing* .o files
-include $(OBJECTS:.$(OBJEXT)=.$(DEPEXT))

#Link
$(TARGET): $(OBJECTS) $(LIBRARY_DIRS)
	$(CC) $(LINK_FLAGS) -g -o $(TARGET) $(OBJECTS) ${LIBS} -T ${LINKER}


#Compile
$(BUILDDIR)/%.$(OBJEXT): $(SRCDIR)/%.$(CEXT)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INC) -c -o $@ $< > $(BUILDDIR)/$*.list
	@$(CC) $(CFLAGS) $(INC) -MM $(SRCDIR)/$*.$(CEXT) > $(BUILDDIR)/$*.$(DEPEXT)
	@cp -f $(BUILDDIR)/$*.$(DEPEXT) $(BUILDDIR)/$*.$(DEPEXT).tmp
	@sed -e 's|.*:|$(BUILDDIR)/$*.$(OBJEXT):|' < $(BUILDDIR)/$*.$(DEPEXT).tmp > $(BUILDDIR)/$*.$(DEPEXT)
	@sed -e 's/.*://' -e 's/\\$$//' < $(BUILDDIR)/$*.$(DEPEXT).tmp | fmt -1 | sed -e 's/^ *//' -e 's/$$/:/' >> $(BUILDDIR)/$*.$(DEPEXT)
	@rm -f $(BUILDDIR)/$*.$(DEPEXT).tmp

# gcc won't output dependencies for assembly files for some reason
# most asm files don't have dependencies so the echo will work for now.
$(BUILDDIR)/%.$(OBJEXT): $(SRCDIR)/%.$(AEXT)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $< > $(BUILDDIR)/$*.list
	@echo $@: $< > $(BUILDDIR)/$*.$(DEPEXT)

$(BUILDDIR)/%.$(OBJEXT): $(SRCDIR)/%.$(SEXT)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INC) -c -o $@ $< > $(BUILDDIR)/$*.list
	@echo $@: $< > $(BUILDDIR)/$*.$(DEPEXT)

# C++
$(BUILDDIR)/%.$(OBJEXT): $(SRCDIR)/%.$(CPPEXT)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INC) -c -o $@ $< > $(BUILDDIR)/$*.list
	@$(CC) $(CFLAGS) $(INC) -MM $(SRCDIR)/$*.$(CPPEXT) > $(BUILDDIR)/$*.$(DEPEXT)
	@cp -f $(BUILDDIR)/$*.$(DEPEXT) $(BUILDDIR)/$*.$(DEPEXT).tmp
	@sed -e 's|.*:|$(BUILDDIR)/$*.$(OBJEXT):|' < $(BUILDDIR)/$*.$(DEPEXT).tmp > $(BUILDDIR)/$*.$(DEPEXT)
	@sed -e 's/.*://' -e 's/\\$$//' < $(BUILDDIR)/$*.$(DEPEXT).tmp | fmt -1 | sed -e 's/^ *//' -e 's/$$/:/' >> $(BUILDDIR)/$*.$(DEPEXT)
	@rm -f $(BUILDDIR)/$*.$(DEPEXT).tmp

# convert to hex
$(TARGET).memfile: $(TARGET)
	@echo 'Making object dump file.'
	riscv64-unknown-elf-objdump -DS $< > $<.objdump
	@echo 'Making memory file'
	riscv64-unknown-elf-elf2hex --bit-width 64 --input $^ --output $@
	extractFunctionRadix.sh $<.objdump
	@echo 'Splitting memfile.'
	./splitfile.sh $@
	mv boot.mem ../src/boot.mem
	mv data.mem ../src/data.mem
