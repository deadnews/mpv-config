.PHONY: all clean test default dotbot install check pc

default: check

check: pc
pc:
	prek run -a

update:
	prek auto-update --freeze
	pindock run --update

scripts-up:
	wget -O mpv/scripts/slicing.lua https://raw.githubusercontent.com/snylonue/mpv_slicing_copy/master/slicing_copy.lua

dotbot:
	dotbot -c install.conf.yaml
