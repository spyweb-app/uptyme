-- PULSE bootstrap configuration
--
-- This file is a starter template for headless checker setup.
-- Keep secrets out of this file. Use environment variables for tokens.
--
-- Suggested precedence:
--   1. environment variables
--   2. this config file
--   3. database settings
--
-- Replace the placeholder values before first start.

return {
    -- Activate cluster mode. When false, the node runs standalone and only `logging` applies.
    -- Role ("central" or "checker") only takes effect when multi_node is true.
    multi_node = true,

    role = "central", -- "central" or "checker"

    -- Human-readable name for this checker node.
    --node_name = "checker-PLACEHOLDER",

    -- Central instance URL.
    --central_url = "https://central.example.com",

    -- Read the shared secret from an environment variable, not from disk.
    --auth_token = env_get("PULSE_CENTRAL_TOKEN"),

    -- Consecutive failed sync polls before "central unreachable" alert fires.
    central_alert_failures = 3,

    -- Checker connectivity alert options.
    checker_alerts = {
      desktop = true,
      --channels = {
      --  { type = "ntfy",    config = { url = "https://ntfy.sh", topic = "pulse-checker" } },
      --  { type = "webhook", config = { url = "https://..." } },
      --},
    },

    -- Logging configuration.
    -- level:  debug | info | warn | error | none  (default: error)
    -- output: file | terminal | both | none        (default: file)
    -- throttle: N = at most one log per N same-category occurrences; 0 = off (default: 6)
    logging = { level = "error", output = "file", throttle = 6 },

}
