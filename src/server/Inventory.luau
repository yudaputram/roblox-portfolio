-- Kelas kecil di atas set { [itemId] = true }. Set-nya tetap table biasa
-- supaya bisa langsung disimpan ke DataStore.
local Inventory = {}
Inventory.__index = Inventory

export type Inventory = typeof(setmetatable({} :: { _owned: { [string]: boolean } }, Inventory))

function Inventory.new(owned: { [string]: boolean }): Inventory
	return setmetatable({ _owned = owned }, Inventory)
end

function Inventory.has(self: Inventory, itemId: string): boolean
	return self._owned[itemId] == true
end

function Inventory.add(self: Inventory, itemId: string): boolean
	if self:has(itemId) then
		return false
	end
	self._owned[itemId] = true
	return true
end

function Inventory.list(self: Inventory): { string }
	local ids = {}
	for itemId in self._owned do
		table.insert(ids, itemId)
	end
	table.sort(ids) -- urutan pairs tidak dijamin
	return ids
end

return Inventory
