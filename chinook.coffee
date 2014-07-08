util = require 'util'
docker = new require('dockerode')({socketPath: '/var/run/docker.sock'})
_ = require 'underscore'
argv = require('minimist')(process.argv)
redis = require('redis').createClient()
async = require 'async'

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
showAddresses = (hostname, cb) ->
    redis.lrange hostnameKey(hostname), 1, -1, (err, addresses) ->
        console.log '\nHOSTNAME: ' + hostname
        console.log '    ----> ' + address for address in addresses
        cb()

# Print out all known hostnames and associated addresses
showAllAddresses = (cb) ->
    redis.keys hostnameKey('*'), (err, hostname_keys) ->
        async.eachSeries hostname_keys, (hk, _cb) ->
            h = hk.replace(RegExp('^' + hostname_key_prefix), '')
            showAddresses h, _cb
        , ->
            cb()

# Commands
# ------------------------------------------------------------------------------

command = argv._[2]

# chinook launch {image_id} {hostname}
# chinook attach {container_id} {hostname}
# chinook detach {container_id} {hostname}
# chinook replace {old_container_id} {new_container_id} {hostname}

# Launch a new image and attach the resulting container to a hostname
# ------------------------------------------------------------------------------

if command == 'launch'
    console.error "NOT IMPLEMENTED"
    process.exit()

# Attach a running container to a hostname
# ------------------------------------------------------------------------------

attachContainer = (container_id, hostname, cb) ->

    docker.getContainer(container_id).inspect (err, container) ->
        console.log err if err

        container_address = makeAddress container.NetworkSettings

        ensureHostname hostname, ->
            addAddress hostname, container_address, cb

if command == 'attach'

    _id = argv._[3]
    _hostname = argv._[4] || argv.hostname || argv.hostname || argv.h

    console.log "Attaching container #{ _id } to #{ _hostname }...\n"

    attachContainer _id, _hostname, ->
        showAddresses hostname, ->
            process.exit()

# Detach a running container from a hostname
# ------------------------------------------------------------------------------

detachContainer = (container_id, hostname, cb) ->

    docker.getContainer(container_id).inspect (err, container) ->
        console.log err if err

        container_address = makeAddress container.NetworkSettings

        ensureHostname hostname, ->
            removeAddress hostname, container_address, cb

if command == 'detach'
    
    _id = argv._[3]
    _hostname = argv._[4] || argv.hostname || argv.h

    console.log "Detaching container #{ _id } from #{ _hostname }..."

    detachContainer _id, _hostname, ->
        showAddresses _hostname, ->
            process.exit()

# Replace a running container with a new running container
# ------------------------------------------------------------------------------

replaceContainer = (old_container_id, new_container_id, hostname, cb) ->

    docker.getContainer(old_container_id).inspect (err, old_container) ->
        console.log err if err
        old_container_address = makeAddress old_container.NetworkSettings

        docker.getContainer(new_container_id).inspect (err, new_container) ->
            console.log err if err
            new_container_address = makeAddress new_container.NetworkSettings

            ensureHostname hostname, ->
                removeAddress hostname, old_container_address, ->
                    addAddress hostname, new_container_address, cb

if command == 'replace'
    
    _old_id = argv._[3]
    _new_id = argv._[4]
    _hostname = argv._[5] || argv.hostname || argv.h

    console.log "Replacing container #{ _old_id } with #{ _new_id } for #{ _hostname }..."

    replaceContainer _old_id, _new_id, _hostname, ->
        showAddresses _hostname, ->
            process.exit()

# No command: show all current hostnames and addresses
# ------------------------------------------------------------------------------
# TODO: Show help

if !command
    showAllAddresses ->
        process.exit()

