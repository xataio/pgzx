// const std = @import("std");
// const conv = @import("conv.zig");
// const c = @import("pgzx_pgsys");
//
// pub fn buildParams(allocator: std.mem.Allocator, params: anytype) !Params {
//     return Builder.new(allocator).build(params);
// }
//
// pub const Builder = struct {
//     allocator: std.mem.Allocator,
//
//     const Self = @This();
//
//     pub fn new(allocator: std.mem.Allocator) Self {
//         var result: Self = undefined;
//         result.init(allocator);
//         return result;
//     }
//
//     pub fn init(self: *Self, allocator: std.mem.Allocator) void {
//         self.allocator = allocator;
//     }
//
//     pub fn build(self: *const Self, params: anytype) !Params {
//         const paramType = @TypeOf(params);
//         const paramInfo = @typeInfo(paramType);
//         if (paramInfo != .@"struct" or !paramInfo.@"struct".is_tuple) {
//             return std.debug.panic("params must be a tuple");
//         }
//
//         var buffer = std.ArrayList(u8).init(self.allocator);
//         const writer: std.ArrayList(u8).Writer = buffer.writer();
//
//         var value_indices = try self.allocator.alloc(i32, paramInfo.@"struct".fields.len);
//         defer self.allocator.free(value_indices);
//
//         var types = try self.allocator.alloc(c.Oid, paramInfo.@"struct".fields.len);
//
//         inline for (paramInfo.@"struct".fields, 0..) |field, idx| {
//             const codec = conv.find(field.type);
//             types[idx] = codec.OID;
//             const initPos = buffer.items.len;
//             const writeFn = codec.write;
//             const value: field.type = @field(params, field.name);
//             try writeFn(writer, value);
//             const pos = buffer.items.len;
//             if (initPos == pos) {
//                 value_indices[idx] = -1;
//             } else {
//                 value_indices[idx] = @intCast(initPos);
//             }
//         }
//
//         var values = try self.allocator.alloc([*c]const u8, value_indices.len);
//         for (value_indices, 0..) |pos, idx| {
//             if (pos == -1) {
//                 values[idx] = null;
//             } else {
//                 values[idx] = buffer.items[@intCast(pos)..].ptr;
//             }
//         }
//
//         return Params{
//             .buffer = buffer,
//             .types = types,
//             .values = values,
//         };
//     }
// };
//
// pub const Params = struct {
//     buffer: std.ArrayList(u8),
//     types: []const c.Oid,
//     values: []const [*c]const u8,
// };
