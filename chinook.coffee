util = require 'util'
docker = new require('dockerode')({socketPath: '/var/run/docker.sock'})
_ = require 'underscore'
argv = require('minimist')(process.argv)
async = require 'async'

# Specify the Redis server to connect to with --redis or -r
redis_address = (argv.redis || argv.r || 'localhost:6379').split(':')
redis_host = redis_address[0]
redis_port = redis_address[1]
redis = null
connectToRedis = (cb) ->
    redis = require('redis').createClient(redis_port, redis_host)
    redis.on 'ready', -> cb()
    redis.on 'error', ->
        console.log "[ERROR] Could not connect to Redis at #{ redis_address.join(':') }"
        process.exit()

# Helpers
# ------------------------------------------------------------------------------

getFirstPort = (net) -> _.keys(net.Ports)[0].split('/')[0]
makeAddress = (net) -> 'http://' + net.IPAddress + ':' + getFirstPort net

hostname_key_prefix = 'frontend:'
hostnameKey = (hostname) -> hostname_key_prefix + hostname

# Core methods
# ------------------------------------------------------------------------------

# Check that the hostname has an address list set up, create one if not
ensureHostname = (hostname, cb) ->
    redis.llen hostnameKey(hostname), (err, l) ->
        if l < 2
            redis.rpush hostnameKey(hostname), cb
        else
            cb()

# Add an address to a hostname
addAddress = (hostname, address, cb) ->
    # Remove in case it already exists
    # TODO: Make a set-based backend for hipache
    removeAddress hostname, address, ->
        redis.rpush hostnameKey(hostname), address, cb

# Remove an address from a hostname
removeAddress = (hostname, address, cb) ->
    redis.lrem hostnameKey(hostname), 0, address, cb

# Print out the addresses associated with a hostname
printAddresses = (hostname, cb) ->
    _printAddresses hostname, (err, output) ->
        console.log output
        cb()

# Build the string to print addresses
_printAddresses = (hostname, cb) ->
    redis.lrange hostnameKey(hostname), 1, -1, (err, addresses) ->
        output = ''
        output += 'HOSTNAME: ' + hostname
        output += '\n    ----> ' + address for address in addresses
        cb null, output

# Print out all known hostnames and associated addresses
printAllAddresses = (cb) ->
    redis.keys hostnameKey('*'), (err, hostname_keys) ->
        async.mapSeries hostname_keys, (hk, _cb) ->
            h = hk.replace(RegExp('^' + hostname_key_prefix), '')
            _printAddresses h, _cb
        , (err, outputs) ->
            console.log outputs.join '\n\n'
            cb()

# Commands
# ------------------------------------------------------------------------------

Chinook = {}

# TODO: chinook launch {image_id} {hostname}
# chinook attach {container_id} {hostname}
# chinook detach {container_id} {hostname}
# chinook replace {old_container_id} {new_container_id} {hostname}

# Launch a new image and attach the resulting container to a hostname
# ------------------------------------------------------------------------------

# Attach a running container to a hostname
# ------------------------------------------------------------------------------

Chinook.attachContainer = (container_id, hostname, cb) ->

    docker.getContainer(container_id).inspect (err, container) ->
        console.log err if err

        container_address = makeAddress container.NetworkSettings
        console.log '  ATTACH: [' + container_id + '] = ' + container_address

        ensureHostname hostname, ->
            addAddress hostname, container_address, cb

# Detach a running container from a hostname
# ------------------------------------------------------------------------------

Chinook.detachContainer = (container_id, hostname, cb) ->

    docker.getContainer(container_id).inspect (err, container) ->
        console.log err if err

        container_address = makeAddress container.NetworkSettings
        console.log '  DETACH: [' + container_id + '] = ' + container_address

        ensureHostname hostname, ->
            removeAddress hostname, container_address, cb

# Replace a running container with a new running container
# ------------------------------------------------------------------------------

Chinook.replaceContainer = (old_container_id, new_container_id, hostname, cb) ->

    docker.getContainer(old_container_id).inspect (err, old_container) ->
        console.log err if err
        old_container_address = makeAddress old_container.NetworkSettings
        console.log '  DETACH: [' + old_container_id + '] = ' + old_container_address

        docker.getContainer(new_container_id).inspect (err, new_container) ->
            console.log err if err
            new_container_address = makeAddress new_container.NetworkSettings
            console.log '  ATTACH: [' + new_container_id + '] = ' + new_container_address

            ensureHostname hostname, ->
                removeAddress hostname, old_container_address, ->
                    addAddress hostname, new_container_address, cb



if require.main != module

    # require() mode: Export the core commands
    # ------------------------------------------------------------------------------

    exports = Chinook
    console.log 'TODO: Attach connected redis client to exported chinook context'

else

    # CLI mode: Interpret command line arguments and run specified methods
    # ------------------------------------------------------------------------------
    # TODO: Show help

    command = argv._[2]

    if command == 'launch'
        console.error "NOT IMPLEMENTED"
        process.exit()

    else if command == 'replace'
        _old_id = argv._[3]
        _new_id = argv._[4]
        _hostname = argv._[5] || argv.hostname || argv.h

        console.log "Replacing container #{ _old_id } with #{ _new_id } for #{ _hostname }..."

        connectToRedis ->
            Chinook.replaceContainer _old_id, _new_id, _hostname, ->
                printAddresses _hostname, ->
                    process.exit()

    else if command == 'attach'
        _id = argv._[3]
        _hostname = argv._[4] || argv.hostname || argv.hostname || argv.h

        console.log "Attaching container #{ _id } to #{ _hostname }..."

        connectToRedis ->
            Chinook.attachContainer _id, _hostname, ->
                printAddresses _hostname, ->
                    process.exit()

    else if command == 'detach'
        _id = argv._[3]
        _hostname = argv._[4] || argv.hostname || argv.h

        console.log "Detaching container #{ _id } from #{ _hostname }..."

        connectToRedis ->
            Chinook.detachContainer _id, _hostname, ->
                printAddresses _hostname, ->
                    process.exit()

    else
        connectToRedis ->
            printAllAddresses ->
                process.exit()

