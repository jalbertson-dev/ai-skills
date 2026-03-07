DIST_DIR := dist

# Discover all skills by finding directories containing a SKILL.md
SKILLS := $(patsubst %/SKILL.md,%,$(wildcard */SKILL.md))

.PHONY: all clean $(SKILLS)

## Build all skills
all: $(SKILLS)

## Build a single skill: make <skill-name>
$(SKILLS):
	@mkdir -p $(DIST_DIR)
	@echo "Building $@.skill..."
	@cd $@ && zip -j ../$(DIST_DIR)/$@.skill SKILL.md
	@echo "  → $(DIST_DIR)/$@.skill"

## Remove all built artifacts
clean:
	rm -rf $(DIST_DIR)

## List available skills
list:
	@echo "Available skills:"
	@for s in $(SKILLS); do echo "  $$s"; done
