include ../../common/sw/common_include.mk

# Primary test name
TEST = host_chan_params

# Build directory
OBJDIR = obj
CFLAGS += -I./$(OBJDIR)
CPPFLAGS += -I./$(OBJDIR)

# Build with BBB library's /dev/fpga_vtp_mapper support?
ifdef FPGA_VTP_MAPPER
	CFLAGS += -DFPGA_VTP_MAPPER=1
	LDFLAGS += -lfpga_vtp_mapper
endif

# Files and folders
SRCS = main.c test_host_chan_params.c $(COMMON_SRCS)
OBJS = $(addprefix $(OBJDIR)/,$(patsubst %.c,%.o,$(SRCS)))

# Targets (build only $(TEST)_ase by default)
all: $(TEST) $(TEST)_ase

# AFU info from JSON file, including AFU UUID
AFU_JSON_INFO = $(OBJDIR)/afu_json_info.h
$(AFU_JSON_INFO): ../hw/rtl/$(TEST).json | objdir
	afu_json_mgr json-info --afu-json=$^ --c-hdr=$@
$(OBJS): $(AFU_JSON_INFO)

$(TEST): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(FPGA_LIBS) -lnuma

$(TEST)_ase: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(ASE_LIBS) -lnuma

$(OBJDIR)/%.o: %.c | objdir
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(TEST) $(TEST)_ase $(OBJDIR)

objdir:
	@mkdir -p $(OBJDIR)

# Debugging. Print Makefile variables with "make print-<VARIABLE NAME>"
print-%:
	@echo $* = $($*)

.PHONY: all clean
