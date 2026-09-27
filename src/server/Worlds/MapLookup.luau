-- Name-based lookups into the hand-built map (static parts in the place
-- file, not Rojo). Every miss warns with the full path, so a renamed or
-- missing part shows up in Output instead of silently doing nothing.

local MapLookup = {}

function MapLookup.Find(parent: Instance?, name: string, className: string?): any
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	if not child then
		warn(`[Map] missing {parent:GetFullName()}.{name}`)
		return nil
	end

	if className and not child:IsA(className) then
		warn(`[Map] {child:GetFullName()} is a {child.ClassName}, expected {className}`)
		return nil
	end

	return child
end

function MapLookup.Attr(instance: Instance?, name: string, expectedType: string): any
	if not instance then
		return nil
	end

	local value = instance:GetAttribute(name)
	if value == nil then
		warn(`[Map] {instance:GetFullName()} is missing attribute {name}`)
		return nil
	end

	if typeof(value) ~= expectedType then
		warn(`[Map] {instance:GetFullName()} attribute {name} is a {typeof(value)}, expected {expectedType}`)
		return nil
	end

	return value
end

return MapLookup
