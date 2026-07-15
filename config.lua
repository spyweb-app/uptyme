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
    -- Leave disabled until you explicitly want the bootstrap file to take effect.
    enabled = false,

    role = "checker",

    -- Human-readable name for this checker node.
    node_name = "checker-PLACEHOLDER",

    -- Central instance URL.
    central_url = "https://central.example.com",

    -- Read the shared secret from an environment variable, not from disk.
    auth_token = env_get("PULSE_CENTRAL_TOKEN"),

    -- How often the checker polls central for monitor definition changes.
    sync_interval_sec = 10,

    -- How long a checker can go without successful central contact before it
    -- emits a local connectivity alert.
    node_liveness_sec = 90,

}
