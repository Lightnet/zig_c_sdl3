-- test.lua
print("Hello from Lua inside Zig!")

function add(a, b)
    return a + b
end

print("The sum of 10 and 20 is: " .. add(10, 21))

print("Config table exists!")
print("KEY_TEST value: " .. Config.KEY_TEST)
print("VERSION value: " .. Config.VERSION)


-- 3. Call the registered Zig function
test("Hello from the Lua runtime!")
test("Player name is: " .. Config.PLAYER_NAME)