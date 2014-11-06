all:
	coffee -o bin -c ./chinook.coffee
	cp bin/chinook.js bin/chinook.js.tmp
	echo "#!/usr/bin/env node" > bin/chinook.js.tmp
	cat bin/chinook.js >> bin/chinook.js.tmp
	mv bin/chinook.js.tmp bin/chinook.js

