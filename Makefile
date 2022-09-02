SHELL:=/usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

HS_BIN=/Applications/Hammerspoon.app//Contents/Frameworks/hs/hs

all: Source/MetarMenu.spoon/docs.json Spoon/MetarMenu.spoon.zip

Source/MetarMenu.spoon/docs.json: Source/MetarMenu.spoon/init.lua
	cd Source/MetarMenu.spoon; ${HS_BIN} -c "hs.doc.builder.genJSON(\"`pwd`\")" | grep -v "^--" > docs.json

Spoon/MetarMenu.spoon.zip: Source/MetarMenu.spoon/docs.json Source/MetarMenu.spoon/init.lua
	cd Source; zip -r ../Spoon/MetarMenu.spoon.zip MetarMenu.spoon;
