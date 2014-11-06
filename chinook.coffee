util = require 'util'
docker = new require('dockerode')({socketPath: '/var/run/docker.sock'})
_ = require 'underscore'
argv = require('minimist')(process.argv)
async = require 'async'

# Specify the Redis server to connect to with --redis or -r
redis_address = (argv.redis || argv.r || ':').split(':')
redis_host = redis_address[0] || 'localhost'
redis_port = redis_address[1] || 6379
redis = null
connectToRedis = (cb) ->
    redis = require('redis').createClient(redis_port, redis_host)
    redis_connected = false
    redisFailed = (err) ->
        if !redis_connected
            console.log "[ERROR] Could not connect to Redis at #{ redis_host }:#{ redis_port }"
        else
            console.log err
        process.exit()
    redis.on 'ready', ->
        redis_connected = true
        cb()
    redis.on 'error', redisFailed

# Helpers
# ------------------------------------------------------------------------------

# WARNING/TODO: All methods relying on makeContainerAddress are assuming that a container
# will have only one exposed port where the desired service presides.
getFirstPort = (net) -> _.keys(net.Ports)[0].split('/')[0]
makeContainerAddress = (net) -> 'http://' + net.IPAddress + ':' + getFirstPort net

hostname_key_prefix = 'frontend:'
hostnameKey = (hostname) -> hostname_key_prefix + hostname

parseProtoAddress = (proto_address) ->
    proto_address = proto_address.split('://')
    if proto_address.length == 1
        proto = 'http'
        address = proto_address[0]
    else
        proto = proto_address[0]
        address = proto_address[1]
    return [proto, address]

formatProtoAddress = (proto, address) ->
    if address.match /^:\d+$/
        address = 'localhost' + address
    return proto + '://' + address

padRight = (s, n) ->
    s_ = '' + s
    while s_.length < n
        s_ += ' '
    return s_

# Core methods
# ------------------------------------------------------------------------------

# Check that the hostname has an address list set up, create one if not
ensureHostname = (hostname, cb) ->
    redis.llen hostnameKey(hostname), (err, l) ->
        if l < 1
            redis.rpush hostnameKey(hostname), hostname, cb
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

# Keeping track of container <-> address relationships
# ------------------------------------------------------------------------------

address_containers = {}
container_image_names = {} # Map container IDs to image names

# Get running docker containers with addresses for exposed ports
getAllContainers = (cb) ->
    docker.listContainers (err, containers=[]) ->
        async.map containers, (container, _cb) ->
            docker.getContainer(container.Id).inspect (err, full_container) ->
                container.Address = makeContainerAddress full_container.NetworkSettings
                container.ShortId = container.Id[..11]
                address_containers[container.Address] = container
                container_image_names[container.Id] = container.Image
                _cb null, container
        , cb

# Printing methods
# ------------------------------------------------------------------------------

# Print list of running containers
printAllContainers = (cb) ->
    console.log 'Running containers:'
    console.log '------------------'
    getAllContainers (err, containers) ->
        console.log padRight(container.ShortId, 16) + padRight(container.Image, 28) + container.Address for container in containers
        cb()

# Print out the addresses associated with a hostname
printAddresses = (hostname, cb) ->
    _printAddresses hostname, (err, output) ->
        console.log output
        cb()

# Build the string to print addresses
_printAddresses = (hostname, cb) ->
    redis.lrange hostnameKey(hostname), 1, -1, (err, addresses) ->
        output = ''
        output += '  HOST: ' + hostname
        for address in addresses
            output += '\n    --> '
            output += padRight address, 32
            if container = address_containers[address]
                output += "[#{ container.ShortId }] #{ container.Image }"
        if !addresses.length
            output += '\n      --- no assigned addresses'
        cb null, output

# Print out all known hostnames and associated addresses
printAllAddresses = (cb) ->
    console.log 'Current assignments:'
    console.log '-------------------'
    redis.keys hostnameKey('*'), (err, hostname_keys=[]) ->
        async.mapSeries hostname_keys, (hk, _cb) ->
            h = hk.replace(RegExp('^' + hostname_key_prefix), '')
            _printAddresses h, _cb
        , (err, outputs) ->
            console.log outputs.join '\n\n'
            cb()

printAssigning = (address) ->
    console.log '      --+ ' + address

printUnassigning = (address) ->
    console.log '      --x ' + address

# Commands
# ------------------------------------------------------------------------------

Chinook = {}

Chinook.prepare = (cb) ->
    connectToRedis ->
        getAllContainers cb

