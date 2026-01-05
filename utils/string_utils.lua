local actions = {}

function actions.split(inputstr, separator)
	if separator == nil then
		separator = "%s"
	end

	local bits = {}
	for bit in string.gmatch(inputstr, "([^" .. separator .. "]+)") do
		table.insert(bits, bit)
	end

	return bits
end

function actions.contains(text, compare)
	if (text == compare) then return true end
	if (text == nil or compare == nil) then return false end
	return text:find(compare, 1, true) ~= nil
end

function actions.starts_with(text, compare)
	return string.sub(text, 1, compare:len()) == compare
end

function actions.ends_with(text, compare)
	return string.sub(text, text:len()-compare:len()+1, text:len()) == compare
end

function actions.trim_left(input)
	local index

	::again::
	index, _ = string.find(input, " ")
	if (index == 1) then
		input = string.sub(input, 2)
		goto again
	end
	return input
end

function actions.seconds_until_with_display_internal(displayTime, nowTime)
	local diff  = os.difftime(displayTime, nowTime)
	local hour = math.floor(diff / 3600)
	local minute = math.floor((diff - (hour*3600)) / 60)
	local second = math.floor(diff - (hour*3600) - (minute*60))
	local diffText = string.format("%sh:%sm:%ss", hour, minute, second)
	return diff, diffText
end

function actions.seconds_until_with_display(displayTime)
	return actions.seconds_until_with_display_internal(displayTime, os.time())
end

return actions