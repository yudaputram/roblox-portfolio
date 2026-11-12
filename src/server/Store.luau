-- Tempat PlayerData menyimpan rekaman. Dua backend dengan bentuk yang sama:
-- store:update(key, transform) meniru UpdateAsync. transform menerima nilai lama
-- dan mengembalikan nilai baru, atau nil untuk membatalkan tulis. Gagal = error.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Store = {}

-- DataStore asli. GetDataStore sendiri error di place yang belum dipublish, jadi
-- dipanggil di dalam update supaya errornya masuk pcall pemanggil seperti error lain.
function Store.datastore(name: string, service: any?)
	local source = service or DataStoreService
	local dataStore = nil
	local store = {}
	function store:update(key: string, transform: (any) -> any)
		if not dataStore then
			dataStore = source:GetDataStore(name)
		end
		dataStore:UpdateAsync(key, transform)
	end
	return store
end

-- Backend palsu untuk tes. Nilai disimpan sebagai string JSON supaya tes tidak lolos
-- karena store dan sesi berbagi table yang sama (DataStore asli juga menyalin).
function Store.memory()
	local store = {
		calls = 0,
		onUpdate = nil :: ((key: string) -> ())?, -- hook tes: boleh yield untuk menyisipkan kejadian lain
		_raw = {} :: { [string]: string },
		_failures = {} :: { string },
	}

	function store:failNext(count: number, message: string)
		for _ = 1, count do
			table.insert(self._failures, message)
		end
	end

	function store:raw(key: string): string?
		return self._raw[key]
	end

	function store:peek(key: string): any
		local raw = self._raw[key]
		return raw and HttpService:JSONDecode(raw)
	end

	function store:update(key: string, transform: (any) -> any)
		self.calls += 1
		if self.onUpdate then
			self.onUpdate(key)
		end
		if #self._failures > 0 then
			error(table.remove(self._failures, 1), 0)
		end
		local function current()
			local raw = self._raw[key]
			return raw and HttpService:JSONDecode(raw)
		end
		-- UpdateAsync asli boleh menjalankan transform lebih dari sekali. Jalankan dua
		-- kali dan buang hasil pertama supaya efek samping ganda ketahuan di tes.
		transform(current())
		local new = transform(current())
		if new ~= nil then
			self._raw[key] = HttpService:JSONEncode(new)
		end
	end

	return store
end

return Store