# Launch a new image and assign the resulting container to a hostname
# ------------------------------------------------------------------------------
# COMMAND: chinook launch {image_id} {hostname}

Chinook.launchImage = (cb) ->
    console.error "NOT IMPLEMENTED"
    cb()

# Assign a running container to a hostname
# ------------------------------------------------------------------------------
# COMMAND: chinook assign {container_id} {hostname}

Chinook.assign = (proto, address, hostname, cb) ->
    if assigner = Chinook.assigners[proto]
        assigner(address, hostname, cb)
    else
        Chinook.assignAddress(formatProtoAddress(proto, address), hostname, cb)

Chinook.assignAddress = (address, hostname, cb) ->
    printAssigning address

    ensureHostname hostname, ->
        addAddress hostname, address, cb

Chinook.assignContainer = (container_id, hostname, cb) ->

    docker.getContainer(container_id).inspect (err, container) ->
        console.log err if err

        container_address = makeContainerAddress container.NetworkSettings
        printAssigning container_address

        ensureHostname hostname, ->
            addAddress hostname, container_address, cb

Chinook.assigners =
    docker: Chinook.assignContainer

# Unassign a running container from a hostname
# ------------------------------------------------------------------------------
# COMMAND: chinook unassign {container_id} {hostname}

Chinook.unassign = (proto, address, hostname, cb) ->
    if unassigner = Chinook.unassigners[proto]
        unassigner(address, hostname, cb)
    else
        Chinook.unassignAddress(formatProtoAddress(proto, address), hostname, cb)

Chinook.unassignAddress = (address, hostname, cb) ->
    printUnassigning address

    ensureHostname hostname, ->
        removeAddress hostname, address, cb

Chinook.unassignContainer = (container_id, hostname, cb) ->

    docker.getContainer(container_id).inspect (err, container) ->
        console.log err if err

        container_address = makeContainerAddress container.NetworkSettings
        printUnassigning container_address

        Chinook.unassignAddress container_address, hostname, cb

Chinook.unassigners =
    docker: Chinook.unassignContainer

# Replace a running container with a new running container
# ------------------------------------------------------------------------------
# COMMAND: chinook replace {old_container_id} {new_container_id} {hostname}

Chinook.replace = (old_proto_address, new_proto_address, hostname, cb) ->

    Chinook.unassign old_proto_address..., hostname, ->
        Chinook.assign new_proto_address..., hostname, cb

# Clear a hostname's addresses
# ------------------------------------------------------------------------------
# COMMAND: chinook clear {hostname}

Chinook.clearHostname = (hostname, cb) ->
    redis.del hostnameKey(hostname), cb

if require.main != module

    # require() mode: Export the core commands
    # ------------------------------------------------------------------------------

    exports = Chinook
    console.log 'TODO: assign connected redis client to exported chinook context'

else

    # CLI mode: Interpret command line arguments and run specified methods
    # ------------------------------------------------------------------------------
    # TODO: Show help

    command = argv._[2]

    if command == 'launch'
        Chinook.launchImage ->
            process.exit()

    else if command == 'assign'
        _proto_address = parseProtoAddress argv._[3]
        _hostname = argv._[4] || argv.hostname || argv.hostname || argv.h

        Chinook.prepare ->
            Chinook.assign _proto_address..., _hostname, ->
                printAddresses _hostname, ->
                    process.exit()

    else if command == 'unassign'
        _proto_address = parseProtoAddress argv._[3]
        _hostname = argv._[4] || argv.hostname || argv.h

        #console.log "Unassigning container #{ _id } from #{ _hostname }..."

        Chinook.prepare ->
            Chinook.unassign _proto_address..., _hostname, ->
                printAddresses _hostname, ->
                    process.exit()

    else if command == 'replace'
        _old_proto_address = parseProtoAddress argv._[3]
        _new_proto_address = parseProtoAddress argv._[4]
        _hostname = argv._[5] || argv.hostname || argv.h

        #console.log "Replacing container #{ _old_proto_address } with #{ _new_proto_address } for #{ _hostname }..."

        Chinook.prepare ->
            Chinook.replace _old_proto_address, _new_proto_address, _hostname, ->
                printAddresses _hostname, ->
                    process.exit()

    else if command == 'clear'
        _hostname = argv._[3]

        Chinook.prepare ->
            Chinook.clearHostname _hostname, ->
                printAllAddresses ->
                    process.exit()

    else
        Chinook.prepare ->
            printAllContainers ->
                console.log ''
                printAllAddresses ->
                    process.exit()

