local monitors = require("handlers.monitors")
local cluster = require("handlers.cluster")
local reports = require("handlers.reports")
local nodes = require("handlers.nodes")
local settings = require("handlers.settings")
local channels = require("handlers.channels")
local health = require("handlers.health")   

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

public.get.cluster_version = cluster.version
public.get.cluster_export = cluster.export
public.post.report = reports.report
public.get.node_me = nodes.me