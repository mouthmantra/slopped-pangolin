pub const packages = struct {
    pub const @"aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw" = struct {
        pub const build_root = "/home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw";
        pub const build_zig = @import("aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX" = struct {
        pub const build_root = "/home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX";
        pub const build_zig = @import("pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"translate_c-0.0.0-Q_BUWlL1BgD7PmL27vTsccyNCOvKb-B65O5Ki1ZKm-ED" = struct {
        pub const build_root = "/home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/translate_c-0.0.0-Q_BUWlL1BgD7PmL27vTsccyNCOvKb-B65O5Ki1ZKm-ED";
        pub const build_zig = @import("translate_c-0.0.0-Q_BUWlL1BgD7PmL27vTsccyNCOvKb-B65O5Ki1ZKm-ED");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "aro", "aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw" },
        };
    };
    pub const @"wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX" = struct {
        pub const build_root = "/home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX";
        pub const build_zig = @import("wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"wlroots-0.20.2-dev-jmOlcrJuBABMWPGDKK86BO7zrfmxm17nimqFb0gffZTn" = struct {
        pub const build_root = "/home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/wlroots-0.20.2-dev-jmOlcrJuBABMWPGDKK86BO7zrfmxm17nimqFb0gffZTn";
        pub const build_zig = @import("wlroots-0.20.2-dev-jmOlcrJuBABMWPGDKK86BO7zrfmxm17nimqFb0gffZTn");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "pixman", "pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX" },
            .{ "wayland", "wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX" },
            .{ "xkbcommon", "xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr" },
        };
    };
    pub const @"xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr" = struct {
        pub const available = false;
    };
    pub const @"xkbcommon-0.4.0-VDqIe0i2AgDRsok2GpMFYJ8SVhQS10_PI2M_CnHXsJJZ" = struct {
        pub const build_root = "/home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/xkbcommon-0.4.0-VDqIe0i2AgDRsok2GpMFYJ8SVhQS10_PI2M_CnHXsJJZ";
        pub const build_zig = @import("xkbcommon-0.4.0-VDqIe0i2AgDRsok2GpMFYJ8SVhQS10_PI2M_CnHXsJJZ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "pixman", "pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX" },
    .{ "wayland", "wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX" },
    .{ "wlroots", "wlroots-0.20.2-dev-jmOlcrJuBABMWPGDKK86BO7zrfmxm17nimqFb0gffZTn" },
    .{ "xkbcommon", "xkbcommon-0.4.0-VDqIe0i2AgDRsok2GpMFYJ8SVhQS10_PI2M_CnHXsJJZ" },
    .{ "translate_c", "translate_c-0.0.0-Q_BUWlL1BgD7PmL27vTsccyNCOvKb-B65O5Ki1ZKm-ED" },
};
