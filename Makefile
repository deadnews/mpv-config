.PHONY: all clean test default dotbot install check pc

default: check

check: pc
pc:
	prek run -a

update:
	prek auto-update --freeze
	pinact run --update

dotbot:
	dotbot -c install.conf.yaml
