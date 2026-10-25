#!/bin/sh
# Format, lint and type check the game code. Must end with "CHECK PASSED".
# Usage (from the project root): sh scripts/check.sh

cd "$(dirname "$0")/.." || exit 1

DIRS="ReplicatedStorage ServerScriptService ServerStorage StarterPlayerScripts"
FAILED=0

echo "== 1/4 StyLua (format) =="
stylua $DIRS || FAILED=1

echo "== 2/4 Selene (lint) =="
selene $DIRS || FAILED=1

echo "== 3/4 Rojo (sourcemap for type checking) =="
rojo sourcemap default.project.json --output sourcemap.json || FAILED=1

echo "== 4/4 luau-lsp (type check) =="
if [ ! -f tools/globalTypes.d.luau ]; then
	echo "Missing tools/globalTypes.d.luau. Download it with:"
	echo "  curl -sSfL -o tools/globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
	FAILED=1
else
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json \
		--definitions:@roblox=tools/globalTypes.d.luau $DIRS || FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
	echo "CHECK FAILED"
	exit 1
fi
echo "CHECK PASSED"
