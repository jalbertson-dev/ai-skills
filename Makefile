# Discover all skills by finding directories containing a SKILL.md
SKILLS := $(patsubst %/SKILL.md,%,$(wildcard */SKILL.md))

.PHONY: all clean $(SKILLS)

## Build all skills
all: $(SKILLS)

## Build a single skill: make <skill-name>
## Output is <skill-name>/<skill-name>.skill (committed to the repo for distribution)
$(SKILLS):
	@echo "Building $@.skill..."
	@cd $@ && zip -j $@.skill SKILL.md
	@echo "  → $@/$@.skill"

## Remove all built .skill artifacts
clean:
	@for s in $(SKILLS); do \
		rm -f $$s/$$s.skill && echo "  removed $$s/$$s.skill"; \
	done

## List available skills
list:
	@echo "Available skills:"
	@for s in $(SKILLS); do echo "  $$s"; done
