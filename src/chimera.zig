const std = @import("std");

/// Chimera (Hyperscan + PCRE hybrid) Zig bindings
/// High-performance regex matching with proper start/end positions
/// Uses Hyperscan for pre-filtering and PCRE for accurate matching

// ============================================================================
// C API Bindings
// ============================================================================

pub const c = @cImport({
    @cInclude("ch/ch.h");
});

// Re-export common types with Zig naming
pub const Database = c.ch_database_t;
pub const Scratch = c.ch_scratch_t;
pub const CompileError = c.ch_compile_error_t;
pub const Error = c.ch_error_t;

// Error codes
pub const SUCCESS = c.CH_SUCCESS;
pub const INVALID = c.CH_INVALID;
pub const NOMEM = c.CH_NOMEM;
pub const SCAN_TERMINATED = c.CH_SCAN_TERMINATED;
pub const COMPILER_ERROR = c.CH_COMPILER_ERROR;
pub const DB_VERSION_ERROR = c.CH_DB_VERSION_ERROR;
pub const DB_PLATFORM_ERROR = c.CH_DB_PLATFORM_ERROR;
pub const DB_MODE_ERROR = c.CH_DB_MODE_ERROR;
pub const BAD_ALIGN = c.CH_BAD_ALIGN;
pub const BAD_ALLOC = c.CH_BAD_ALLOC;
pub const SCRATCH_IN_USE = c.CH_SCRATCH_IN_USE;
pub const ARCH_ERROR = c.CH_ARCH_ERROR;

// ============================================================================
// High-level Zig API
// ============================================================================

/// Compile multiple PCRE patterns into a Chimera database
pub fn compileMulti(
    patterns: []const [:0]const u8,
    flags: []const c_uint,
    ids: []const c_uint,
    allocator: std.mem.Allocator,
) !*Database {
    if (patterns.len != flags.len or patterns.len != ids.len) {
        return error.LengthMismatch;
    }

    // Convert Zig slices to C arrays
    const pattern_ptrs = try allocator.alloc([*c]const u8, patterns.len);
    defer allocator.free(pattern_ptrs);

    for (patterns, 0..) |pattern, i| {
        pattern_ptrs[i] = pattern.ptr;
    }

    var database: ?*Database = null;
    var compile_err: ?*CompileError = null;

    const result = c.ch_compile_multi(
        pattern_ptrs.ptr,
        flags.ptr,
        ids.ptr,
        @intCast(patterns.len),
        c.CH_MODE_NOGROUPS, // No capturing groups for now
        null, // platform info
        &database,
        &compile_err,
    );

    if (result != SUCCESS) {
        if (compile_err) |err| {
            defer _ = c.ch_free_compile_error(err);
            return error.CompileError;
        }
        return error.UnknownCompileError;
    }

    return database.?;
}

/// Allocate scratch space for a database
pub fn allocScratch(database: *Database) !*Scratch {
    var scratch: ?*Scratch = null;

    const result = c.ch_alloc_scratch(database, &scratch);

    if (result != SUCCESS) {
        return error.ScratchAllocFailed;
    }

    return scratch.?;
}

/// Match callback context
pub const MatchContext = struct {
    matches: std.ArrayList(Match),
    allocator: std.mem.Allocator,
};

/// A single match result with proper start/end positions
pub const Match = struct {
    id: u32,
    from: u64,
    to: u64,
};

/// Callback function for matches (called from C)
export fn chimeraMatchCallback(
    id: c_uint,
    from: c_ulonglong,
    to: c_ulonglong,
    flags: c_uint,
    size: c_uint,
    captured: [*c]const c.ch_capture_t,
    context: ?*anyopaque,
) callconv(.c) c_int {
    _ = flags;
    _ = size;
    _ = captured;

    const ctx: *MatchContext = @ptrCast(@alignCast(context.?));

    ctx.matches.append(ctx.allocator, Match{
        .id = id,
        .from = from,
        .to = to,
    }) catch return 1; // Return non-zero to stop scanning on error

    return 0; // 0 = continue scanning
}

/// Scan data for matches using Chimera (Hyperscan + PCRE)
pub fn scan(
    database: *Database,
    data: []const u8,
    scratch: *Scratch,
    allocator: std.mem.Allocator,
) ![]Match {
    var ctx = MatchContext{
        .matches = std.ArrayList(Match){},
        .allocator = allocator,
    };
    defer ctx.matches.deinit(allocator);

    const result = c.ch_scan(
        database,
        data.ptr,
        @intCast(data.len),
        0, // flags
        scratch,
        chimeraMatchCallback,
        null, // error callback
        &ctx,
    );

    if (result != SUCCESS and result != SCAN_TERMINATED) {
        return error.ScanFailed;
    }

    return try ctx.matches.toOwnedSlice(allocator);
}

/// Free a compiled database
pub fn freeDatabase(database: *Database) void {
    _ = c.ch_free_database(database);
}

