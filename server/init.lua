local H = require("helpers")
local monitors = require("handlers.monitors")
local cluster = require("handlers.cluster")
local reports = require("handlers.reports")
local nodes = require("handlers.nodes")
local settings = require("handlers.settings")
local channels = require("handlers.channels")
local health = require("handlers.health")
local cluster_auth = require("lib.cluster_auth")
local logger = require("lib.logger")

local function verify_public_endpoint(handler)
    return function(self)
        local node = cluster_auth.verify(self)
        if not node then return H.json_response(401, nil, "Unauthorized") end
        logger.debug("recieve checker request: " .. dump(self), "cluster.inbound")
        return handler(self, node)
    end
end

get.monitors = monitors.list
get.monitors_export = monitors.export
post.monitors = monitors.create
post.monitors_import = monitors.import
put.monitors = monitors.update
delete.monitors = monitors.remove

get.settings = settings.get
put.settings = settings.update

get.channels = channels.list
post.channels = channels.create
put.channels = channels.update
delete.channels = channels.remove

get.health = health.check

get.nodes = nodes.list
post.nodes = nodes.create
put.nodes = nodes.update
delete.nodes = nodes.remove

public.get.cluster_version = verify_public_endpoint(cluster.version)
public.get.cluster_export = verify_public_endpoint(cluster.export)
public.post.report = verify_public_endpoint(reports.report)
public.get.node_me = verify_public_endpoint(nodes.me)