include ../../common/sw/common_include.mk

# Primary test name
TEST = host_chan_params

# Build directory
OBJDIR = obj
CFLAGS += -I./$(OBJDIR)
CPPFLAGS += -I./$(OBJDIR)

# Build with BBB library's /dev/fpga_near_mem_map support?
ifdef FPGA_NEAR_MEM_MAP
	CFLAGS += -DFPGA_NEAR_MEM_MAP=1
	LDFLAGS += -lfpga_near_mem_map
endif

# Files and folders
SRCS = main.c test_host_chan_params.c $(COMMON_SRCS)
OBJS = $(addprefix $(OBJDIR)/,$(patsubst %.c,%.o,$(SRCS)))

all: $(TEST)

# AFU info from JSON file, including AFU UUID
AFU_JSON_INFO = $(OBJDIR)/afu_json_info.h
$(AFU_JSON_INFO): ../hw/rtl/$(TEST).json | objdir
	afu_json_mgr json-info --afu-json=$^ --c-hdr=$@
$(OBJS): $(AFU_JSON_INFO)

$(TEST): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(FPGA_LIBS) -lnuma

$(OBJDIR)/%.o: %.c | objdir
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(TEST) $(OBJDIR)

objdir:
	@mkdir -p $(OBJDIR)

# Debugging. Print Makefile variables with "make print-<VARIABLE NAME>"
print-%:
	@echo $* = $($*)

.PHONY: all clean
