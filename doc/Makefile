DRAWIO ?= drawio

all: alzette.svg

alzette.svg: sparkle.drawio Makefile
	$(DRAWIO) --export --page-index 0 --crop --transparent --format svg --embed-svg-images --output $@ $<