/// Free scratch space
pub fn freeScratch(scratch: *Scratch) void {
    _ = c.ch_free_scratch(scratch);
}

// ============================================================================
// Tests
// ============================================================================

test "chimera basic URL detection" {
    const allocator = std.testing.allocator;

    // PCRE pattern for URLs
    const patterns = [_][:0]const u8{"https?://[^\\s<>\"'{}\\[\\]]+"};
    const flags = [_]c_uint{0};
    const ids = [_]c_uint{0};

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const text = "Visit https://docs.example.com/api/v1/guide for more info";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    // Should find 1 URL
    try std.testing.expectEqual(@as(usize, 1), matches.len);

    // Check it matches the full URL
    try std.testing.expectEqual(@as(u64, 6), matches[0].from);
    try std.testing.expectEqual(@as(u64, 43), matches[0].to);

    const matched = text[matches[0].from..matches[0].to];
    try std.testing.expectEqualStrings("https://docs.example.com/api/v1/guide", matched);
}

test "chimera multiple URLs" {
    const allocator = std.testing.allocator;

    const patterns = [_][:0]const u8{"https?://[^\\s<>\"'{}\\[\\]]+"};
    const flags = [_]c_uint{0};
    const ids = [_]c_uint{0};

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const text = "Check https://example.com and http://test.org";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    // Should find exactly 2 URLs
    try std.testing.expectEqual(@as(usize, 2), matches.len);
}

test "chimera certificate DN" {
    const allocator = std.testing.allocator;

    const patterns = [_][:0]const u8{"(?:C|CN|O|OU|L|ST|DC|EMAIL)=[^/,]+(?:[/,]\\s*(?:C|CN|O|OU|L|ST|DC|EMAIL)=[^/,]+)*"};
    const flags = [_]c_uint{0};
    const ids = [_]c_uint{0};

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const text = "Subject: C=US/ST=California/O=TechCorp/CN=example.com";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    try std.testing.expect(matches.len > 0);

    const matched = text[matches[0].from..matches[0].to];
    try std.testing.expect(std.mem.indexOf(u8, matched, "C=US") != null);
    try std.testing.expect(std.mem.indexOf(u8, matched, "CN=example.com") != null);
}

test "chimera URL with ports and query strings" {
    const allocator = std.testing.allocator;

    const patterns = [_][:0]const u8{"https?://[^\\s<>\"'{}\\[\\]]+"};
    const flags = [_]c_uint{0};
    const ids = [_]c_uint{0};

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const text = "API: https://api.example.com:8443/v2/users?filter=active&sort=name";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    try std.testing.expectEqual(@as(usize, 1), matches.len);

    const matched = text[matches[0].from..matches[0].to];
    try std.testing.expectEqualStrings("https://api.example.com:8443/v2/users?filter=active&sort=name", matched);
}

test "chimera multi-pattern detection" {
    const allocator = std.testing.allocator;

    // Detect both URLs and email addresses
    const patterns = [_][:0]const u8{
        "https?://[^\\s<>\"'{}\\[\\]]+",  // URL pattern (id=0)
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", // Email pattern (id=1)
    };
    const flags = [_]c_uint{ 0, 0 };
    const ids = [_]c_uint{ 0, 1 };

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const text = "Contact admin@example.com or visit https://example.com/support";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    // Should find both email (id=1) and URL (id=0)
    try std.testing.expectEqual(@as(usize, 2), matches.len);

    // Verify we got both pattern types
    var found_email = false;
    var found_url = false;
    for (matches) |match| {
        if (match.id == 0) found_url = true;
        if (match.id == 1) found_email = true;
    }
    try std.testing.expect(found_email);
    try std.testing.expect(found_url);
}

test "chimera accurate position tracking" {
    const allocator = std.testing.allocator;

    const patterns = [_][:0]const u8{"https?://[^\\s<>\"'{}\\[\\]]+"};
    const flags = [_]c_uint{0};
    const ids = [_]c_uint{0};

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    // Test that positions are byte-accurate
    const text = "Prefix https://example.com Suffix";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    try std.testing.expectEqual(@as(usize, 1), matches.len);

    // Verify exact match boundaries
    const matched = text[matches[0].from..matches[0].to];
    try std.testing.expectEqualStrings("https://example.com", matched);

    // Verify positions are correct
    try std.testing.expectEqual(@as(u64, 7), matches[0].from);
    try std.testing.expectEqual(@as(u64, 26), matches[0].to);
}

test "chimera no matches" {
    const allocator = std.testing.allocator;

    const patterns = [_][:0]const u8{"https?://[^\\s<>\"'{}\\[\\]]+"};
    const flags = [_]c_uint{0};
    const ids = [_]c_uint{0};

    const db = try compileMulti(&patterns, &flags, &ids, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const text = "No URLs in this text at all";
    const matches = try scan(db, text, scratch, allocator);
    defer allocator.free(matches);

    // Should find nothing
    try std.testing.expectEqual(@as(usize, 0), matches.len);
}
