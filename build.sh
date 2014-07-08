#!/bin/sh

# Compile .coffee to .js
coffee -o bin -c ./chinook.coffee

# Ugly hack to prepend shebang line
cp bin/chinook.js bin/chinook.js.tmp
echo "#!/usr/bin/env node" > bin/chinook.js.tmp
cat bin/chinook.js >> bin/chinook.js.tmp
mv bin/chinook.js.tmp bin/chinook.js

