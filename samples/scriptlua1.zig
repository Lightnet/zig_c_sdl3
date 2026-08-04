const std = @import("std");
const ziglua = @import("zlua"); // https://github.com/natecraddock/ziglua

// 1. Define your data structures natively in Zig
const GameConfig = struct {
    KEY_TEST: i32 = 0,
    VERSION: i32 = 1,
    DEBUG_MODE: bool = true,
    PLAYER_NAME: []const u8 = "Ziggy",
};

// Define the logging function that Lua can call
fn luaLog(lua: *ziglua.Lua) i32 {
    // Read the string argument from the Lua stack (index 1)
    const message = lua.toString(1) catch "Invalid string passed to log";

    // Print the message natively in Zig
    std.debug.print("[Lua Log] {s}\n", .{message});

    // Return 0 because this function returns 0 values to Lua
    return 0;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lua = try ziglua.Lua.init(allocator);
    defer lua.deinit();

    lua.openLibs();

    // 2. Register the Zig function globally in Lua under the name "test"
    lua.pushFunction(ziglua.wrap(luaLog));
    lua.setGlobal("test");

    // 2. Instantiate your configuration data
    const config = GameConfig{};

    // 3. Use pushAny to let Ziglua automatically unpack the struct into a table
    try lua.pushAny(config);

    // 4. Register the table globally under the namespace "Config"
    lua.setGlobal("Config");

    std.debug.print("--- Executing Lua Script ---\n", .{});

    lua.doFile("script.lua") catch |err| {
        std.debug.print("Lua Error: {s}\n", .{@errorName(err)});
        return err;
    };

    std.debug.print("--- Execution Finished ---\n", .{});
}

// print("--- Lua checking automated mapping ---")
// print("KEY_TEST: " .. tostring(Config.KEY_TEST))      -- Output: 0
// print("VERSION: " .. tostring(Config.VERSION))        -- Output: 1
// print("DEBUG_MODE: " .. tostring(Config.DEBUG_MODE))  -- Output: true
// print("PLAYER_NAME: " .. Config.PLAYER_NAME)          -- Output: Ziggy
