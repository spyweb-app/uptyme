local H = require("helpers")
local monitors = require("handlers.monitors")
local cluster = require("handlers.cluster")
local reports = require("handlers.reports")
local nodes = require("handlers.nodes")
local settings = require("handlers.settings")
local channels = require("handlers.channels")
local health = require("handlers.health")
local stats = require("handlers.stats")
local public_status = require("handlers.public_status")
local status_pages = require("handlers.status_pages")
local cluster_auth = require("lib.cluster_auth")
local logger = require("lib.logger")
local rate_limit = require("lib.rate_limit")

local function normalize_client_ip(addr)
    if not addr or addr == "" then return "unknown" end

    local ipv6 = addr:match("^%[(.-)%]:%d+$")
    if ipv6 then return ipv6 end

    return addr:match("^(.*):%d+$") or addr
end

local function throttle(handler, scope, opts)
    opts = opts or {}
    local limit = opts.limit or 60
    local window = opts.window or 60
    local key_fn = opts.key_fn or function(self)
        return normalize_client_ip(self.client_ip)
    end

    return function(self, ...)
        local identity = key_fn(self, ...)
        local err = rate_limit.check(scope .. ":" .. tostring(identity), limit, window)
        if err then
            return {
                status = 429,
                body = json_encode({
                    success = false,
                    error = "Rate limit exceeded",
                }, true),
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Retry-After"] = tostring(err.retry_after),
                    ["X-RateLimit-Limit"] = tostring(err.limit),
                    ["X-RateLimit-Remaining"] = tostring(err.remaining),
                },
            }
        end
        return handler(self, ...)
    end
end

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
post.monitors = throttle(monitors.create, "admin:monitors:create", { limit = 30 })
post.monitors_import = throttle(monitors.import, "admin:monitors:import", { limit = 10 })
put.monitors = throttle(monitors.update, "admin:monitors:update", { limit = 60 })
delete.monitors = throttle(monitors.remove, "admin:monitors:delete", { limit = 30 })

get.settings = settings.get
put.settings = throttle(settings.update, "admin:settings:update", { limit = 10 })

get.channels = channels.list
post.channels = throttle(channels.create, "admin:channels:create", { limit = 30 })
put.channels = throttle(channels.update, "admin:channels:update", { limit = 60 })
delete.channels = throttle(channels.remove, "admin:channels:delete", { limit = 30 })

get.health = health.check

get.stats = stats.get

get.nodes = nodes.list
post.nodes = throttle(nodes.create, "admin:nodes:create", { limit = 10 })
put.nodes = throttle(nodes.update, "admin:nodes:update", { limit = 60 })
delete.nodes = throttle(nodes.remove, "admin:nodes:delete", { limit = 30 })

get.status_pages = status_pages.list
post.status_pages = throttle(status_pages.create, "admin:status-pages:create", { limit = 30 })
put.status_pages = throttle(status_pages.update, "admin:status-pages:update", { limit = 60 })
delete.status_pages = throttle(status_pages.remove, "admin:status-pages:delete", { limit = 30 })

public.get.cluster_version = throttle( verify_public_endpoint(cluster.version), "public:cluster-version", { limit = 30 } )
public.get.cluster_export = throttle( verify_public_endpoint(cluster.export), "public:cluster-export", { limit = 10 } )
public.post.report = throttle( verify_public_endpoint( throttle(reports.report, "public:report:node", { 
            limit = 300,
            key_fn = function(_, node)
                return tostring(node.id)
            end,
        }
    )), "public:report:ip", { limit = 60 }
)
public.get.node_me = throttle( verify_public_endpoint(nodes.me), "public:node-me", { limit = 30 } )
public.get.status = throttle(public_status.get, "public:status", { limit = 60 })
