local M = {}

local MOD = 4294967296
local MAX = 4294967295

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local H0 = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

local function u32(n)
    n = n % MOD
    if n < 0 then
        n = n + MOD
    end
    return n
end

local function band(a, b)
    a = u32(a)
    b = u32(b)
    local res = 0
    local bit = 1
    for _ = 1, 32 do
        if (a % 2 == 1) and (b % 2 == 1) then
            res = res + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return res
end

local function bor(a, b)
    a = u32(a)
    b = u32(b)
    local res = 0
    local bit = 1
    for _ = 1, 32 do
        local ra = a % 2
        local rb = b % 2
        if ra == 1 or rb == 1 then
            res = res + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return res
end

local function bxor(a, b)
    a = u32(a)
    b = u32(b)
    local res = 0
    local bit = 1
    for _ = 1, 32 do
        local ra = a % 2
        local rb = b % 2
        if (ra + rb) == 1 then
            res = res + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return res
end

local function bnot(a)
    return MAX - u32(a)
end

local function lshift(a, n)
    n = n % 32
    if n == 0 then
        return u32(a)
    end
    return u32((u32(a) * (2 ^ n)) % MOD)
end

local function rshift(a, n)
    n = n % 32
    if n == 0 then
        return u32(a)
    end
    return math.floor(u32(a) / (2 ^ n))
end

local function ror(a, n)
    n = n % 32
    if n == 0 then
        return u32(a)
    end
    return bor(rshift(a, n), lshift(a, 32 - n))
end

local function preprocess(msg)
    local bytes = { string.byte(msg, 1, #msg) }
    local bit_len = #bytes * 8
    bytes[#bytes + 1] = 0x80

    while (#bytes % 64) ~= 56 do
        bytes[#bytes + 1] = 0
    end

    local hi = math.floor(bit_len / MOD)
    local lo = bit_len % MOD

    for shift = 24, 0, -8 do
        bytes[#bytes + 1] = math.floor(hi / (2 ^ shift)) % 256
    end
    for shift = 24, 0, -8 do
        bytes[#bytes + 1] = math.floor(lo / (2 ^ shift)) % 256
    end

    return bytes
end

local function to_hex(words)
    local out = {}
    for i = 1, #words do
        out[#out + 1] = string.format("%08x", u32(words[i]))
    end
    return table.concat(out)
end

function M.digest(msg)
    msg = msg or ""
    local bytes = preprocess(msg)
    local h = { H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8] }
    local w = {}

    for offset = 1, #bytes, 64 do
        for i = 0, 15 do
            local j = offset + i * 4
            w[i + 1] = u32(
                bytes[j] * 16777216 +
                bytes[j + 1] * 65536 +
                bytes[j + 2] * 256 +
                bytes[j + 3]
            )
        end

        for i = 17, 64 do
            local x = w[i - 15]
            local y = w[i - 2]
            local s0 = bxor(bxor(ror(x, 7), ror(x, 18)), rshift(x, 3))
            local s1 = bxor(bxor(ror(y, 17), ror(y, 19)), rshift(y, 10))
            w[i] = u32(w[i - 16] + s0 + w[i - 7] + s1)
        end

        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]

        for i = 1, 64 do
            local s1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = u32(hh + s1 + ch + K[i] + w[i])
            local s0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = u32(s0 + maj)

            hh = g
            g = f
            f = e
            e = u32(d + temp1)
            d = c
            c = b
            b = a
            a = u32(temp1 + temp2)
        end

        h[1] = u32(h[1] + a)
        h[2] = u32(h[2] + b)
        h[3] = u32(h[3] + c)
        h[4] = u32(h[4] + d)
        h[5] = u32(h[5] + e)
        h[6] = u32(h[6] + f)
        h[7] = u32(h[7] + g)
        h[8] = u32(h[8] + hh)
    end

    return to_hex(h)
end

M.hex = M.digest

function M.equal(a, b)
    a = a or ""
    b = b or ""

    local len_a = #a
    local len_b = #b
    local max_len = math.max(len_a, len_b)
    local diff = math.abs(len_a - len_b)

    for i = 1, max_len do
        local ca = i <= len_a and a:byte(i) or 0
        local cb = i <= len_b and b:byte(i) or 0
        diff = diff + math.abs(ca - cb)
    end

    return diff == 0
end

return M
