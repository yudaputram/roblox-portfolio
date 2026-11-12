-- Token bucket per pemain, dipakai bersama oleh setiap remote yang perlu batas request.
-- Request yang kelewat batas dibuang sebelum validasi lain. now disuntik supaya bisa dites.
type Bucket = { tokens: number, updatedAt: number }

local RateLimit = {}
RateLimit.__index = RateLimit

-- capacity: request beruntun yang boleh lewat; refillPerSecond: jatah yang kembali tiap detik.
function RateLimit.new(capacity: number, refillPerSecond: number)
	local self = setmetatable({}, RateLimit)
	self._capacity = capacity
	self._refill = refillPerSecond
	self._buckets = {} :: { [Player]: Bucket }
	return self
end

function RateLimit:allow(player: Player, now: number): boolean
	local bucket = self._buckets[player]
	if not bucket then
		bucket = { tokens = self._capacity, updatedAt = now }
		self._buckets[player] = bucket
	end
	local refilled = bucket.tokens + (now - bucket.updatedAt) * self._refill
	bucket.tokens = math.min(self._capacity, refilled)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimit:removePlayer(player: Player)
	self._buckets[player] = nil
end

return RateLimit
