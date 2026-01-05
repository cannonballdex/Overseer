local utils = require('overseer/utils/string_utils')

local actions = {}

local function assert(actual, expected, message)
    if (actual ~= expected) then
        printf("Test Failed. Actual(%s) Expected(%s). %s", actual, expected, message)
        return false
    end
    return true
end

local function assert_true(result, message) return assert(result, true, message) end

local function assert_false(result, message) return assert(result, false, message) end

local function test_starts_with()
    local result = true
    result = result and assert_true(utils.starts_with("A", "A"), "StartsWith 1")
    result = result and assert_false(utils.starts_with("A", "B"), "StartsWith 2")
    result = result and assert_true(utils.starts_with(" A", " "), "StartsWith 3")
    result = result and assert_false(utils.starts_with("BA", "A"), "StartsWith 4")
    result = result and assert_true(utils.starts_with("AB CD EF", "A"), "StartsWith 5")

    if (result) then return end

    print("TestStargsWith has one or more errors.")
end

local function test_trim_left()
    local result = true
    result = result and assert(utils.trim_left("A"), "A", "TrimLeft 1")
    result = result and assert(utils.trim_left(" A"), "A", "TrimLeft 2")
    result = result and assert(utils.trim_left("A "), "A ", "TrimLeft 3")
    result = result and assert(utils.trim_left(" A "), "A ", "TrimLeft 4")
    result = result and assert(utils.trim_left("      A"), "A", "TrimLeft 5")

    if (result) then return end

    print("test_trim_left has one or more errors.")
end

local function test_split()
    assert(utils.split("A", nil), {"A"}, "Split 1")
    assert(utils.split("A|B|C", "|"), {"A"}, "Split 1")
end

local function test_seconds_until_with_display_internal()
    local result = true
    local time = os.time({year=2000, month=1, day=1, hour=0, min=0, sec=0})

    local future  = time + 1
    local seconds, display = utils.seconds_until_with_display_internal(future, time)
    result = result and assert(seconds, 1)
    result = result and assert(display, "0h:0m:1s")

    future  = time + 60
    seconds, display = utils.seconds_until_with_display_internal(future, time)
    result = result and assert(seconds, 60)
    result = result and assert(display, "0h:1m:0s")

    future  = time + 3661
    seconds, display = utils.seconds_until_with_display_internal(future, time)
    result = result and assert(seconds, 3661)
    result = result and assert(display, "1h:1m:1s")

    future  = time + 7322
    seconds, display = utils.seconds_until_with_display_internal(future, time)
    result = result and assert(seconds, 7322)
    result = result and assert(display, "2h:2m:2s")

    if (result) then return end

    print("test_seconds_until_with_display_internal has one or more errors.")
end

function actions.RunTests()
    test_starts_with()
    test_trim_left()
    test_seconds_until_with_display_internal()

    print("Tests completed")
end

return actions