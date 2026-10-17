const __root = @This();
pub const __builtin = @import("c_builtins");
pub const __helpers = @import("helpers");

pub const __u_char = u8;
pub const __u_short = c_ushort;
pub const __u_int = c_uint;
pub const __u_long = c_ulong;
pub const __int8_t = i8;
pub const __uint8_t = u8;
pub const __int16_t = c_short;
pub const __uint16_t = c_ushort;
pub const __int32_t = c_int;
pub const __uint32_t = c_uint;
pub const __int64_t = c_long;
pub const __uint64_t = c_ulong;
pub const __int_least8_t = __int8_t;
pub const __uint_least8_t = __uint8_t;
pub const __int_least16_t = __int16_t;
pub const __uint_least16_t = __uint16_t;
pub const __int_least32_t = __int32_t;
pub const __uint_least32_t = __uint32_t;
pub const __int_least64_t = __int64_t;
pub const __uint_least64_t = __uint64_t;
pub const __quad_t = c_long;
pub const __u_quad_t = c_ulong;
pub const __intmax_t = c_long;
pub const __uintmax_t = c_ulong;
pub const __dev_t = c_ulong;
pub const __uid_t = c_uint;
pub const __gid_t = c_uint;
pub const __ino_t = c_ulong;
pub const __ino64_t = c_ulong;
pub const __mode_t = c_uint;
pub const __nlink_t = c_ulong;
pub const __off_t = c_long;
pub const __off64_t = c_long;
pub const __pid_t = c_int;
pub const __fsid_t = extern struct {
    __val: [2]c_int,
};
pub const __clock_t = c_long;
pub const __rlim_t = c_ulong;
pub const __rlim64_t = c_ulong;
pub const __id_t = c_uint;
pub const __time_t = c_long;
pub const __useconds_t = c_uint;
pub const __suseconds_t = c_long;
pub const __suseconds64_t = c_long;
pub const __daddr_t = c_int;
pub const __key_t = c_int;
pub const __clockid_t = c_int;
pub const __timer_t = ?*anyopaque;
pub const __blksize_t = c_long;
pub const __blkcnt_t = c_long;
pub const __blkcnt64_t = c_long;
pub const __fsblkcnt_t = c_ulong;
pub const __fsblkcnt64_t = c_ulong;
pub const __fsfilcnt_t = c_ulong;
pub const __fsfilcnt64_t = c_ulong;
pub const __fsword_t = c_long;
pub const __ssize_t = c_long;
pub const __syscall_slong_t = c_long;
pub const __syscall_ulong_t = c_ulong;
pub const __loff_t = __off64_t;
pub const __caddr_t = [*c]u8;
pub const __intptr_t = c_long;
pub const __socklen_t = c_uint;
pub const __sig_atomic_t = c_int;
pub const time_t = __time_t;
pub const struct_timeval = extern struct {
    tv_sec: __time_t,
    tv_usec: __suseconds_t,
    pub const gettimeofday = __root.gettimeofday;
    pub const settimeofday = __root.settimeofday;
    pub const adjtime = __root.adjtime;
};
pub const suseconds_t = __suseconds_t;
pub const __sigset_t = extern struct {
    __val: [16]c_ulong,
};
pub const sigset_t = __sigset_t;
pub const struct_timespec = extern struct {
    tv_sec: __time_t,
    tv_nsec: __syscall_slong_t,
};
pub const __fd_mask = c_long;
pub const fd_set = extern struct {
    __fds_bits: [16]__fd_mask,
};
pub const fd_mask = __fd_mask;
pub extern fn select(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]struct_timeval) c_int;
pub extern fn pselect(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]const struct_timespec, noalias __sigmask: [*c]const __sigset_t) c_int;
pub const struct_timezone = extern struct {
    tz_minuteswest: c_int,
    tz_dsttime: c_int,
};
pub extern fn gettimeofday(noalias __tv: [*c]struct_timeval, noalias __tz: ?*anyopaque) c_int;
pub extern fn settimeofday(__tv: [*c]const struct_timeval, __tz: [*c]const struct_timezone) c_int;
pub extern fn adjtime(__delta: [*c]const struct_timeval, __olddelta: [*c]struct_timeval) c_int;
pub const ITIMER_REAL: c_int = 0;
pub const ITIMER_VIRTUAL: c_int = 1;
pub const ITIMER_PROF: c_int = 2;
pub const enum___itimer_which = c_uint;
pub const struct_itimerval = extern struct {
    it_interval: struct_timeval,
    it_value: struct_timeval,
};
pub const __itimer_which_t = c_int;
pub extern fn getitimer(__which: __itimer_which_t, __value: [*c]struct_itimerval) c_int;
pub extern fn setitimer(__which: __itimer_which_t, noalias __new: [*c]const struct_itimerval, noalias __old: [*c]struct_itimerval) c_int;
pub extern fn utimes(__file: [*c]const u8, __tvp: [*c]const struct_timeval) c_int;
pub extern fn lutimes(__file: [*c]const u8, __tvp: [*c]const struct_timeval) c_int;
pub extern fn futimes(__fd: c_int, __tvp: [*c]const struct_timeval) c_int;
pub const struct_winsize = extern struct {
    ws_row: c_ushort,
    ws_col: c_ushort,
    ws_xpixel: c_ushort,
    ws_ypixel: c_ushort,
};
pub extern fn ioctl(__fd: c_int, __request: c_ulong, ...) c_int;
pub const u_char = __u_char;
pub const u_short = __u_short;
pub const u_int = __u_int;
pub const u_long = __u_long;
pub const quad_t = __quad_t;
pub const u_quad_t = __u_quad_t;
pub const fsid_t = __fsid_t;
pub const loff_t = __loff_t;
pub const ino_t = __ino_t;
pub const dev_t = __dev_t;
pub const gid_t = __gid_t;
pub const mode_t = __mode_t;
pub const nlink_t = __nlink_t;
pub const uid_t = __uid_t;
pub const off_t = __off_t;
pub const pid_t = __pid_t;
pub const id_t = __id_t;
pub const daddr_t = __daddr_t;
pub const caddr_t = __caddr_t;
pub const key_t = __key_t;
pub const clock_t = __clock_t;
pub const clockid_t = __clockid_t;
pub const timer_t = __timer_t;
pub const ptrdiff_t = c_long;
pub const wchar_t = c_int;
pub const max_align_t = extern struct {
    __aro_max_align_ll: c_longlong,
    __aro_max_align_ld: c_longdouble,
};
pub const ulong = c_ulong;
pub const ushort = c_ushort;
pub const uint = c_uint;
pub const u_int8_t = __uint8_t;
pub const u_int16_t = __uint16_t;
pub const u_int32_t = __uint32_t;
pub const u_int64_t = __uint64_t;
pub const register_t = c_int;
pub fn __bswap_16(arg___bsx: __uint16_t) callconv(.c) __uint16_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @byteSwap(@as(__uint16_t, __bsx));
}
pub fn __bswap_32(arg___bsx: __uint32_t) callconv(.c) __uint32_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @bitCast(@as(c_int, @byteSwap(@as(c_int, @bitCast(@as(c_uint, @truncate(__bsx)))))));
}
pub fn __bswap_64(arg___bsx: __uint64_t) callconv(.c) __uint64_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @bitCast(@as(c_long, @byteSwap(@as(c_long, @bitCast(@as(c_ulong, @truncate(__bsx)))))));
}
pub fn __uint16_identity(arg___x: __uint16_t) callconv(.c) __uint16_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint32_identity(arg___x: __uint32_t) callconv(.c) __uint32_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint64_identity(arg___x: __uint64_t) callconv(.c) __uint64_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub const blksize_t = __blksize_t;
pub const blkcnt_t = __blkcnt_t;
pub const fsblkcnt_t = __fsblkcnt_t;
pub const fsfilcnt_t = __fsfilcnt_t;
const struct_unnamed_1 = extern struct {
    __low: c_uint,
    __high: c_uint,
};
pub const __atomic_wide_counter = extern union {
    __value64: c_ulonglong,
    __value32: struct_unnamed_1,
};
pub const struct___pthread_internal_list = extern struct {
    __prev: [*c]struct___pthread_internal_list,
    __next: [*c]struct___pthread_internal_list,
};
pub const __pthread_list_t = struct___pthread_internal_list;
pub const struct___pthread_internal_slist = extern struct {
    __next: [*c]struct___pthread_internal_slist,
};
pub const __pthread_slist_t = struct___pthread_internal_slist;
pub const struct___pthread_mutex_s = extern struct {
    __lock: c_int,
    __count: c_uint,
    __owner: c_int,
    __nusers: c_uint,
    __kind: c_int,
    __spins: c_short,
    __glibc_reserved: c_short,
    __list: __pthread_list_t,
};
pub const struct___pthread_rwlock_arch_t = extern struct {
    __readers: c_uint,
    __writers: c_uint,
    __wrphase_futex: c_uint,
    __writers_futex: c_uint,
    __pad3: c_uint,
    __pad4: c_uint,
    __cur_writer: c_int,
    __shared: c_int,
    __pad1: c_ulong,
    __pad2: c_ulong,
    __flags: c_uint,
};
pub const struct___pthread_cond_s = extern struct {
    __wseq: __atomic_wide_counter,
    __g1_start: __atomic_wide_counter,
    __g_size: [2]c_uint,
    __g1_orig_size: c_uint,
    __wrefs: c_uint,
    __g_signals: [2]c_uint,
    __unused_initialized_1: c_uint,
    __unused_initialized_2: c_uint,
};
pub const __tss_t = c_uint;
pub const __thrd_t = c_ulong;
pub const __once_flag = extern struct {
    __data: c_int,
};
pub const pthread_t = c_ulong;
pub const pthread_mutexattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_condattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_key_t = c_uint;
pub const pthread_once_t = c_int;
pub const union_pthread_attr_t = extern union {
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_attr_t = union_pthread_attr_t;
pub const pthread_mutex_t = extern union {
    __data: struct___pthread_mutex_s,
    __size: [40]u8,
    __align: c_long,
};
pub const pthread_cond_t = extern union {
    __data: struct___pthread_cond_s,
    __size: [48]u8,
    __align: c_longlong,
};
pub const pthread_rwlock_t = extern union {
    __data: struct___pthread_rwlock_arch_t,
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_rwlockattr_t = extern union {
    __size: [8]u8,
    __align: c_long,
};
pub const pthread_spinlock_t = c_int;
pub const pthread_barrier_t = extern union {
    __size: [32]u8,
    __align: c_long,
};
pub const pthread_barrierattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const __s8 = i8;
pub const __u8 = u8;
pub const __s16 = c_short;
pub const __u16 = c_ushort;
pub const __s32 = c_int;
pub const __u32 = c_uint;
pub const __s64 = c_longlong;
pub const __u64 = c_ulonglong;
pub const __kernel_fd_set = extern struct {
    fds_bits: [16]c_ulong,
};
pub const __kernel_sighandler_t = ?*const fn (c_int) callconv(.c) void;
pub const __kernel_key_t = c_int;
pub const __kernel_mqd_t = c_int;
pub const __kernel_old_uid_t = c_ushort;
pub const __kernel_old_gid_t = c_ushort;
pub const __kernel_old_dev_t = c_ulong;
pub const __kernel_long_t = c_long;
pub const __kernel_ulong_t = c_ulong;
pub const __kernel_ino_t = __kernel_ulong_t;
pub const __kernel_mode_t = c_uint;
pub const __kernel_pid_t = c_int;
pub const __kernel_ipc_pid_t = c_int;
pub const __kernel_uid_t = c_uint;
pub const __kernel_gid_t = c_uint;
pub const __kernel_suseconds_t = __kernel_long_t;
pub const __kernel_daddr_t = c_int;
pub const __kernel_uid32_t = c_uint;
pub const __kernel_gid32_t = c_uint;
pub const __kernel_size_t = __kernel_ulong_t;
pub const __kernel_ssize_t = __kernel_long_t;
pub const __kernel_ptrdiff_t = __kernel_long_t;
pub const __kernel_fsid_t = extern struct {
    val: [2]c_int,
};
pub const __kernel_off_t = __kernel_long_t;
pub const __kernel_loff_t = c_longlong;
pub const __kernel_uoff_t = c_ulonglong;
pub const __kernel_old_time_t = __kernel_long_t;
pub const __kernel_time_t = __kernel_long_t;
pub const __kernel_time64_t = c_longlong;
pub const __kernel_clock_t = __kernel_long_t;
pub const __kernel_timer_t = c_int;
pub const __kernel_clockid_t = c_int;
pub const __kernel_caddr_t = [*c]u8;
pub const __kernel_uid16_t = c_ushort;
pub const __kernel_gid16_t = c_ushort;
pub const __s128 = i128;
pub const __u128 = u128;
pub const __le16 = __u16;
pub const __be16 = __u16;
pub const __le32 = __u32;
pub const __be32 = __u32;
pub const __le64 = __u64;
pub const __be64 = __u64;
pub const __sum16 = __u16;
pub const __wsum = __u32;
pub const __poll_t = c_uint;
pub const struct_input_event = extern struct {
    time: struct_timeval,
    type: __u16,
    code: __u16,
    value: __s32,
    pub const libevdev_event_is_type = __root.libevdev_event_is_type;
    pub const libevdev_event_is_code = __root.libevdev_event_is_code;
};
pub const struct_input_id = extern struct {
    bustype: __u16,
    vendor: __u16,
    product: __u16,
    version: __u16,
};
pub const struct_input_absinfo = extern struct {
    value: __s32,
    minimum: __s32,
    maximum: __s32,
    fuzz: __s32,
    flat: __s32,
    resolution: __s32,
};
pub const struct_input_keymap_entry = extern struct {
    flags: __u8,
    len: __u8,
    index: __u16,
    keycode: __u32,
    scancode: [32]__u8,
};
pub const struct_input_mask = extern struct {
    type: __u32,
    codes_size: __u32,
    codes_ptr: __u64,
};
pub const struct_ff_replay = extern struct {
    length: __u16,
    delay: __u16,
};
pub const struct_ff_trigger = extern struct {
    button: __u16,
    interval: __u16,
};
pub const struct_ff_envelope = extern struct {
    attack_length: __u16,
    attack_level: __u16,
    fade_length: __u16,
    fade_level: __u16,
};
pub const struct_ff_constant_effect = extern struct {
    level: __s16,
    envelope: struct_ff_envelope,
};
pub const struct_ff_ramp_effect = extern struct {
    start_level: __s16,
    end_level: __s16,
    envelope: struct_ff_envelope,
};
pub const struct_ff_condition_effect = extern struct {
    right_saturation: __u16,
    left_saturation: __u16,
    right_coeff: __s16,
    left_coeff: __s16,
    deadband: __u16,
    center: __s16,
};
pub const struct_ff_periodic_effect = extern struct {
    waveform: __u16,
    period: __u16,
    magnitude: __s16,
    offset: __s16,
    phase: __u16,
    envelope: struct_ff_envelope,
    custom_len: __u32,
    custom_data: [*c]__s16,
};
pub const struct_ff_rumble_effect = extern struct {
    strong_magnitude: __u16,
    weak_magnitude: __u16,
};
pub const struct_ff_haptic_effect = extern struct {
    hid_usage: __u16,
    vendor_id: __u16,
    vendor_waveform_page: __u8,
    intensity: __u16,
    repeat_count: __u16,
    retrigger_period: __u16,
};
const union_unnamed_2 = extern union {
    constant: struct_ff_constant_effect,
    ramp: struct_ff_ramp_effect,
    periodic: struct_ff_periodic_effect,
    condition: [2]struct_ff_condition_effect,
    rumble: struct_ff_rumble_effect,
    haptic: struct_ff_haptic_effect,
};
pub const struct_ff_effect = extern struct {
    type: __u16,
    id: __s16,
    direction: __u16,
    trigger: struct_ff_trigger,
    replay: struct_ff_replay,
    u: union_unnamed_2,
};
pub const struct___va_list_tag_3 = extern struct {
    unnamed_0: c_uint,
    unnamed_1: c_uint,
    unnamed_2: ?*anyopaque,
    unnamed_3: ?*anyopaque,
};
pub const __builtin_va_list = [1]struct___va_list_tag_3;
pub const va_list = __builtin_va_list;
pub const __gnuc_va_list = __builtin_va_list;
pub const struct_libevdev = opaque {
    pub const libevdev_free = __root.libevdev_free;
    pub const libevdev_set_device_log_function = __root.libevdev_set_device_log_function;
    pub const libevdev_grab = __root.libevdev_grab;
    pub const libevdev_set_fd = __root.libevdev_set_fd;
    pub const libevdev_change_fd = __root.libevdev_change_fd;
    pub const libevdev_get_fd = __root.libevdev_get_fd;
    pub const libevdev_next_event = __root.libevdev_next_event;
    pub const libevdev_has_event_pending = __root.libevdev_has_event_pending;
    pub const libevdev_get_name = __root.libevdev_get_name;
    pub const libevdev_set_name = __root.libevdev_set_name;
    pub const libevdev_get_phys = __root.libevdev_get_phys;
    pub const libevdev_set_phys = __root.libevdev_set_phys;
    pub const libevdev_get_uniq = __root.libevdev_get_uniq;
    pub const libevdev_set_uniq = __root.libevdev_set_uniq;
    pub const libevdev_get_id_product = __root.libevdev_get_id_product;
    pub const libevdev_set_id_product = __root.libevdev_set_id_product;
    pub const libevdev_get_id_vendor = __root.libevdev_get_id_vendor;
    pub const libevdev_set_id_vendor = __root.libevdev_set_id_vendor;
    pub const libevdev_get_id_bustype = __root.libevdev_get_id_bustype;
    pub const libevdev_set_id_bustype = __root.libevdev_set_id_bustype;
    pub const libevdev_get_id_version = __root.libevdev_get_id_version;
    pub const libevdev_set_id_version = __root.libevdev_set_id_version;
    pub const libevdev_get_driver_version = __root.libevdev_get_driver_version;
    pub const libevdev_has_property = __root.libevdev_has_property;
    pub const libevdev_enable_property = __root.libevdev_enable_property;
    pub const libevdev_disable_property = __root.libevdev_disable_property;
    pub const libevdev_has_event_type = __root.libevdev_has_event_type;
    pub const libevdev_has_event_code = __root.libevdev_has_event_code;
    pub const libevdev_get_abs_minimum = __root.libevdev_get_abs_minimum;
    pub const libevdev_get_abs_maximum = __root.libevdev_get_abs_maximum;
    pub const libevdev_get_abs_fuzz = __root.libevdev_get_abs_fuzz;
    pub const libevdev_get_abs_flat = __root.libevdev_get_abs_flat;
    pub const libevdev_get_abs_resolution = __root.libevdev_get_abs_resolution;
    pub const libevdev_get_abs_info = __root.libevdev_get_abs_info;
    pub const libevdev_get_event_value = __root.libevdev_get_event_value;
    pub const libevdev_set_event_value = __root.libevdev_set_event_value;
    pub const libevdev_fetch_event_value = __root.libevdev_fetch_event_value;
    pub const libevdev_get_slot_value = __root.libevdev_get_slot_value;
    pub const libevdev_set_slot_value = __root.libevdev_set_slot_value;
    pub const libevdev_fetch_slot_value = __root.libevdev_fetch_slot_value;
    pub const libevdev_get_num_slots = __root.libevdev_get_num_slots;
    pub const libevdev_get_current_slot = __root.libevdev_get_current_slot;
    pub const libevdev_set_abs_minimum = __root.libevdev_set_abs_minimum;
    pub const libevdev_set_abs_maximum = __root.libevdev_set_abs_maximum;
    pub const libevdev_set_abs_fuzz = __root.libevdev_set_abs_fuzz;
    pub const libevdev_set_abs_flat = __root.libevdev_set_abs_flat;
    pub const libevdev_set_abs_resolution = __root.libevdev_set_abs_resolution;
    pub const libevdev_set_abs_info = __root.libevdev_set_abs_info;
    pub const libevdev_enable_event_type = __root.libevdev_enable_event_type;
    pub const libevdev_disable_event_type = __root.libevdev_disable_event_type;
    pub const libevdev_enable_event_code = __root.libevdev_enable_event_code;
    pub const libevdev_disable_event_code = __root.libevdev_disable_event_code;
    pub const libevdev_kernel_set_abs_info = __root.libevdev_kernel_set_abs_info;
    pub const libevdev_kernel_set_led_value = __root.libevdev_kernel_set_led_value;
    pub const libevdev_kernel_set_led_values = __root.libevdev_kernel_set_led_values;
    pub const libevdev_set_clock_id = __root.libevdev_set_clock_id;
    pub const libevdev_get_repeat = __root.libevdev_get_repeat;
    pub const set_device_log_function = __root.libevdev_set_device_log_function;
    pub const grab = __root.libevdev_grab;
    pub const set_fd = __root.libevdev_set_fd;
    pub const change_fd = __root.libevdev_change_fd;
    pub const get_fd = __root.libevdev_get_fd;
    pub const next_event = __root.libevdev_next_event;
    pub const has_event_pending = __root.libevdev_has_event_pending;
    pub const get_name = __root.libevdev_get_name;
    pub const set_name = __root.libevdev_set_name;
    pub const get_phys = __root.libevdev_get_phys;
    pub const set_phys = __root.libevdev_set_phys;
    pub const get_uniq = __root.libevdev_get_uniq;
    pub const set_uniq = __root.libevdev_set_uniq;
    pub const get_id_product = __root.libevdev_get_id_product;
    pub const set_id_product = __root.libevdev_set_id_product;
    pub const get_id_vendor = __root.libevdev_get_id_vendor;
    pub const set_id_vendor = __root.libevdev_set_id_vendor;
    pub const get_id_bustype = __root.libevdev_get_id_bustype;
    pub const set_id_bustype = __root.libevdev_set_id_bustype;
    pub const get_id_version = __root.libevdev_get_id_version;
    pub const set_id_version = __root.libevdev_set_id_version;
    pub const get_driver_version = __root.libevdev_get_driver_version;
    pub const has_property = __root.libevdev_has_property;
    pub const enable_property = __root.libevdev_enable_property;
    pub const disable_property = __root.libevdev_disable_property;
    pub const has_event_type = __root.libevdev_has_event_type;
    pub const has_event_code = __root.libevdev_has_event_code;
    pub const get_abs_minimum = __root.libevdev_get_abs_minimum;
    pub const get_abs_maximum = __root.libevdev_get_abs_maximum;
    pub const get_abs_fuzz = __root.libevdev_get_abs_fuzz;
    pub const get_abs_flat = __root.libevdev_get_abs_flat;
    pub const get_abs_resolution = __root.libevdev_get_abs_resolution;
    pub const get_abs_info = __root.libevdev_get_abs_info;
    pub const get_event_value = __root.libevdev_get_event_value;
    pub const set_event_value = __root.libevdev_set_event_value;
    pub const fetch_event_value = __root.libevdev_fetch_event_value;
    pub const get_slot_value = __root.libevdev_get_slot_value;
    pub const set_slot_value = __root.libevdev_set_slot_value;
    pub const fetch_slot_value = __root.libevdev_fetch_slot_value;
    pub const get_num_slots = __root.libevdev_get_num_slots;
    pub const get_current_slot = __root.libevdev_get_current_slot;
    pub const set_abs_minimum = __root.libevdev_set_abs_minimum;
    pub const set_abs_maximum = __root.libevdev_set_abs_maximum;
    pub const set_abs_fuzz = __root.libevdev_set_abs_fuzz;
    pub const set_abs_flat = __root.libevdev_set_abs_flat;
    pub const set_abs_resolution = __root.libevdev_set_abs_resolution;
    pub const set_abs_info = __root.libevdev_set_abs_info;
    pub const enable_event_type = __root.libevdev_enable_event_type;
    pub const disable_event_type = __root.libevdev_disable_event_type;
    pub const enable_event_code = __root.libevdev_enable_event_code;
    pub const disable_event_code = __root.libevdev_disable_event_code;
    pub const kernel_set_abs_info = __root.libevdev_kernel_set_abs_info;
    pub const kernel_set_led_value = __root.libevdev_kernel_set_led_value;
    pub const kernel_set_led_values = __root.libevdev_kernel_set_led_values;
    pub const set_clock_id = __root.libevdev_set_clock_id;
    pub const get_repeat = __root.libevdev_get_repeat;
};
pub const LIBEVDEV_READ_FLAG_SYNC: c_int = 1;
pub const LIBEVDEV_READ_FLAG_NORMAL: c_int = 2;
pub const LIBEVDEV_READ_FLAG_FORCE_SYNC: c_int = 4;
pub const LIBEVDEV_READ_FLAG_BLOCKING: c_int = 8;
pub const enum_libevdev_read_flag = c_uint;
pub extern fn libevdev_new() ?*struct_libevdev;
pub extern fn libevdev_new_from_fd(fd: c_int, dev: [*c]?*struct_libevdev) c_int;
pub extern fn libevdev_free(dev: ?*struct_libevdev) void;
pub const LIBEVDEV_LOG_ERROR: c_int = 10;
pub const LIBEVDEV_LOG_INFO: c_int = 20;
pub const LIBEVDEV_LOG_DEBUG: c_int = 30;
pub const enum_libevdev_log_priority = c_uint;
pub const libevdev_log_func_t = ?*const fn (priority: enum_libevdev_log_priority, data: ?*anyopaque, file: [*c]const u8, line: c_int, func: [*c]const u8, format: [*c]const u8, args: [*c]struct___va_list_tag_3) callconv(.c) void;
pub extern fn libevdev_set_log_function(logfunc: libevdev_log_func_t, data: ?*anyopaque) void;
pub extern fn libevdev_set_log_priority(priority: enum_libevdev_log_priority) void;
pub extern fn libevdev_get_log_priority() enum_libevdev_log_priority;
pub const libevdev_device_log_func_t = ?*const fn (dev: ?*const struct_libevdev, priority: enum_libevdev_log_priority, data: ?*anyopaque, file: [*c]const u8, line: c_int, func: [*c]const u8, format: [*c]const u8, args: [*c]struct___va_list_tag_3) callconv(.c) void;
pub extern fn libevdev_set_device_log_function(dev: ?*struct_libevdev, logfunc: libevdev_device_log_func_t, priority: enum_libevdev_log_priority, data: ?*anyopaque) void;
pub const LIBEVDEV_GRAB: c_int = 3;
pub const LIBEVDEV_UNGRAB: c_int = 4;
pub const enum_libevdev_grab_mode = c_uint;
pub extern fn libevdev_grab(dev: ?*struct_libevdev, grab: enum_libevdev_grab_mode) c_int;
pub extern fn libevdev_set_fd(dev: ?*struct_libevdev, fd: c_int) c_int;
pub extern fn libevdev_change_fd(dev: ?*struct_libevdev, fd: c_int) c_int;
pub extern fn libevdev_get_fd(dev: ?*const struct_libevdev) c_int;
pub const LIBEVDEV_READ_STATUS_SUCCESS: c_int = 0;
pub const LIBEVDEV_READ_STATUS_SYNC: c_int = 1;
pub const enum_libevdev_read_status = c_uint;
pub extern fn libevdev_next_event(dev: ?*struct_libevdev, flags: c_uint, ev: [*c]struct_input_event) c_int;
pub extern fn libevdev_has_event_pending(dev: ?*struct_libevdev) c_int;
pub extern fn libevdev_get_name(dev: ?*const struct_libevdev) [*c]const u8;
pub extern fn libevdev_set_name(dev: ?*struct_libevdev, name: [*c]const u8) void;
pub extern fn libevdev_get_phys(dev: ?*const struct_libevdev) [*c]const u8;
pub extern fn libevdev_set_phys(dev: ?*struct_libevdev, phys: [*c]const u8) void;
pub extern fn libevdev_get_uniq(dev: ?*const struct_libevdev) [*c]const u8;
pub extern fn libevdev_set_uniq(dev: ?*struct_libevdev, uniq: [*c]const u8) void;
pub extern fn libevdev_get_id_product(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_set_id_product(dev: ?*struct_libevdev, product_id: c_int) void;
pub extern fn libevdev_get_id_vendor(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_set_id_vendor(dev: ?*struct_libevdev, vendor_id: c_int) void;
pub extern fn libevdev_get_id_bustype(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_set_id_bustype(dev: ?*struct_libevdev, bustype: c_int) void;
pub extern fn libevdev_get_id_version(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_set_id_version(dev: ?*struct_libevdev, version: c_int) void;
pub extern fn libevdev_get_driver_version(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_has_property(dev: ?*const struct_libevdev, prop: c_uint) c_int;
pub extern fn libevdev_enable_property(dev: ?*struct_libevdev, prop: c_uint) c_int;
pub extern fn libevdev_disable_property(dev: ?*struct_libevdev, prop: c_uint) c_int;
pub extern fn libevdev_has_event_type(dev: ?*const struct_libevdev, @"type": c_uint) c_int;
pub extern fn libevdev_has_event_code(dev: ?*const struct_libevdev, @"type": c_uint, code: c_uint) c_int;
pub extern fn libevdev_get_abs_minimum(dev: ?*const struct_libevdev, code: c_uint) c_int;
pub extern fn libevdev_get_abs_maximum(dev: ?*const struct_libevdev, code: c_uint) c_int;
pub extern fn libevdev_get_abs_fuzz(dev: ?*const struct_libevdev, code: c_uint) c_int;
pub extern fn libevdev_get_abs_flat(dev: ?*const struct_libevdev, code: c_uint) c_int;
pub extern fn libevdev_get_abs_resolution(dev: ?*const struct_libevdev, code: c_uint) c_int;
pub extern fn libevdev_get_abs_info(dev: ?*const struct_libevdev, code: c_uint) [*c]const struct_input_absinfo;
pub extern fn libevdev_get_event_value(dev: ?*const struct_libevdev, @"type": c_uint, code: c_uint) c_int;
pub extern fn libevdev_set_event_value(dev: ?*struct_libevdev, @"type": c_uint, code: c_uint, value: c_int) c_int;
pub extern fn libevdev_fetch_event_value(dev: ?*const struct_libevdev, @"type": c_uint, code: c_uint, value: [*c]c_int) c_int;
pub extern fn libevdev_get_slot_value(dev: ?*const struct_libevdev, slot: c_uint, code: c_uint) c_int;
pub extern fn libevdev_set_slot_value(dev: ?*struct_libevdev, slot: c_uint, code: c_uint, value: c_int) c_int;
pub extern fn libevdev_fetch_slot_value(dev: ?*const struct_libevdev, slot: c_uint, code: c_uint, value: [*c]c_int) c_int;
pub extern fn libevdev_get_num_slots(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_get_current_slot(dev: ?*const struct_libevdev) c_int;
pub extern fn libevdev_set_abs_minimum(dev: ?*struct_libevdev, code: c_uint, val: c_int) void;
pub extern fn libevdev_set_abs_maximum(dev: ?*struct_libevdev, code: c_uint, val: c_int) void;
pub extern fn libevdev_set_abs_fuzz(dev: ?*struct_libevdev, code: c_uint, val: c_int) void;
pub extern fn libevdev_set_abs_flat(dev: ?*struct_libevdev, code: c_uint, val: c_int) void;
pub extern fn libevdev_set_abs_resolution(dev: ?*struct_libevdev, code: c_uint, val: c_int) void;
pub extern fn libevdev_set_abs_info(dev: ?*struct_libevdev, code: c_uint, abs: [*c]const struct_input_absinfo) void;
pub extern fn libevdev_enable_event_type(dev: ?*struct_libevdev, @"type": c_uint) c_int;
pub extern fn libevdev_disable_event_type(dev: ?*struct_libevdev, @"type": c_uint) c_int;
pub extern fn libevdev_enable_event_code(dev: ?*struct_libevdev, @"type": c_uint, code: c_uint, data: ?*const anyopaque) c_int;
pub extern fn libevdev_disable_event_code(dev: ?*struct_libevdev, @"type": c_uint, code: c_uint) c_int;
pub extern fn libevdev_kernel_set_abs_info(dev: ?*struct_libevdev, code: c_uint, abs: [*c]const struct_input_absinfo) c_int;
pub const LIBEVDEV_LED_ON: c_int = 3;
pub const LIBEVDEV_LED_OFF: c_int = 4;
pub const enum_libevdev_led_value = c_uint;
pub extern fn libevdev_kernel_set_led_value(dev: ?*struct_libevdev, code: c_uint, value: enum_libevdev_led_value) c_int;
pub extern fn libevdev_kernel_set_led_values(dev: ?*struct_libevdev, ...) c_int;
pub extern fn libevdev_set_clock_id(dev: ?*struct_libevdev, clockid: c_int) c_int;
pub extern fn libevdev_event_is_type(ev: [*c]const struct_input_event, @"type": c_uint) c_int;
pub extern fn libevdev_event_is_code(ev: [*c]const struct_input_event, @"type": c_uint, code: c_uint) c_int;
pub extern fn libevdev_event_type_get_name(@"type": c_uint) [*c]const u8;
pub extern fn libevdev_event_code_get_name(@"type": c_uint, code: c_uint) [*c]const u8;
pub extern fn libevdev_event_value_get_name(@"type": c_uint, code: c_uint, value: c_int) [*c]const u8;
pub extern fn libevdev_property_get_name(prop: c_uint) [*c]const u8;
pub extern fn libevdev_event_type_get_max(@"type": c_uint) c_int;
pub extern fn libevdev_event_type_from_name(name: [*c]const u8) c_int;
pub extern fn libevdev_event_type_from_name_n(name: [*c]const u8, len: usize) c_int;
pub extern fn libevdev_event_code_from_name(@"type": c_uint, name: [*c]const u8) c_int;
pub extern fn libevdev_event_code_from_name_n(@"type": c_uint, name: [*c]const u8, len: usize) c_int;
pub extern fn libevdev_event_value_from_name(@"type": c_uint, code: c_uint, name: [*c]const u8) c_int;
pub extern fn libevdev_event_type_from_code_name(name: [*c]const u8) c_int;
pub extern fn libevdev_event_type_from_code_name_n(name: [*c]const u8, len: usize) c_int;
pub extern fn libevdev_event_code_from_code_name(name: [*c]const u8) c_int;
pub extern fn libevdev_event_code_from_code_name_n(name: [*c]const u8, len: usize) c_int;
pub extern fn libevdev_event_value_from_name_n(@"type": c_uint, code: c_uint, name: [*c]const u8, len: usize) c_int;
pub extern fn libevdev_property_from_name(name: [*c]const u8) c_int;
pub extern fn libevdev_property_from_name_n(name: [*c]const u8, len: usize) c_int;
pub extern fn libevdev_get_repeat(dev: ?*const struct_libevdev, delay: [*c]c_int, period: [*c]c_int) c_int;
pub extern fn gnu_dev_major(__dev: __dev_t) c_uint;
pub extern fn gnu_dev_minor(__dev: __dev_t) c_uint;
pub extern fn gnu_dev_makedev(__major: c_uint, __minor: c_uint) __dev_t;
pub const struct_udev = opaque {
    pub const udev_ref = __root.udev_ref;
    pub const udev_unref = __root.udev_unref;
    pub const udev_set_log_fn = __root.udev_set_log_fn;
    pub const udev_get_log_priority = __root.udev_get_log_priority;
    pub const udev_set_log_priority = __root.udev_set_log_priority;
    pub const udev_get_userdata = __root.udev_get_userdata;
    pub const udev_set_userdata = __root.udev_set_userdata;
    pub const udev_device_new_from_syspath = __root.udev_device_new_from_syspath;
    pub const udev_device_new_from_devnum = __root.udev_device_new_from_devnum;
    pub const udev_device_new_from_subsystem_sysname = __root.udev_device_new_from_subsystem_sysname;
    pub const udev_device_new_from_device_id = __root.udev_device_new_from_device_id;
    pub const udev_device_new_from_environment = __root.udev_device_new_from_environment;
    pub const udev_monitor_new_from_netlink = __root.udev_monitor_new_from_netlink;
    pub const udev_enumerate_new = __root.udev_enumerate_new;
    pub const udev_queue_new = __root.udev_queue_new;
    pub const udev_hwdb_new = __root.udev_hwdb_new;
    pub const ref = __root.udev_ref;
    pub const unref = __root.udev_unref;
    pub const set_log_fn = __root.udev_set_log_fn;
    pub const get_log_priority = __root.udev_get_log_priority;
    pub const set_log_priority = __root.udev_set_log_priority;
    pub const get_userdata = __root.udev_get_userdata;
    pub const set_userdata = __root.udev_set_userdata;
    pub const device_new_from_syspath = __root.udev_device_new_from_syspath;
    pub const device_new_from_devnum = __root.udev_device_new_from_devnum;
    pub const device_new_from_subsystem_sysname = __root.udev_device_new_from_subsystem_sysname;
    pub const device_new_from_device_id = __root.udev_device_new_from_device_id;
    pub const device_new_from_environment = __root.udev_device_new_from_environment;
    pub const monitor_new_from_netlink = __root.udev_monitor_new_from_netlink;
    pub const enumerate_new = __root.udev_enumerate_new;
    pub const queue_new = __root.udev_queue_new;
    pub const hwdb_new = __root.udev_hwdb_new;
};
pub extern fn udev_ref(udev: ?*struct_udev) ?*struct_udev;
pub extern fn udev_unref(udev: ?*struct_udev) ?*struct_udev;
pub extern fn udev_new() ?*struct_udev;
pub extern fn udev_set_log_fn(udev: ?*struct_udev, log_fn: ?*const fn (udev: ?*struct_udev, priority: c_int, file: [*c]const u8, line: c_int, @"fn": [*c]const u8, format: [*c]const u8, args: [*c]struct___va_list_tag_3) callconv(.c) void) void;
pub extern fn udev_get_log_priority(udev: ?*struct_udev) c_int;
pub extern fn udev_set_log_priority(udev: ?*struct_udev, priority: c_int) void;
pub extern fn udev_get_userdata(udev: ?*struct_udev) ?*anyopaque;
pub extern fn udev_set_userdata(udev: ?*struct_udev, userdata: ?*anyopaque) void;
pub const struct_udev_list_entry = opaque {
    pub const udev_list_entry_get_next = __root.udev_list_entry_get_next;
    pub const udev_list_entry_get_by_name = __root.udev_list_entry_get_by_name;
    pub const udev_list_entry_get_name = __root.udev_list_entry_get_name;
    pub const udev_list_entry_get_value = __root.udev_list_entry_get_value;
    pub const get_next = __root.udev_list_entry_get_next;
    pub const get_by_name = __root.udev_list_entry_get_by_name;
    pub const get_name = __root.udev_list_entry_get_name;
    pub const get_value = __root.udev_list_entry_get_value;
};
pub extern fn udev_list_entry_get_next(list_entry: ?*struct_udev_list_entry) ?*struct_udev_list_entry;
pub extern fn udev_list_entry_get_by_name(list_entry: ?*struct_udev_list_entry, name: [*c]const u8) ?*struct_udev_list_entry;
pub extern fn udev_list_entry_get_name(list_entry: ?*struct_udev_list_entry) [*c]const u8;
pub extern fn udev_list_entry_get_value(list_entry: ?*struct_udev_list_entry) [*c]const u8;
pub const struct_udev_device = opaque {
    pub const udev_device_ref = __root.udev_device_ref;
    pub const udev_device_unref = __root.udev_device_unref;
    pub const udev_device_get_udev = __root.udev_device_get_udev;
    pub const udev_device_get_parent = __root.udev_device_get_parent;
    pub const udev_device_get_parent_with_subsystem_devtype = __root.udev_device_get_parent_with_subsystem_devtype;
    pub const udev_device_get_devpath = __root.udev_device_get_devpath;
    pub const udev_device_get_subsystem = __root.udev_device_get_subsystem;
    pub const udev_device_get_devtype = __root.udev_device_get_devtype;
    pub const udev_device_get_syspath = __root.udev_device_get_syspath;
    pub const udev_device_get_sysname = __root.udev_device_get_sysname;
    pub const udev_device_get_sysnum = __root.udev_device_get_sysnum;
    pub const udev_device_get_devnode = __root.udev_device_get_devnode;
    pub const udev_device_get_is_initialized = __root.udev_device_get_is_initialized;
    pub const udev_device_get_devlinks_list_entry = __root.udev_device_get_devlinks_list_entry;
    pub const udev_device_get_properties_list_entry = __root.udev_device_get_properties_list_entry;
    pub const udev_device_get_tags_list_entry = __root.udev_device_get_tags_list_entry;
    pub const udev_device_get_current_tags_list_entry = __root.udev_device_get_current_tags_list_entry;
    pub const udev_device_get_sysattr_list_entry = __root.udev_device_get_sysattr_list_entry;
    pub const udev_device_get_property_value = __root.udev_device_get_property_value;
    pub const udev_device_get_driver = __root.udev_device_get_driver;
    pub const udev_device_get_devnum = __root.udev_device_get_devnum;
    pub const udev_device_get_action = __root.udev_device_get_action;
    pub const udev_device_get_seqnum = __root.udev_device_get_seqnum;
    pub const udev_device_get_usec_since_initialized = __root.udev_device_get_usec_since_initialized;
    pub const udev_device_get_sysattr_value = __root.udev_device_get_sysattr_value;
    pub const udev_device_set_sysattr_value = __root.udev_device_set_sysattr_value;
    pub const udev_device_has_tag = __root.udev_device_has_tag;
    pub const udev_device_has_current_tag = __root.udev_device_has_current_tag;
    pub const ref = __root.udev_device_ref;
    pub const unref = __root.udev_device_unref;
    pub const get_udev = __root.udev_device_get_udev;
    pub const get_parent = __root.udev_device_get_parent;
    pub const get_parent_with_subsystem_devtype = __root.udev_device_get_parent_with_subsystem_devtype;
    pub const get_devpath = __root.udev_device_get_devpath;
    pub const get_subsystem = __root.udev_device_get_subsystem;
    pub const get_devtype = __root.udev_device_get_devtype;
    pub const get_syspath = __root.udev_device_get_syspath;
    pub const get_sysname = __root.udev_device_get_sysname;
    pub const get_sysnum = __root.udev_device_get_sysnum;
    pub const get_devnode = __root.udev_device_get_devnode;
    pub const get_is_initialized = __root.udev_device_get_is_initialized;
    pub const get_devlinks_list_entry = __root.udev_device_get_devlinks_list_entry;
    pub const get_properties_list_entry = __root.udev_device_get_properties_list_entry;
    pub const get_tags_list_entry = __root.udev_device_get_tags_list_entry;
    pub const get_current_tags_list_entry = __root.udev_device_get_current_tags_list_entry;
    pub const get_sysattr_list_entry = __root.udev_device_get_sysattr_list_entry;
    pub const get_property_value = __root.udev_device_get_property_value;
    pub const get_driver = __root.udev_device_get_driver;
    pub const get_devnum = __root.udev_device_get_devnum;
    pub const get_action = __root.udev_device_get_action;
    pub const get_seqnum = __root.udev_device_get_seqnum;
    pub const get_usec_since_initialized = __root.udev_device_get_usec_since_initialized;
    pub const get_sysattr_value = __root.udev_device_get_sysattr_value;
    pub const set_sysattr_value = __root.udev_device_set_sysattr_value;
    pub const has_tag = __root.udev_device_has_tag;
    pub const has_current_tag = __root.udev_device_has_current_tag;
};
pub extern fn udev_device_ref(udev_device: ?*struct_udev_device) ?*struct_udev_device;
pub extern fn udev_device_unref(udev_device: ?*struct_udev_device) ?*struct_udev_device;
pub extern fn udev_device_get_udev(udev_device: ?*struct_udev_device) ?*struct_udev;
pub extern fn udev_device_new_from_syspath(udev: ?*struct_udev, syspath: [*c]const u8) ?*struct_udev_device;
pub extern fn udev_device_new_from_devnum(udev: ?*struct_udev, @"type": u8, devnum: dev_t) ?*struct_udev_device;
pub extern fn udev_device_new_from_subsystem_sysname(udev: ?*struct_udev, subsystem: [*c]const u8, sysname: [*c]const u8) ?*struct_udev_device;
pub extern fn udev_device_new_from_device_id(udev: ?*struct_udev, id: [*c]const u8) ?*struct_udev_device;
pub extern fn udev_device_new_from_environment(udev: ?*struct_udev) ?*struct_udev_device;
pub extern fn udev_device_get_parent(udev_device: ?*struct_udev_device) ?*struct_udev_device;
pub extern fn udev_device_get_parent_with_subsystem_devtype(udev_device: ?*struct_udev_device, subsystem: [*c]const u8, devtype: [*c]const u8) ?*struct_udev_device;
pub extern fn udev_device_get_devpath(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_subsystem(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_devtype(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_syspath(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_sysname(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_sysnum(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_devnode(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_is_initialized(udev_device: ?*struct_udev_device) c_int;
pub extern fn udev_device_get_devlinks_list_entry(udev_device: ?*struct_udev_device) ?*struct_udev_list_entry;
pub extern fn udev_device_get_properties_list_entry(udev_device: ?*struct_udev_device) ?*struct_udev_list_entry;
pub extern fn udev_device_get_tags_list_entry(udev_device: ?*struct_udev_device) ?*struct_udev_list_entry;
pub extern fn udev_device_get_current_tags_list_entry(udev_device: ?*struct_udev_device) ?*struct_udev_list_entry;
pub extern fn udev_device_get_sysattr_list_entry(udev_device: ?*struct_udev_device) ?*struct_udev_list_entry;
pub extern fn udev_device_get_property_value(udev_device: ?*struct_udev_device, key: [*c]const u8) [*c]const u8;
pub extern fn udev_device_get_driver(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_devnum(udev_device: ?*struct_udev_device) dev_t;
pub extern fn udev_device_get_action(udev_device: ?*struct_udev_device) [*c]const u8;
pub extern fn udev_device_get_seqnum(udev_device: ?*struct_udev_device) c_ulonglong;
pub extern fn udev_device_get_usec_since_initialized(udev_device: ?*struct_udev_device) c_ulonglong;
pub extern fn udev_device_get_sysattr_value(udev_device: ?*struct_udev_device, sysattr: [*c]const u8) [*c]const u8;
pub extern fn udev_device_set_sysattr_value(udev_device: ?*struct_udev_device, sysattr: [*c]const u8, value: [*c]const u8) c_int;
pub extern fn udev_device_has_tag(udev_device: ?*struct_udev_device, tag: [*c]const u8) c_int;
pub extern fn udev_device_has_current_tag(udev_device: ?*struct_udev_device, tag: [*c]const u8) c_int;
pub const struct_udev_monitor = opaque {
    pub const udev_monitor_ref = __root.udev_monitor_ref;
    pub const udev_monitor_unref = __root.udev_monitor_unref;
    pub const udev_monitor_get_udev = __root.udev_monitor_get_udev;
    pub const udev_monitor_enable_receiving = __root.udev_monitor_enable_receiving;
    pub const udev_monitor_set_receive_buffer_size = __root.udev_monitor_set_receive_buffer_size;
    pub const udev_monitor_get_fd = __root.udev_monitor_get_fd;
    pub const udev_monitor_receive_device = __root.udev_monitor_receive_device;
    pub const udev_monitor_filter_add_match_subsystem_devtype = __root.udev_monitor_filter_add_match_subsystem_devtype;
    pub const udev_monitor_filter_add_match_tag = __root.udev_monitor_filter_add_match_tag;
    pub const udev_monitor_filter_update = __root.udev_monitor_filter_update;
    pub const udev_monitor_filter_remove = __root.udev_monitor_filter_remove;
    pub const ref = __root.udev_monitor_ref;
    pub const unref = __root.udev_monitor_unref;
    pub const get_udev = __root.udev_monitor_get_udev;
    pub const enable_receiving = __root.udev_monitor_enable_receiving;
    pub const set_receive_buffer_size = __root.udev_monitor_set_receive_buffer_size;
    pub const get_fd = __root.udev_monitor_get_fd;
    pub const receive_device = __root.udev_monitor_receive_device;
    pub const filter_add_match_subsystem_devtype = __root.udev_monitor_filter_add_match_subsystem_devtype;
    pub const filter_add_match_tag = __root.udev_monitor_filter_add_match_tag;
    pub const filter_update = __root.udev_monitor_filter_update;
    pub const filter_remove = __root.udev_monitor_filter_remove;
};
pub extern fn udev_monitor_ref(udev_monitor: ?*struct_udev_monitor) ?*struct_udev_monitor;
pub extern fn udev_monitor_unref(udev_monitor: ?*struct_udev_monitor) ?*struct_udev_monitor;
pub extern fn udev_monitor_get_udev(udev_monitor: ?*struct_udev_monitor) ?*struct_udev;
pub extern fn udev_monitor_new_from_netlink(udev: ?*struct_udev, name: [*c]const u8) ?*struct_udev_monitor;
pub extern fn udev_monitor_enable_receiving(udev_monitor: ?*struct_udev_monitor) c_int;
pub extern fn udev_monitor_set_receive_buffer_size(udev_monitor: ?*struct_udev_monitor, size: c_int) c_int;
pub extern fn udev_monitor_get_fd(udev_monitor: ?*struct_udev_monitor) c_int;
pub extern fn udev_monitor_receive_device(udev_monitor: ?*struct_udev_monitor) ?*struct_udev_device;
pub extern fn udev_monitor_filter_add_match_subsystem_devtype(udev_monitor: ?*struct_udev_monitor, subsystem: [*c]const u8, devtype: [*c]const u8) c_int;
pub extern fn udev_monitor_filter_add_match_tag(udev_monitor: ?*struct_udev_monitor, tag: [*c]const u8) c_int;
pub extern fn udev_monitor_filter_update(udev_monitor: ?*struct_udev_monitor) c_int;
pub extern fn udev_monitor_filter_remove(udev_monitor: ?*struct_udev_monitor) c_int;
pub const struct_udev_enumerate = opaque {
    pub const udev_enumerate_ref = __root.udev_enumerate_ref;
    pub const udev_enumerate_unref = __root.udev_enumerate_unref;
    pub const udev_enumerate_get_udev = __root.udev_enumerate_get_udev;
    pub const udev_enumerate_add_match_subsystem = __root.udev_enumerate_add_match_subsystem;
    pub const udev_enumerate_add_nomatch_subsystem = __root.udev_enumerate_add_nomatch_subsystem;
    pub const udev_enumerate_add_match_sysattr = __root.udev_enumerate_add_match_sysattr;
    pub const udev_enumerate_add_nomatch_sysattr = __root.udev_enumerate_add_nomatch_sysattr;
    pub const udev_enumerate_add_match_property = __root.udev_enumerate_add_match_property;
    pub const udev_enumerate_add_match_sysname = __root.udev_enumerate_add_match_sysname;
    pub const udev_enumerate_add_match_tag = __root.udev_enumerate_add_match_tag;
    pub const udev_enumerate_add_match_parent = __root.udev_enumerate_add_match_parent;
    pub const udev_enumerate_add_match_is_initialized = __root.udev_enumerate_add_match_is_initialized;
    pub const udev_enumerate_add_syspath = __root.udev_enumerate_add_syspath;
    pub const udev_enumerate_scan_devices = __root.udev_enumerate_scan_devices;
    pub const udev_enumerate_scan_subsystems = __root.udev_enumerate_scan_subsystems;
    pub const udev_enumerate_get_list_entry = __root.udev_enumerate_get_list_entry;
    pub const ref = __root.udev_enumerate_ref;
    pub const unref = __root.udev_enumerate_unref;
    pub const get_udev = __root.udev_enumerate_get_udev;
    pub const add_match_subsystem = __root.udev_enumerate_add_match_subsystem;
    pub const add_nomatch_subsystem = __root.udev_enumerate_add_nomatch_subsystem;
    pub const add_match_sysattr = __root.udev_enumerate_add_match_sysattr;
    pub const add_nomatch_sysattr = __root.udev_enumerate_add_nomatch_sysattr;
    pub const add_match_property = __root.udev_enumerate_add_match_property;
    pub const add_match_sysname = __root.udev_enumerate_add_match_sysname;
    pub const add_match_tag = __root.udev_enumerate_add_match_tag;
    pub const add_match_parent = __root.udev_enumerate_add_match_parent;
    pub const add_match_is_initialized = __root.udev_enumerate_add_match_is_initialized;
    pub const add_syspath = __root.udev_enumerate_add_syspath;
    pub const scan_devices = __root.udev_enumerate_scan_devices;
    pub const scan_subsystems = __root.udev_enumerate_scan_subsystems;
    pub const get_list_entry = __root.udev_enumerate_get_list_entry;
};
pub extern fn udev_enumerate_ref(udev_enumerate: ?*struct_udev_enumerate) ?*struct_udev_enumerate;
pub extern fn udev_enumerate_unref(udev_enumerate: ?*struct_udev_enumerate) ?*struct_udev_enumerate;
pub extern fn udev_enumerate_get_udev(udev_enumerate: ?*struct_udev_enumerate) ?*struct_udev;
pub extern fn udev_enumerate_new(udev: ?*struct_udev) ?*struct_udev_enumerate;
pub extern fn udev_enumerate_add_match_subsystem(udev_enumerate: ?*struct_udev_enumerate, subsystem: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_nomatch_subsystem(udev_enumerate: ?*struct_udev_enumerate, subsystem: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_match_sysattr(udev_enumerate: ?*struct_udev_enumerate, sysattr: [*c]const u8, value: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_nomatch_sysattr(udev_enumerate: ?*struct_udev_enumerate, sysattr: [*c]const u8, value: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_match_property(udev_enumerate: ?*struct_udev_enumerate, property: [*c]const u8, value: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_match_sysname(udev_enumerate: ?*struct_udev_enumerate, sysname: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_match_tag(udev_enumerate: ?*struct_udev_enumerate, tag: [*c]const u8) c_int;
pub extern fn udev_enumerate_add_match_parent(udev_enumerate: ?*struct_udev_enumerate, parent: ?*struct_udev_device) c_int;
pub extern fn udev_enumerate_add_match_is_initialized(udev_enumerate: ?*struct_udev_enumerate) c_int;
pub extern fn udev_enumerate_add_syspath(udev_enumerate: ?*struct_udev_enumerate, syspath: [*c]const u8) c_int;
pub extern fn udev_enumerate_scan_devices(udev_enumerate: ?*struct_udev_enumerate) c_int;
pub extern fn udev_enumerate_scan_subsystems(udev_enumerate: ?*struct_udev_enumerate) c_int;
pub extern fn udev_enumerate_get_list_entry(udev_enumerate: ?*struct_udev_enumerate) ?*struct_udev_list_entry;
pub const struct_udev_queue = opaque {
    pub const udev_queue_ref = __root.udev_queue_ref;
    pub const udev_queue_unref = __root.udev_queue_unref;
    pub const udev_queue_get_udev = __root.udev_queue_get_udev;
    pub const udev_queue_get_kernel_seqnum = __root.udev_queue_get_kernel_seqnum;
    pub const udev_queue_get_udev_seqnum = __root.udev_queue_get_udev_seqnum;
    pub const udev_queue_get_udev_is_active = __root.udev_queue_get_udev_is_active;
    pub const udev_queue_get_queue_is_empty = __root.udev_queue_get_queue_is_empty;
    pub const udev_queue_get_seqnum_is_finished = __root.udev_queue_get_seqnum_is_finished;
    pub const udev_queue_get_seqnum_sequence_is_finished = __root.udev_queue_get_seqnum_sequence_is_finished;
    pub const udev_queue_get_fd = __root.udev_queue_get_fd;
    pub const udev_queue_flush = __root.udev_queue_flush;
    pub const udev_queue_get_queued_list_entry = __root.udev_queue_get_queued_list_entry;
    pub const ref = __root.udev_queue_ref;
    pub const unref = __root.udev_queue_unref;
    pub const get_udev = __root.udev_queue_get_udev;
    pub const get_kernel_seqnum = __root.udev_queue_get_kernel_seqnum;
    pub const get_udev_seqnum = __root.udev_queue_get_udev_seqnum;
    pub const get_udev_is_active = __root.udev_queue_get_udev_is_active;
    pub const get_queue_is_empty = __root.udev_queue_get_queue_is_empty;
    pub const get_seqnum_is_finished = __root.udev_queue_get_seqnum_is_finished;
    pub const get_seqnum_sequence_is_finished = __root.udev_queue_get_seqnum_sequence_is_finished;
    pub const get_fd = __root.udev_queue_get_fd;
    pub const flush = __root.udev_queue_flush;
    pub const get_queued_list_entry = __root.udev_queue_get_queued_list_entry;
};
pub extern fn udev_queue_ref(udev_queue: ?*struct_udev_queue) ?*struct_udev_queue;
pub extern fn udev_queue_unref(udev_queue: ?*struct_udev_queue) ?*struct_udev_queue;
pub extern fn udev_queue_get_udev(udev_queue: ?*struct_udev_queue) ?*struct_udev;
pub extern fn udev_queue_new(udev: ?*struct_udev) ?*struct_udev_queue;
pub extern fn udev_queue_get_kernel_seqnum(udev_queue: ?*struct_udev_queue) c_ulonglong;
pub extern fn udev_queue_get_udev_seqnum(udev_queue: ?*struct_udev_queue) c_ulonglong;
pub extern fn udev_queue_get_udev_is_active(udev_queue: ?*struct_udev_queue) c_int;
pub extern fn udev_queue_get_queue_is_empty(udev_queue: ?*struct_udev_queue) c_int;
pub extern fn udev_queue_get_seqnum_is_finished(udev_queue: ?*struct_udev_queue, seqnum: c_ulonglong) c_int;
pub extern fn udev_queue_get_seqnum_sequence_is_finished(udev_queue: ?*struct_udev_queue, start: c_ulonglong, end: c_ulonglong) c_int;
pub extern fn udev_queue_get_fd(udev_queue: ?*struct_udev_queue) c_int;
pub extern fn udev_queue_flush(udev_queue: ?*struct_udev_queue) c_int;
pub extern fn udev_queue_get_queued_list_entry(udev_queue: ?*struct_udev_queue) ?*struct_udev_list_entry;
pub const struct_udev_hwdb = opaque {
    pub const udev_hwdb_ref = __root.udev_hwdb_ref;
    pub const udev_hwdb_unref = __root.udev_hwdb_unref;
    pub const udev_hwdb_get_properties_list_entry = __root.udev_hwdb_get_properties_list_entry;
    pub const ref = __root.udev_hwdb_ref;
    pub const unref = __root.udev_hwdb_unref;
    pub const get_properties_list_entry = __root.udev_hwdb_get_properties_list_entry;
};
pub extern fn udev_hwdb_new(udev: ?*struct_udev) ?*struct_udev_hwdb;
pub extern fn udev_hwdb_ref(hwdb: ?*struct_udev_hwdb) ?*struct_udev_hwdb;
pub extern fn udev_hwdb_unref(hwdb: ?*struct_udev_hwdb) ?*struct_udev_hwdb;
pub extern fn udev_hwdb_get_properties_list_entry(hwdb: ?*struct_udev_hwdb, modalias: [*c]const u8, flags: c_uint) ?*struct_udev_list_entry;
pub extern fn udev_util_encode_string(str: [*c]const u8, str_enc: [*c]u8, len: usize) c_int;
pub const int_least8_t = __int_least8_t;
pub const int_least16_t = __int_least16_t;
pub const int_least32_t = __int_least32_t;
pub const int_least64_t = __int_least64_t;
pub const uint_least8_t = __uint_least8_t;
pub const uint_least16_t = __uint_least16_t;
pub const uint_least32_t = __uint_least32_t;
pub const uint_least64_t = __uint_least64_t;
pub const int_fast8_t = i8;
pub const int_fast16_t = c_long;
pub const int_fast32_t = c_long;
pub const int_fast64_t = c_long;
pub const uint_fast8_t = u8;
pub const uint_fast16_t = c_ulong;
pub const uint_fast32_t = c_ulong;
pub const uint_fast64_t = c_ulong;
pub const intmax_t = __intmax_t;
pub const uintmax_t = __uintmax_t;
pub const div_t = extern struct {
    quot: c_int,
    rem: c_int,
};
pub const ldiv_t = extern struct {
    quot: c_long,
    rem: c_long,
};
pub const lldiv_t = extern struct {
    quot: c_longlong,
    rem: c_longlong,
};
pub extern fn __ctype_get_mb_cur_max() usize;
pub extern fn atof(__nptr: [*c]const u8) f64;
pub extern fn atoi(__nptr: [*c]const u8) c_int;
pub extern fn atol(__nptr: [*c]const u8) c_long;
pub extern fn atoll(__nptr: [*c]const u8) c_longlong;
pub extern fn strtod(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) f64;
pub extern fn strtof(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) f32;
pub extern fn strtold(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) c_longdouble;
pub extern fn strtol(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_long;
pub extern fn strtoul(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulong;
pub extern fn strtoq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtouq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn strtoll(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtoull(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn l64a(__n: c_long) [*c]u8;
pub extern fn a64l(__s: [*c]const u8) c_long;
pub extern fn random() c_long;
pub extern fn srandom(__seed: c_uint) void;
pub extern fn initstate(__seed: c_uint, __statebuf: [*c]u8, __statelen: usize) [*c]u8;
pub extern fn setstate(__statebuf: [*c]u8) [*c]u8;
pub const struct_random_data = extern struct {
    fptr: [*c]i32,
    rptr: [*c]i32,
    state: [*c]i32,
    rand_type: c_int,
    rand_deg: c_int,
    rand_sep: c_int,
    end_ptr: [*c]i32,
    pub const random_r = __root.random_r;
    pub const r = __root.random_r;
};
pub extern fn random_r(noalias __buf: [*c]struct_random_data, noalias __result: [*c]i32) c_int;
pub extern fn srandom_r(__seed: c_uint, __buf: [*c]struct_random_data) c_int;
pub extern fn initstate_r(__seed: c_uint, noalias __statebuf: [*c]u8, __statelen: usize, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn setstate_r(noalias __statebuf: [*c]u8, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn rand() c_int;
pub extern fn srand(__seed: c_uint) void;
pub extern fn rand_r(__seed: [*c]c_uint) c_int;
pub extern fn drand48() f64;
pub extern fn erand48(__xsubi: [*c]c_ushort) f64;
pub extern fn lrand48() c_long;
pub extern fn nrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn mrand48() c_long;
pub extern fn jrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn srand48(__seedval: c_long) void;
pub extern fn seed48(__seed16v: [*c]c_ushort) [*c]c_ushort;
pub extern fn lcong48(__param: [*c]c_ushort) void;
pub const struct_drand48_data = extern struct {
    __x: [3]c_ushort,
    __old_x: [3]c_ushort,
    __c: c_ushort,
    __init: c_ushort,
    __a: c_ulonglong,
    pub const drand48_r = __root.drand48_r;
    pub const lrand48_r = __root.lrand48_r;
    pub const mrand48_r = __root.mrand48_r;
    pub const r = __root.drand48_r;
};
pub extern fn drand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn erand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn lrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn nrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn mrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn jrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn srand48_r(__seedval: c_long, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn seed48_r(__seed16v: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn lcong48_r(__param: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn arc4random() __uint32_t;
pub extern fn arc4random_buf(__buf: ?*anyopaque, __size: usize) void;
pub extern fn arc4random_uniform(__upper_bound: __uint32_t) __uint32_t;
pub extern fn malloc(__size: usize) ?*anyopaque;
pub extern fn calloc(__nmemb: usize, __size: usize) ?*anyopaque;
pub extern fn realloc(__ptr: ?*anyopaque, __size: usize) ?*anyopaque;
pub extern fn free(__ptr: ?*anyopaque) void;
pub extern fn reallocarray(__ptr: ?*anyopaque, __nmemb: usize, __size: usize) ?*anyopaque;
pub extern fn alloca(__size: usize) ?*anyopaque;
pub extern fn valloc(__size: usize) ?*anyopaque;
pub extern fn posix_memalign(__memptr: [*c]?*anyopaque, __alignment: usize, __size: usize) c_int;
pub extern fn aligned_alloc(__alignment: usize, __size: usize) ?*anyopaque;
pub extern fn abort() noreturn;
pub extern fn atexit(__func: ?*const fn () callconv(.c) void) c_int;
pub extern fn at_quick_exit(__func: ?*const fn () callconv(.c) void) c_int;
pub extern fn on_exit(__func: ?*const fn (__status: c_int, __arg: ?*anyopaque) callconv(.c) void, __arg: ?*anyopaque) c_int;
pub extern fn exit(__status: c_int) noreturn;
pub extern fn quick_exit(__status: c_int) noreturn;
pub extern fn _Exit(__status: c_int) noreturn;
pub extern fn getenv(__name: [*c]const u8) [*c]u8;
pub extern fn putenv(__string: [*c]u8) c_int;
pub extern fn setenv(__name: [*c]const u8, __value: [*c]const u8, __replace: c_int) c_int;
pub extern fn unsetenv(__name: [*c]const u8) c_int;
pub extern fn clearenv() c_int;
pub extern fn mktemp(__template: [*c]u8) [*c]u8;
pub extern fn mkstemp(__template: [*c]u8) c_int;
pub extern fn mkstemps(__template: [*c]u8, __suffixlen: c_int) c_int;
pub extern fn mkdtemp(__template: [*c]u8) [*c]u8;
pub extern fn system(__command: [*c]const u8) c_int;
pub extern fn realpath(noalias __name: [*c]const u8, noalias __resolved: [*c]u8) [*c]u8;
pub const __compar_fn_t = ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int;
pub extern fn bsearch(__key: ?*const anyopaque, __base: ?*const anyopaque, __nmemb: usize, __size: usize, __compar: __compar_fn_t) ?*anyopaque;
pub extern fn qsort(__base: ?*anyopaque, __nmemb: usize, __size: usize, __compar: __compar_fn_t) void;
pub extern fn abs(__x: c_int) c_int;
pub extern fn labs(__x: c_long) c_long;
pub extern fn llabs(__x: c_longlong) c_longlong;
pub extern fn div(__numer: c_int, __denom: c_int) div_t;
pub extern fn ldiv(__numer: c_long, __denom: c_long) ldiv_t;
pub extern fn lldiv(__numer: c_longlong, __denom: c_longlong) lldiv_t;
pub extern fn ecvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn fcvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn gcvt(__value: f64, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn qecvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qfcvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qgcvt(__value: c_longdouble, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn ecvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn fcvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qecvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qfcvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn mblen(__s: [*c]const u8, __n: usize) c_int;
pub extern fn mbtowc(noalias __pwc: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) c_int;
pub extern fn wctomb(__s: [*c]u8, __wchar: wchar_t) c_int;
pub extern fn mbstowcs(noalias __pwcs: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) usize;
pub extern fn wcstombs(noalias __s: [*c]u8, noalias __pwcs: [*c]const wchar_t, __n: usize) usize;
pub extern fn rpmatch(__response: [*c]const u8) c_int;
pub extern fn getsubopt(noalias __optionp: [*c][*c]u8, noalias __tokens: [*c]const [*c]u8, noalias __valuep: [*c][*c]u8) c_int;
pub extern fn getloadavg(__loadavg: [*c]f64, __nelem: c_int) c_int;
pub const struct_libinput = opaque {
    pub const libinput_udev_assign_seat = __root.libinput_udev_assign_seat;
    pub const libinput_path_add_device = __root.libinput_path_add_device;
    pub const libinput_plugin_system_append_path = __root.libinput_plugin_system_append_path;
    pub const libinput_plugin_system_append_default_paths = __root.libinput_plugin_system_append_default_paths;
    pub const libinput_plugin_system_load_plugins = __root.libinput_plugin_system_load_plugins;
    pub const libinput_get_fd = __root.libinput_get_fd;
    pub const libinput_dispatch = __root.libinput_dispatch;
    pub const libinput_get_event = __root.libinput_get_event;
    pub const libinput_next_event_type = __root.libinput_next_event_type;
    pub const libinput_set_user_data = __root.libinput_set_user_data;
    pub const libinput_get_user_data = __root.libinput_get_user_data;
    pub const libinput_resume = __root.libinput_resume;
    pub const libinput_suspend = __root.libinput_suspend;
    pub const libinput_ref = __root.libinput_ref;
    pub const libinput_unref = __root.libinput_unref;
    pub const libinput_log_set_priority = __root.libinput_log_set_priority;
    pub const libinput_log_get_priority = __root.libinput_log_get_priority;
    pub const libinput_log_set_handler = __root.libinput_log_set_handler;
    pub const udev_assign_seat = __root.libinput_udev_assign_seat;
    pub const path_add_device = __root.libinput_path_add_device;
    pub const plugin_system_append_path = __root.libinput_plugin_system_append_path;
    pub const plugin_system_append_default_paths = __root.libinput_plugin_system_append_default_paths;
    pub const plugin_system_load_plugins = __root.libinput_plugin_system_load_plugins;
    pub const get_fd = __root.libinput_get_fd;
    pub const dispatch = __root.libinput_dispatch;
    pub const get_event = __root.libinput_get_event;
    pub const next_event_type = __root.libinput_next_event_type;
    pub const set_user_data = __root.libinput_set_user_data;
    pub const get_user_data = __root.libinput_get_user_data;
    pub const @"resume" = __root.libinput_resume;
    pub const @"suspend" = __root.libinput_suspend;
    pub const ref = __root.libinput_ref;
    pub const unref = __root.libinput_unref;
    pub const log_set_priority = __root.libinput_log_set_priority;
    pub const log_get_priority = __root.libinput_log_get_priority;
    pub const log_set_handler = __root.libinput_log_set_handler;
};
pub const struct_libinput_device = opaque {
    pub const libinput_device_tablet_pad_get_num_mode_groups = __root.libinput_device_tablet_pad_get_num_mode_groups;
    pub const libinput_device_tablet_pad_get_mode_group = __root.libinput_device_tablet_pad_get_mode_group;
    pub const libinput_path_remove_device = __root.libinput_path_remove_device;
    pub const libinput_device_ref = __root.libinput_device_ref;
    pub const libinput_device_unref = __root.libinput_device_unref;
    pub const libinput_device_set_user_data = __root.libinput_device_set_user_data;
    pub const libinput_device_get_user_data = __root.libinput_device_get_user_data;
    pub const libinput_device_get_context = __root.libinput_device_get_context;
    pub const libinput_device_get_device_group = __root.libinput_device_get_device_group;
    pub const libinput_device_get_sysname = __root.libinput_device_get_sysname;
    pub const libinput_device_get_name = __root.libinput_device_get_name;
    pub const libinput_device_get_id_bustype = __root.libinput_device_get_id_bustype;
    pub const libinput_device_get_id_product = __root.libinput_device_get_id_product;
    pub const libinput_device_get_id_vendor = __root.libinput_device_get_id_vendor;
    pub const libinput_device_get_output_name = __root.libinput_device_get_output_name;
    pub const libinput_device_get_seat = __root.libinput_device_get_seat;
    pub const libinput_device_set_seat_logical_name = __root.libinput_device_set_seat_logical_name;
    pub const libinput_device_get_udev_device = __root.libinput_device_get_udev_device;
    pub const libinput_device_led_update = __root.libinput_device_led_update;
    pub const libinput_device_has_capability = __root.libinput_device_has_capability;
    pub const libinput_device_get_size = __root.libinput_device_get_size;
    pub const libinput_device_pointer_has_button = __root.libinput_device_pointer_has_button;
    pub const libinput_device_keyboard_has_key = __root.libinput_device_keyboard_has_key;
    pub const libinput_device_touch_get_touch_count = __root.libinput_device_touch_get_touch_count;
    pub const libinput_device_switch_has_switch = __root.libinput_device_switch_has_switch;
    pub const libinput_device_tablet_pad_get_num_buttons = __root.libinput_device_tablet_pad_get_num_buttons;
    pub const libinput_device_tablet_pad_get_num_dials = __root.libinput_device_tablet_pad_get_num_dials;
    pub const libinput_device_tablet_pad_get_num_rings = __root.libinput_device_tablet_pad_get_num_rings;
    pub const libinput_device_tablet_pad_get_num_strips = __root.libinput_device_tablet_pad_get_num_strips;
    pub const libinput_device_tablet_pad_has_key = __root.libinput_device_tablet_pad_has_key;
    pub const libinput_device_config_tap_get_finger_count = __root.libinput_device_config_tap_get_finger_count;
    pub const libinput_device_config_tap_set_enabled = __root.libinput_device_config_tap_set_enabled;
    pub const libinput_device_config_tap_get_enabled = __root.libinput_device_config_tap_get_enabled;
    pub const libinput_device_config_tap_get_default_enabled = __root.libinput_device_config_tap_get_default_enabled;
    pub const libinput_device_config_tap_set_button_map = __root.libinput_device_config_tap_set_button_map;
    pub const libinput_device_config_tap_get_button_map = __root.libinput_device_config_tap_get_button_map;
    pub const libinput_device_config_tap_get_default_button_map = __root.libinput_device_config_tap_get_default_button_map;
    pub const libinput_device_config_tap_set_drag_enabled = __root.libinput_device_config_tap_set_drag_enabled;
    pub const libinput_device_config_tap_get_drag_enabled = __root.libinput_device_config_tap_get_drag_enabled;
    pub const libinput_device_config_tap_get_default_drag_enabled = __root.libinput_device_config_tap_get_default_drag_enabled;
    pub const libinput_device_config_tap_set_drag_lock_enabled = __root.libinput_device_config_tap_set_drag_lock_enabled;
    pub const libinput_device_config_tap_get_drag_lock_enabled = __root.libinput_device_config_tap_get_drag_lock_enabled;
    pub const libinput_device_config_tap_get_default_drag_lock_enabled = __root.libinput_device_config_tap_get_default_drag_lock_enabled;
    pub const libinput_device_config_3fg_drag_get_finger_count = __root.libinput_device_config_3fg_drag_get_finger_count;
    pub const libinput_device_config_3fg_drag_set_enabled = __root.libinput_device_config_3fg_drag_set_enabled;
    pub const libinput_device_config_3fg_drag_get_enabled = __root.libinput_device_config_3fg_drag_get_enabled;
    pub const libinput_device_config_3fg_drag_get_default_enabled = __root.libinput_device_config_3fg_drag_get_default_enabled;
    pub const libinput_device_config_calibration_has_matrix = __root.libinput_device_config_calibration_has_matrix;
    pub const libinput_device_config_calibration_set_matrix = __root.libinput_device_config_calibration_set_matrix;
    pub const libinput_device_config_calibration_get_matrix = __root.libinput_device_config_calibration_get_matrix;
    pub const libinput_device_config_calibration_get_default_matrix = __root.libinput_device_config_calibration_get_default_matrix;
    pub const libinput_device_config_area_has_rectangle = __root.libinput_device_config_area_has_rectangle;
    pub const libinput_device_config_area_set_rectangle = __root.libinput_device_config_area_set_rectangle;
    pub const libinput_device_config_area_get_rectangle = __root.libinput_device_config_area_get_rectangle;
    pub const libinput_device_config_area_get_default_rectangle = __root.libinput_device_config_area_get_default_rectangle;
    pub const libinput_device_config_send_events_get_modes = __root.libinput_device_config_send_events_get_modes;
    pub const libinput_device_config_send_events_set_mode = __root.libinput_device_config_send_events_set_mode;
    pub const libinput_device_config_send_events_get_mode = __root.libinput_device_config_send_events_get_mode;
    pub const libinput_device_config_send_events_get_default_mode = __root.libinput_device_config_send_events_get_default_mode;
    pub const libinput_device_config_accel_is_available = __root.libinput_device_config_accel_is_available;
    pub const libinput_device_config_accel_set_speed = __root.libinput_device_config_accel_set_speed;
    pub const libinput_device_config_accel_get_speed = __root.libinput_device_config_accel_get_speed;
    pub const libinput_device_config_accel_get_default_speed = __root.libinput_device_config_accel_get_default_speed;
    pub const libinput_device_config_accel_apply = __root.libinput_device_config_accel_apply;
    pub const libinput_device_config_accel_get_profiles = __root.libinput_device_config_accel_get_profiles;
    pub const libinput_device_config_accel_set_profile = __root.libinput_device_config_accel_set_profile;
    pub const libinput_device_config_accel_get_profile = __root.libinput_device_config_accel_get_profile;
    pub const libinput_device_config_accel_get_default_profile = __root.libinput_device_config_accel_get_default_profile;
    pub const libinput_device_config_scroll_has_natural_scroll = __root.libinput_device_config_scroll_has_natural_scroll;
    pub const libinput_device_config_scroll_set_natural_scroll_enabled = __root.libinput_device_config_scroll_set_natural_scroll_enabled;
    pub const libinput_device_config_scroll_get_natural_scroll_enabled = __root.libinput_device_config_scroll_get_natural_scroll_enabled;
    pub const libinput_device_config_scroll_get_default_natural_scroll_enabled = __root.libinput_device_config_scroll_get_default_natural_scroll_enabled;
    pub const libinput_device_config_left_handed_is_available = __root.libinput_device_config_left_handed_is_available;
    pub const libinput_device_config_left_handed_set = __root.libinput_device_config_left_handed_set;
    pub const libinput_device_config_left_handed_get = __root.libinput_device_config_left_handed_get;
    pub const libinput_device_config_left_handed_get_default = __root.libinput_device_config_left_handed_get_default;
    pub const libinput_device_config_click_get_methods = __root.libinput_device_config_click_get_methods;
    pub const libinput_device_config_click_set_method = __root.libinput_device_config_click_set_method;
    pub const libinput_device_config_click_get_method = __root.libinput_device_config_click_get_method;
    pub const libinput_device_config_click_get_default_method = __root.libinput_device_config_click_get_default_method;
    pub const libinput_device_config_click_set_clickfinger_button_map = __root.libinput_device_config_click_set_clickfinger_button_map;
    pub const libinput_device_config_click_get_clickfinger_button_map = __root.libinput_device_config_click_get_clickfinger_button_map;
    pub const libinput_device_config_click_get_default_clickfinger_button_map = __root.libinput_device_config_click_get_default_clickfinger_button_map;
    pub const libinput_device_config_middle_emulation_is_available = __root.libinput_device_config_middle_emulation_is_available;
    pub const libinput_device_config_middle_emulation_set_enabled = __root.libinput_device_config_middle_emulation_set_enabled;
    pub const libinput_device_config_middle_emulation_get_enabled = __root.libinput_device_config_middle_emulation_get_enabled;
    pub const libinput_device_config_middle_emulation_get_default_enabled = __root.libinput_device_config_middle_emulation_get_default_enabled;
    pub const libinput_device_config_scroll_get_methods = __root.libinput_device_config_scroll_get_methods;
    pub const libinput_device_config_scroll_set_method = __root.libinput_device_config_scroll_set_method;
    pub const libinput_device_config_scroll_get_method = __root.libinput_device_config_scroll_get_method;
    pub const libinput_device_config_scroll_get_default_method = __root.libinput_device_config_scroll_get_default_method;
    pub const libinput_device_config_scroll_set_button = __root.libinput_device_config_scroll_set_button;
    pub const libinput_device_config_scroll_get_button = __root.libinput_device_config_scroll_get_button;
    pub const libinput_device_config_scroll_get_default_button = __root.libinput_device_config_scroll_get_default_button;
    pub const libinput_device_config_scroll_set_button_lock = __root.libinput_device_config_scroll_set_button_lock;
    pub const libinput_device_config_scroll_get_button_lock = __root.libinput_device_config_scroll_get_button_lock;
    pub const libinput_device_config_scroll_get_default_button_lock = __root.libinput_device_config_scroll_get_default_button_lock;
    pub const libinput_device_config_dwt_is_available = __root.libinput_device_config_dwt_is_available;
    pub const libinput_device_config_dwt_set_enabled = __root.libinput_device_config_dwt_set_enabled;
    pub const libinput_device_config_dwt_get_enabled = __root.libinput_device_config_dwt_get_enabled;
    pub const libinput_device_config_dwt_get_default_enabled = __root.libinput_device_config_dwt_get_default_enabled;
    pub const libinput_device_config_dwt_set_timeout = __root.libinput_device_config_dwt_set_timeout;
    pub const libinput_device_config_dwt_get_timeout = __root.libinput_device_config_dwt_get_timeout;
    pub const libinput_device_config_dwt_get_default_timeout = __root.libinput_device_config_dwt_get_default_timeout;
    pub const libinput_device_config_dwtp_is_available = __root.libinput_device_config_dwtp_is_available;
    pub const libinput_device_config_dwtp_set_enabled = __root.libinput_device_config_dwtp_set_enabled;
    pub const libinput_device_config_dwtp_get_enabled = __root.libinput_device_config_dwtp_get_enabled;
    pub const libinput_device_config_dwtp_get_default_enabled = __root.libinput_device_config_dwtp_get_default_enabled;
    pub const libinput_device_config_dwtp_set_timeout = __root.libinput_device_config_dwtp_set_timeout;
    pub const libinput_device_config_dwtp_get_timeout = __root.libinput_device_config_dwtp_get_timeout;
    pub const libinput_device_config_dwtp_get_default_timeout = __root.libinput_device_config_dwtp_get_default_timeout;
    pub const libinput_device_config_rotation_is_available = __root.libinput_device_config_rotation_is_available;
    pub const libinput_device_config_rotation_set_angle = __root.libinput_device_config_rotation_set_angle;
    pub const libinput_device_config_rotation_get_angle = __root.libinput_device_config_rotation_get_angle;
    pub const libinput_device_config_rotation_get_default_angle = __root.libinput_device_config_rotation_get_default_angle;
    pub const tablet_pad_get_num_mode_groups = __root.libinput_device_tablet_pad_get_num_mode_groups;
    pub const tablet_pad_get_mode_group = __root.libinput_device_tablet_pad_get_mode_group;
    pub const device = __root.libinput_path_remove_device;
    pub const ref = __root.libinput_device_ref;
    pub const unref = __root.libinput_device_unref;
    pub const set_user_data = __root.libinput_device_set_user_data;
    pub const get_user_data = __root.libinput_device_get_user_data;
    pub const get_context = __root.libinput_device_get_context;
    pub const get_device_group = __root.libinput_device_get_device_group;
    pub const get_sysname = __root.libinput_device_get_sysname;
    pub const get_name = __root.libinput_device_get_name;
    pub const get_id_bustype = __root.libinput_device_get_id_bustype;
    pub const get_id_product = __root.libinput_device_get_id_product;
    pub const get_id_vendor = __root.libinput_device_get_id_vendor;
    pub const get_output_name = __root.libinput_device_get_output_name;
    pub const get_seat = __root.libinput_device_get_seat;
    pub const set_seat_logical_name = __root.libinput_device_set_seat_logical_name;
    pub const get_udev_device = __root.libinput_device_get_udev_device;
    pub const led_update = __root.libinput_device_led_update;
    pub const has_capability = __root.libinput_device_has_capability;
    pub const get_size = __root.libinput_device_get_size;
    pub const pointer_has_button = __root.libinput_device_pointer_has_button;
    pub const keyboard_has_key = __root.libinput_device_keyboard_has_key;
    pub const touch_get_touch_count = __root.libinput_device_touch_get_touch_count;
    pub const switch_has_switch = __root.libinput_device_switch_has_switch;
    pub const tablet_pad_get_num_buttons = __root.libinput_device_tablet_pad_get_num_buttons;
    pub const tablet_pad_get_num_dials = __root.libinput_device_tablet_pad_get_num_dials;
    pub const tablet_pad_get_num_rings = __root.libinput_device_tablet_pad_get_num_rings;
    pub const tablet_pad_get_num_strips = __root.libinput_device_tablet_pad_get_num_strips;
    pub const tablet_pad_has_key = __root.libinput_device_tablet_pad_has_key;
    pub const config_tap_get_finger_count = __root.libinput_device_config_tap_get_finger_count;
    pub const config_tap_set_enabled = __root.libinput_device_config_tap_set_enabled;
    pub const config_tap_get_enabled = __root.libinput_device_config_tap_get_enabled;
    pub const config_tap_get_default_enabled = __root.libinput_device_config_tap_get_default_enabled;
    pub const config_tap_set_button_map = __root.libinput_device_config_tap_set_button_map;
    pub const config_tap_get_button_map = __root.libinput_device_config_tap_get_button_map;
    pub const config_tap_get_default_button_map = __root.libinput_device_config_tap_get_default_button_map;
    pub const config_tap_set_drag_enabled = __root.libinput_device_config_tap_set_drag_enabled;
    pub const config_tap_get_drag_enabled = __root.libinput_device_config_tap_get_drag_enabled;
    pub const config_tap_get_default_drag_enabled = __root.libinput_device_config_tap_get_default_drag_enabled;
    pub const config_tap_set_drag_lock_enabled = __root.libinput_device_config_tap_set_drag_lock_enabled;
    pub const config_tap_get_drag_lock_enabled = __root.libinput_device_config_tap_get_drag_lock_enabled;
    pub const config_tap_get_default_drag_lock_enabled = __root.libinput_device_config_tap_get_default_drag_lock_enabled;
    pub const config_3fg_drag_get_finger_count = __root.libinput_device_config_3fg_drag_get_finger_count;
    pub const config_3fg_drag_set_enabled = __root.libinput_device_config_3fg_drag_set_enabled;
    pub const config_3fg_drag_get_enabled = __root.libinput_device_config_3fg_drag_get_enabled;
    pub const config_3fg_drag_get_default_enabled = __root.libinput_device_config_3fg_drag_get_default_enabled;
    pub const config_calibration_has_matrix = __root.libinput_device_config_calibration_has_matrix;
    pub const config_calibration_set_matrix = __root.libinput_device_config_calibration_set_matrix;
    pub const config_calibration_get_matrix = __root.libinput_device_config_calibration_get_matrix;
    pub const config_calibration_get_default_matrix = __root.libinput_device_config_calibration_get_default_matrix;
    pub const config_area_has_rectangle = __root.libinput_device_config_area_has_rectangle;
    pub const config_area_set_rectangle = __root.libinput_device_config_area_set_rectangle;
    pub const config_area_get_rectangle = __root.libinput_device_config_area_get_rectangle;
    pub const config_area_get_default_rectangle = __root.libinput_device_config_area_get_default_rectangle;
    pub const config_send_events_get_modes = __root.libinput_device_config_send_events_get_modes;
    pub const config_send_events_set_mode = __root.libinput_device_config_send_events_set_mode;
    pub const config_send_events_get_mode = __root.libinput_device_config_send_events_get_mode;
    pub const config_send_events_get_default_mode = __root.libinput_device_config_send_events_get_default_mode;
    pub const config_accel_is_available = __root.libinput_device_config_accel_is_available;
    pub const config_accel_set_speed = __root.libinput_device_config_accel_set_speed;
    pub const config_accel_get_speed = __root.libinput_device_config_accel_get_speed;
    pub const config_accel_get_default_speed = __root.libinput_device_config_accel_get_default_speed;
    pub const config_accel_apply = __root.libinput_device_config_accel_apply;
    pub const config_accel_get_profiles = __root.libinput_device_config_accel_get_profiles;
    pub const config_accel_set_profile = __root.libinput_device_config_accel_set_profile;
    pub const config_accel_get_profile = __root.libinput_device_config_accel_get_profile;
    pub const config_accel_get_default_profile = __root.libinput_device_config_accel_get_default_profile;
    pub const config_scroll_has_natural_scroll = __root.libinput_device_config_scroll_has_natural_scroll;
    pub const config_scroll_set_natural_scroll_enabled = __root.libinput_device_config_scroll_set_natural_scroll_enabled;
    pub const config_scroll_get_natural_scroll_enabled = __root.libinput_device_config_scroll_get_natural_scroll_enabled;
    pub const config_scroll_get_default_natural_scroll_enabled = __root.libinput_device_config_scroll_get_default_natural_scroll_enabled;
    pub const config_left_handed_is_available = __root.libinput_device_config_left_handed_is_available;
    pub const config_left_handed_set = __root.libinput_device_config_left_handed_set;
    pub const config_left_handed_get = __root.libinput_device_config_left_handed_get;
    pub const config_left_handed_get_default = __root.libinput_device_config_left_handed_get_default;
    pub const config_click_get_methods = __root.libinput_device_config_click_get_methods;
    pub const config_click_set_method = __root.libinput_device_config_click_set_method;
    pub const config_click_get_method = __root.libinput_device_config_click_get_method;
    pub const config_click_get_default_method = __root.libinput_device_config_click_get_default_method;
    pub const config_click_set_clickfinger_button_map = __root.libinput_device_config_click_set_clickfinger_button_map;
    pub const config_click_get_clickfinger_button_map = __root.libinput_device_config_click_get_clickfinger_button_map;
    pub const config_click_get_default_clickfinger_button_map = __root.libinput_device_config_click_get_default_clickfinger_button_map;
    pub const config_middle_emulation_is_available = __root.libinput_device_config_middle_emulation_is_available;
    pub const config_middle_emulation_set_enabled = __root.libinput_device_config_middle_emulation_set_enabled;
    pub const config_middle_emulation_get_enabled = __root.libinput_device_config_middle_emulation_get_enabled;
    pub const config_middle_emulation_get_default_enabled = __root.libinput_device_config_middle_emulation_get_default_enabled;
    pub const config_scroll_get_methods = __root.libinput_device_config_scroll_get_methods;
    pub const config_scroll_set_method = __root.libinput_device_config_scroll_set_method;
    pub const config_scroll_get_method = __root.libinput_device_config_scroll_get_method;
    pub const config_scroll_get_default_method = __root.libinput_device_config_scroll_get_default_method;
    pub const config_scroll_set_button = __root.libinput_device_config_scroll_set_button;
    pub const config_scroll_get_button = __root.libinput_device_config_scroll_get_button;
    pub const config_scroll_get_default_button = __root.libinput_device_config_scroll_get_default_button;
    pub const config_scroll_set_button_lock = __root.libinput_device_config_scroll_set_button_lock;
    pub const config_scroll_get_button_lock = __root.libinput_device_config_scroll_get_button_lock;
    pub const config_scroll_get_default_button_lock = __root.libinput_device_config_scroll_get_default_button_lock;
    pub const config_dwt_is_available = __root.libinput_device_config_dwt_is_available;
    pub const config_dwt_set_enabled = __root.libinput_device_config_dwt_set_enabled;
    pub const config_dwt_get_enabled = __root.libinput_device_config_dwt_get_enabled;
    pub const config_dwt_get_default_enabled = __root.libinput_device_config_dwt_get_default_enabled;
    pub const config_dwt_set_timeout = __root.libinput_device_config_dwt_set_timeout;
    pub const config_dwt_get_timeout = __root.libinput_device_config_dwt_get_timeout;
    pub const config_dwt_get_default_timeout = __root.libinput_device_config_dwt_get_default_timeout;
    pub const config_dwtp_is_available = __root.libinput_device_config_dwtp_is_available;
    pub const config_dwtp_set_enabled = __root.libinput_device_config_dwtp_set_enabled;
    pub const config_dwtp_get_enabled = __root.libinput_device_config_dwtp_get_enabled;
    pub const config_dwtp_get_default_enabled = __root.libinput_device_config_dwtp_get_default_enabled;
    pub const config_dwtp_set_timeout = __root.libinput_device_config_dwtp_set_timeout;
    pub const config_dwtp_get_timeout = __root.libinput_device_config_dwtp_get_timeout;
    pub const config_dwtp_get_default_timeout = __root.libinput_device_config_dwtp_get_default_timeout;
    pub const config_rotation_is_available = __root.libinput_device_config_rotation_is_available;
    pub const config_rotation_set_angle = __root.libinput_device_config_rotation_set_angle;
    pub const config_rotation_get_angle = __root.libinput_device_config_rotation_get_angle;
    pub const config_rotation_get_default_angle = __root.libinput_device_config_rotation_get_default_angle;
};
pub const struct_libinput_device_group = opaque {
    pub const libinput_device_group_ref = __root.libinput_device_group_ref;
    pub const libinput_device_group_unref = __root.libinput_device_group_unref;
    pub const libinput_device_group_set_user_data = __root.libinput_device_group_set_user_data;
    pub const libinput_device_group_get_user_data = __root.libinput_device_group_get_user_data;
    pub const ref = __root.libinput_device_group_ref;
    pub const unref = __root.libinput_device_group_unref;
    pub const set_user_data = __root.libinput_device_group_set_user_data;
    pub const get_user_data = __root.libinput_device_group_get_user_data;
};
pub const struct_libinput_seat = opaque {
    pub const libinput_seat_ref = __root.libinput_seat_ref;
    pub const libinput_seat_unref = __root.libinput_seat_unref;
    pub const libinput_seat_set_user_data = __root.libinput_seat_set_user_data;
    pub const libinput_seat_get_user_data = __root.libinput_seat_get_user_data;
    pub const libinput_seat_get_context = __root.libinput_seat_get_context;
    pub const libinput_seat_get_physical_name = __root.libinput_seat_get_physical_name;
    pub const libinput_seat_get_logical_name = __root.libinput_seat_get_logical_name;
    pub const ref = __root.libinput_seat_ref;
    pub const unref = __root.libinput_seat_unref;
    pub const set_user_data = __root.libinput_seat_set_user_data;
    pub const get_user_data = __root.libinput_seat_get_user_data;
    pub const get_context = __root.libinput_seat_get_context;
    pub const get_physical_name = __root.libinput_seat_get_physical_name;
    pub const get_logical_name = __root.libinput_seat_get_logical_name;
};
pub const struct_libinput_tablet_tool = opaque {
    pub const libinput_tablet_tool_get_type = __root.libinput_tablet_tool_get_type;
    pub const libinput_tablet_tool_get_tool_id = __root.libinput_tablet_tool_get_tool_id;
    pub const libinput_tablet_tool_get_name = __root.libinput_tablet_tool_get_name;
    pub const libinput_tablet_tool_ref = __root.libinput_tablet_tool_ref;
    pub const libinput_tablet_tool_unref = __root.libinput_tablet_tool_unref;
    pub const libinput_tablet_tool_has_pressure = __root.libinput_tablet_tool_has_pressure;
    pub const libinput_tablet_tool_has_distance = __root.libinput_tablet_tool_has_distance;
    pub const libinput_tablet_tool_has_tilt = __root.libinput_tablet_tool_has_tilt;
    pub const libinput_tablet_tool_has_rotation = __root.libinput_tablet_tool_has_rotation;
    pub const libinput_tablet_tool_has_slider = __root.libinput_tablet_tool_has_slider;
    pub const libinput_tablet_tool_has_size = __root.libinput_tablet_tool_has_size;
    pub const libinput_tablet_tool_has_wheel = __root.libinput_tablet_tool_has_wheel;
    pub const libinput_tablet_tool_has_button = __root.libinput_tablet_tool_has_button;
    pub const libinput_tablet_tool_is_unique = __root.libinput_tablet_tool_is_unique;
    pub const libinput_tablet_tool_get_serial = __root.libinput_tablet_tool_get_serial;
    pub const libinput_tablet_tool_get_user_data = __root.libinput_tablet_tool_get_user_data;
    pub const libinput_tablet_tool_set_user_data = __root.libinput_tablet_tool_set_user_data;
    pub const libinput_tablet_tool_config_pressure_range_is_available = __root.libinput_tablet_tool_config_pressure_range_is_available;
    pub const libinput_tablet_tool_config_pressure_range_set = __root.libinput_tablet_tool_config_pressure_range_set;
    pub const libinput_tablet_tool_config_pressure_range_get_minimum = __root.libinput_tablet_tool_config_pressure_range_get_minimum;
    pub const libinput_tablet_tool_config_pressure_range_get_maximum = __root.libinput_tablet_tool_config_pressure_range_get_maximum;
    pub const libinput_tablet_tool_config_pressure_range_get_default_minimum = __root.libinput_tablet_tool_config_pressure_range_get_default_minimum;
    pub const libinput_tablet_tool_config_pressure_range_get_default_maximum = __root.libinput_tablet_tool_config_pressure_range_get_default_maximum;
    pub const libinput_tablet_tool_config_eraser_button_get_modes = __root.libinput_tablet_tool_config_eraser_button_get_modes;
    pub const libinput_tablet_tool_config_eraser_button_set_mode = __root.libinput_tablet_tool_config_eraser_button_set_mode;
    pub const libinput_tablet_tool_config_eraser_button_get_mode = __root.libinput_tablet_tool_config_eraser_button_get_mode;
    pub const libinput_tablet_tool_config_eraser_button_get_default_mode = __root.libinput_tablet_tool_config_eraser_button_get_default_mode;
    pub const libinput_tablet_tool_config_eraser_button_set_button = __root.libinput_tablet_tool_config_eraser_button_set_button;
    pub const libinput_tablet_tool_config_eraser_button_get_button = __root.libinput_tablet_tool_config_eraser_button_get_button;
    pub const libinput_tablet_tool_config_eraser_button_get_default_button = __root.libinput_tablet_tool_config_eraser_button_get_default_button;
    pub const get_type = __root.libinput_tablet_tool_get_type;
    pub const get_tool_id = __root.libinput_tablet_tool_get_tool_id;
    pub const get_name = __root.libinput_tablet_tool_get_name;
    pub const ref = __root.libinput_tablet_tool_ref;
    pub const unref = __root.libinput_tablet_tool_unref;
    pub const has_pressure = __root.libinput_tablet_tool_has_pressure;
    pub const has_distance = __root.libinput_tablet_tool_has_distance;
    pub const has_tilt = __root.libinput_tablet_tool_has_tilt;
    pub const has_rotation = __root.libinput_tablet_tool_has_rotation;
    pub const has_slider = __root.libinput_tablet_tool_has_slider;
    pub const has_size = __root.libinput_tablet_tool_has_size;
    pub const has_wheel = __root.libinput_tablet_tool_has_wheel;
    pub const has_button = __root.libinput_tablet_tool_has_button;
    pub const is_unique = __root.libinput_tablet_tool_is_unique;
    pub const get_serial = __root.libinput_tablet_tool_get_serial;
    pub const get_user_data = __root.libinput_tablet_tool_get_user_data;
    pub const set_user_data = __root.libinput_tablet_tool_set_user_data;
    pub const config_pressure_range_is_available = __root.libinput_tablet_tool_config_pressure_range_is_available;
    pub const config_pressure_range_set = __root.libinput_tablet_tool_config_pressure_range_set;
    pub const config_pressure_range_get_minimum = __root.libinput_tablet_tool_config_pressure_range_get_minimum;
    pub const config_pressure_range_get_maximum = __root.libinput_tablet_tool_config_pressure_range_get_maximum;
    pub const config_pressure_range_get_default_minimum = __root.libinput_tablet_tool_config_pressure_range_get_default_minimum;
    pub const config_pressure_range_get_default_maximum = __root.libinput_tablet_tool_config_pressure_range_get_default_maximum;
    pub const config_eraser_button_get_modes = __root.libinput_tablet_tool_config_eraser_button_get_modes;
    pub const config_eraser_button_set_mode = __root.libinput_tablet_tool_config_eraser_button_set_mode;
    pub const config_eraser_button_get_mode = __root.libinput_tablet_tool_config_eraser_button_get_mode;
    pub const config_eraser_button_get_default_mode = __root.libinput_tablet_tool_config_eraser_button_get_default_mode;
    pub const config_eraser_button_set_button = __root.libinput_tablet_tool_config_eraser_button_set_button;
    pub const config_eraser_button_get_button = __root.libinput_tablet_tool_config_eraser_button_get_button;
    pub const config_eraser_button_get_default_button = __root.libinput_tablet_tool_config_eraser_button_get_default_button;
};
pub const struct_libinput_event = opaque {
    pub const libinput_event_destroy = __root.libinput_event_destroy;
    pub const libinput_event_get_type = __root.libinput_event_get_type;
    pub const libinput_event_get_context = __root.libinput_event_get_context;
    pub const libinput_event_get_device = __root.libinput_event_get_device;
    pub const libinput_event_get_pointer_event = __root.libinput_event_get_pointer_event;
    pub const libinput_event_get_keyboard_event = __root.libinput_event_get_keyboard_event;
    pub const libinput_event_get_touch_event = __root.libinput_event_get_touch_event;
    pub const libinput_event_get_gesture_event = __root.libinput_event_get_gesture_event;
    pub const libinput_event_get_tablet_tool_event = __root.libinput_event_get_tablet_tool_event;
    pub const libinput_event_get_tablet_pad_event = __root.libinput_event_get_tablet_pad_event;
    pub const libinput_event_get_switch_event = __root.libinput_event_get_switch_event;
    pub const libinput_event_get_device_notify_event = __root.libinput_event_get_device_notify_event;
    pub const destroy = __root.libinput_event_destroy;
    pub const get_type = __root.libinput_event_get_type;
    pub const get_context = __root.libinput_event_get_context;
    pub const get_device = __root.libinput_event_get_device;
    pub const get_pointer_event = __root.libinput_event_get_pointer_event;
    pub const get_keyboard_event = __root.libinput_event_get_keyboard_event;
    pub const get_touch_event = __root.libinput_event_get_touch_event;
    pub const get_gesture_event = __root.libinput_event_get_gesture_event;
    pub const get_tablet_tool_event = __root.libinput_event_get_tablet_tool_event;
    pub const get_tablet_pad_event = __root.libinput_event_get_tablet_pad_event;
    pub const get_switch_event = __root.libinput_event_get_switch_event;
    pub const get_device_notify_event = __root.libinput_event_get_device_notify_event;
};
pub const struct_libinput_event_device_notify = opaque {
    pub const libinput_event_device_notify_get_base_event = __root.libinput_event_device_notify_get_base_event;
    pub const get_base_event = __root.libinput_event_device_notify_get_base_event;
};
pub const struct_libinput_event_keyboard = opaque {
    pub const libinput_event_keyboard_get_time = __root.libinput_event_keyboard_get_time;
    pub const libinput_event_keyboard_get_time_usec = __root.libinput_event_keyboard_get_time_usec;
    pub const libinput_event_keyboard_get_key = __root.libinput_event_keyboard_get_key;
    pub const libinput_event_keyboard_get_key_state = __root.libinput_event_keyboard_get_key_state;
    pub const libinput_event_keyboard_get_base_event = __root.libinput_event_keyboard_get_base_event;
    pub const libinput_event_keyboard_get_seat_key_count = __root.libinput_event_keyboard_get_seat_key_count;
    pub const get_time = __root.libinput_event_keyboard_get_time;
    pub const get_time_usec = __root.libinput_event_keyboard_get_time_usec;
    pub const get_key = __root.libinput_event_keyboard_get_key;
    pub const get_key_state = __root.libinput_event_keyboard_get_key_state;
    pub const get_base_event = __root.libinput_event_keyboard_get_base_event;
    pub const get_seat_key_count = __root.libinput_event_keyboard_get_seat_key_count;
};
pub const struct_libinput_event_pointer = opaque {
    pub const libinput_event_pointer_get_time = __root.libinput_event_pointer_get_time;
    pub const libinput_event_pointer_get_time_usec = __root.libinput_event_pointer_get_time_usec;
    pub const libinput_event_pointer_get_dx = __root.libinput_event_pointer_get_dx;
    pub const libinput_event_pointer_get_dy = __root.libinput_event_pointer_get_dy;
    pub const libinput_event_pointer_get_dx_unaccelerated = __root.libinput_event_pointer_get_dx_unaccelerated;
    pub const libinput_event_pointer_get_dy_unaccelerated = __root.libinput_event_pointer_get_dy_unaccelerated;
    pub const libinput_event_pointer_get_absolute_x = __root.libinput_event_pointer_get_absolute_x;
    pub const libinput_event_pointer_get_absolute_y = __root.libinput_event_pointer_get_absolute_y;
    pub const libinput_event_pointer_get_absolute_x_transformed = __root.libinput_event_pointer_get_absolute_x_transformed;
    pub const libinput_event_pointer_get_absolute_y_transformed = __root.libinput_event_pointer_get_absolute_y_transformed;
    pub const libinput_event_pointer_get_button = __root.libinput_event_pointer_get_button;
    pub const libinput_event_pointer_get_button_state = __root.libinput_event_pointer_get_button_state;
    pub const libinput_event_pointer_get_seat_button_count = __root.libinput_event_pointer_get_seat_button_count;
    pub const libinput_event_pointer_has_axis = __root.libinput_event_pointer_has_axis;
    pub const libinput_event_pointer_get_axis_value = __root.libinput_event_pointer_get_axis_value;
    pub const libinput_event_pointer_get_axis_source = __root.libinput_event_pointer_get_axis_source;
    pub const libinput_event_pointer_get_axis_value_discrete = __root.libinput_event_pointer_get_axis_value_discrete;
    pub const libinput_event_pointer_get_scroll_value = __root.libinput_event_pointer_get_scroll_value;
    pub const libinput_event_pointer_get_scroll_value_v120 = __root.libinput_event_pointer_get_scroll_value_v120;
    pub const libinput_event_pointer_get_base_event = __root.libinput_event_pointer_get_base_event;
    pub const get_time = __root.libinput_event_pointer_get_time;
    pub const get_time_usec = __root.libinput_event_pointer_get_time_usec;
    pub const get_dx = __root.libinput_event_pointer_get_dx;
    pub const get_dy = __root.libinput_event_pointer_get_dy;
    pub const get_dx_unaccelerated = __root.libinput_event_pointer_get_dx_unaccelerated;
    pub const get_dy_unaccelerated = __root.libinput_event_pointer_get_dy_unaccelerated;
    pub const get_absolute_x = __root.libinput_event_pointer_get_absolute_x;
    pub const get_absolute_y = __root.libinput_event_pointer_get_absolute_y;
    pub const get_absolute_x_transformed = __root.libinput_event_pointer_get_absolute_x_transformed;
    pub const get_absolute_y_transformed = __root.libinput_event_pointer_get_absolute_y_transformed;
    pub const get_button = __root.libinput_event_pointer_get_button;
    pub const get_button_state = __root.libinput_event_pointer_get_button_state;
    pub const get_seat_button_count = __root.libinput_event_pointer_get_seat_button_count;
    pub const has_axis = __root.libinput_event_pointer_has_axis;
    pub const get_axis_value = __root.libinput_event_pointer_get_axis_value;
    pub const get_axis_source = __root.libinput_event_pointer_get_axis_source;
    pub const get_axis_value_discrete = __root.libinput_event_pointer_get_axis_value_discrete;
    pub const get_scroll_value = __root.libinput_event_pointer_get_scroll_value;
    pub const get_scroll_value_v120 = __root.libinput_event_pointer_get_scroll_value_v120;
    pub const get_base_event = __root.libinput_event_pointer_get_base_event;
};
pub const struct_libinput_event_touch = opaque {
    pub const libinput_event_touch_get_time = __root.libinput_event_touch_get_time;
    pub const libinput_event_touch_get_time_usec = __root.libinput_event_touch_get_time_usec;
    pub const libinput_event_touch_get_slot = __root.libinput_event_touch_get_slot;
    pub const libinput_event_touch_get_seat_slot = __root.libinput_event_touch_get_seat_slot;
    pub const libinput_event_touch_get_x = __root.libinput_event_touch_get_x;
    pub const libinput_event_touch_get_y = __root.libinput_event_touch_get_y;
    pub const libinput_event_touch_get_x_transformed = __root.libinput_event_touch_get_x_transformed;
    pub const libinput_event_touch_get_y_transformed = __root.libinput_event_touch_get_y_transformed;
    pub const libinput_event_touch_get_base_event = __root.libinput_event_touch_get_base_event;
    pub const get_time = __root.libinput_event_touch_get_time;
    pub const get_time_usec = __root.libinput_event_touch_get_time_usec;
    pub const get_slot = __root.libinput_event_touch_get_slot;
    pub const get_seat_slot = __root.libinput_event_touch_get_seat_slot;
    pub const get_x = __root.libinput_event_touch_get_x;
    pub const get_y = __root.libinput_event_touch_get_y;
    pub const get_x_transformed = __root.libinput_event_touch_get_x_transformed;
    pub const get_y_transformed = __root.libinput_event_touch_get_y_transformed;
    pub const get_base_event = __root.libinput_event_touch_get_base_event;
};
pub const struct_libinput_event_gesture = opaque {
    pub const libinput_event_gesture_get_time = __root.libinput_event_gesture_get_time;
    pub const libinput_event_gesture_get_time_usec = __root.libinput_event_gesture_get_time_usec;
    pub const libinput_event_gesture_get_base_event = __root.libinput_event_gesture_get_base_event;
    pub const libinput_event_gesture_get_finger_count = __root.libinput_event_gesture_get_finger_count;
    pub const libinput_event_gesture_get_cancelled = __root.libinput_event_gesture_get_cancelled;
    pub const libinput_event_gesture_get_dx = __root.libinput_event_gesture_get_dx;
    pub const libinput_event_gesture_get_dy = __root.libinput_event_gesture_get_dy;
    pub const libinput_event_gesture_get_dx_unaccelerated = __root.libinput_event_gesture_get_dx_unaccelerated;
    pub const libinput_event_gesture_get_dy_unaccelerated = __root.libinput_event_gesture_get_dy_unaccelerated;
    pub const libinput_event_gesture_get_scale = __root.libinput_event_gesture_get_scale;
    pub const libinput_event_gesture_get_angle_delta = __root.libinput_event_gesture_get_angle_delta;
    pub const get_time = __root.libinput_event_gesture_get_time;
    pub const get_time_usec = __root.libinput_event_gesture_get_time_usec;
    pub const get_base_event = __root.libinput_event_gesture_get_base_event;
    pub const get_finger_count = __root.libinput_event_gesture_get_finger_count;
    pub const get_cancelled = __root.libinput_event_gesture_get_cancelled;
    pub const get_dx = __root.libinput_event_gesture_get_dx;
    pub const get_dy = __root.libinput_event_gesture_get_dy;
    pub const get_dx_unaccelerated = __root.libinput_event_gesture_get_dx_unaccelerated;
    pub const get_dy_unaccelerated = __root.libinput_event_gesture_get_dy_unaccelerated;
    pub const get_scale = __root.libinput_event_gesture_get_scale;
    pub const get_angle_delta = __root.libinput_event_gesture_get_angle_delta;
};
pub const struct_libinput_event_tablet_tool = opaque {
    pub const libinput_event_tablet_tool_get_base_event = __root.libinput_event_tablet_tool_get_base_event;
    pub const libinput_event_tablet_tool_x_has_changed = __root.libinput_event_tablet_tool_x_has_changed;
    pub const libinput_event_tablet_tool_y_has_changed = __root.libinput_event_tablet_tool_y_has_changed;
    pub const libinput_event_tablet_tool_pressure_has_changed = __root.libinput_event_tablet_tool_pressure_has_changed;
    pub const libinput_event_tablet_tool_distance_has_changed = __root.libinput_event_tablet_tool_distance_has_changed;
    pub const libinput_event_tablet_tool_tilt_x_has_changed = __root.libinput_event_tablet_tool_tilt_x_has_changed;
    pub const libinput_event_tablet_tool_tilt_y_has_changed = __root.libinput_event_tablet_tool_tilt_y_has_changed;
    pub const libinput_event_tablet_tool_rotation_has_changed = __root.libinput_event_tablet_tool_rotation_has_changed;
    pub const libinput_event_tablet_tool_slider_has_changed = __root.libinput_event_tablet_tool_slider_has_changed;
    pub const libinput_event_tablet_tool_size_major_has_changed = __root.libinput_event_tablet_tool_size_major_has_changed;
    pub const libinput_event_tablet_tool_size_minor_has_changed = __root.libinput_event_tablet_tool_size_minor_has_changed;
    pub const libinput_event_tablet_tool_wheel_has_changed = __root.libinput_event_tablet_tool_wheel_has_changed;
    pub const libinput_event_tablet_tool_get_x = __root.libinput_event_tablet_tool_get_x;
    pub const libinput_event_tablet_tool_get_y = __root.libinput_event_tablet_tool_get_y;
    pub const libinput_event_tablet_tool_get_dx = __root.libinput_event_tablet_tool_get_dx;
    pub const libinput_event_tablet_tool_get_dy = __root.libinput_event_tablet_tool_get_dy;
    pub const libinput_event_tablet_tool_get_pressure = __root.libinput_event_tablet_tool_get_pressure;
    pub const libinput_event_tablet_tool_get_distance = __root.libinput_event_tablet_tool_get_distance;
    pub const libinput_event_tablet_tool_get_tilt_x = __root.libinput_event_tablet_tool_get_tilt_x;
    pub const libinput_event_tablet_tool_get_tilt_y = __root.libinput_event_tablet_tool_get_tilt_y;
    pub const libinput_event_tablet_tool_get_rotation = __root.libinput_event_tablet_tool_get_rotation;
    pub const libinput_event_tablet_tool_get_slider_position = __root.libinput_event_tablet_tool_get_slider_position;
    pub const libinput_event_tablet_tool_get_size_major = __root.libinput_event_tablet_tool_get_size_major;
    pub const libinput_event_tablet_tool_get_size_minor = __root.libinput_event_tablet_tool_get_size_minor;
    pub const libinput_event_tablet_tool_get_wheel_delta = __root.libinput_event_tablet_tool_get_wheel_delta;
    pub const libinput_event_tablet_tool_get_wheel_delta_discrete = __root.libinput_event_tablet_tool_get_wheel_delta_discrete;
    pub const libinput_event_tablet_tool_get_x_transformed = __root.libinput_event_tablet_tool_get_x_transformed;
    pub const libinput_event_tablet_tool_get_y_transformed = __root.libinput_event_tablet_tool_get_y_transformed;
    pub const libinput_event_tablet_tool_get_tool = __root.libinput_event_tablet_tool_get_tool;
    pub const libinput_event_tablet_tool_get_proximity_state = __root.libinput_event_tablet_tool_get_proximity_state;
    pub const libinput_event_tablet_tool_get_tip_state = __root.libinput_event_tablet_tool_get_tip_state;
    pub const libinput_event_tablet_tool_get_button = __root.libinput_event_tablet_tool_get_button;
    pub const libinput_event_tablet_tool_get_button_state = __root.libinput_event_tablet_tool_get_button_state;
    pub const libinput_event_tablet_tool_get_seat_button_count = __root.libinput_event_tablet_tool_get_seat_button_count;
    pub const libinput_event_tablet_tool_get_time = __root.libinput_event_tablet_tool_get_time;
    pub const libinput_event_tablet_tool_get_time_usec = __root.libinput_event_tablet_tool_get_time_usec;
    pub const get_base_event = __root.libinput_event_tablet_tool_get_base_event;
    pub const x_has_changed = __root.libinput_event_tablet_tool_x_has_changed;
    pub const y_has_changed = __root.libinput_event_tablet_tool_y_has_changed;
    pub const pressure_has_changed = __root.libinput_event_tablet_tool_pressure_has_changed;
    pub const distance_has_changed = __root.libinput_event_tablet_tool_distance_has_changed;
    pub const tilt_x_has_changed = __root.libinput_event_tablet_tool_tilt_x_has_changed;
    pub const tilt_y_has_changed = __root.libinput_event_tablet_tool_tilt_y_has_changed;
    pub const rotation_has_changed = __root.libinput_event_tablet_tool_rotation_has_changed;
    pub const slider_has_changed = __root.libinput_event_tablet_tool_slider_has_changed;
    pub const size_major_has_changed = __root.libinput_event_tablet_tool_size_major_has_changed;
    pub const size_minor_has_changed = __root.libinput_event_tablet_tool_size_minor_has_changed;
    pub const wheel_has_changed = __root.libinput_event_tablet_tool_wheel_has_changed;
    pub const get_x = __root.libinput_event_tablet_tool_get_x;
    pub const get_y = __root.libinput_event_tablet_tool_get_y;
    pub const get_dx = __root.libinput_event_tablet_tool_get_dx;
    pub const get_dy = __root.libinput_event_tablet_tool_get_dy;
    pub const get_pressure = __root.libinput_event_tablet_tool_get_pressure;
    pub const get_distance = __root.libinput_event_tablet_tool_get_distance;
    pub const get_tilt_x = __root.libinput_event_tablet_tool_get_tilt_x;
    pub const get_tilt_y = __root.libinput_event_tablet_tool_get_tilt_y;
    pub const get_rotation = __root.libinput_event_tablet_tool_get_rotation;
    pub const get_slider_position = __root.libinput_event_tablet_tool_get_slider_position;
    pub const get_size_major = __root.libinput_event_tablet_tool_get_size_major;
    pub const get_size_minor = __root.libinput_event_tablet_tool_get_size_minor;
    pub const get_wheel_delta = __root.libinput_event_tablet_tool_get_wheel_delta;
    pub const get_wheel_delta_discrete = __root.libinput_event_tablet_tool_get_wheel_delta_discrete;
    pub const get_x_transformed = __root.libinput_event_tablet_tool_get_x_transformed;
    pub const get_y_transformed = __root.libinput_event_tablet_tool_get_y_transformed;
    pub const get_tool = __root.libinput_event_tablet_tool_get_tool;
    pub const get_proximity_state = __root.libinput_event_tablet_tool_get_proximity_state;
    pub const get_tip_state = __root.libinput_event_tablet_tool_get_tip_state;
    pub const get_button = __root.libinput_event_tablet_tool_get_button;
    pub const get_button_state = __root.libinput_event_tablet_tool_get_button_state;
    pub const get_seat_button_count = __root.libinput_event_tablet_tool_get_seat_button_count;
    pub const get_time = __root.libinput_event_tablet_tool_get_time;
    pub const get_time_usec = __root.libinput_event_tablet_tool_get_time_usec;
};
pub const struct_libinput_event_tablet_pad = opaque {
    pub const libinput_event_tablet_pad_get_base_event = __root.libinput_event_tablet_pad_get_base_event;
    pub const libinput_event_tablet_pad_get_ring_position = __root.libinput_event_tablet_pad_get_ring_position;
    pub const libinput_event_tablet_pad_get_ring_number = __root.libinput_event_tablet_pad_get_ring_number;
    pub const libinput_event_tablet_pad_get_ring_source = __root.libinput_event_tablet_pad_get_ring_source;
    pub const libinput_event_tablet_pad_get_strip_position = __root.libinput_event_tablet_pad_get_strip_position;
    pub const libinput_event_tablet_pad_get_strip_number = __root.libinput_event_tablet_pad_get_strip_number;
    pub const libinput_event_tablet_pad_get_strip_source = __root.libinput_event_tablet_pad_get_strip_source;
    pub const libinput_event_tablet_pad_get_button_number = __root.libinput_event_tablet_pad_get_button_number;
    pub const libinput_event_tablet_pad_get_button_state = __root.libinput_event_tablet_pad_get_button_state;
    pub const libinput_event_tablet_pad_get_key = __root.libinput_event_tablet_pad_get_key;
    pub const libinput_event_tablet_pad_get_key_state = __root.libinput_event_tablet_pad_get_key_state;
    pub const libinput_event_tablet_pad_get_dial_delta_v120 = __root.libinput_event_tablet_pad_get_dial_delta_v120;
    pub const libinput_event_tablet_pad_get_dial_number = __root.libinput_event_tablet_pad_get_dial_number;
    pub const libinput_event_tablet_pad_get_mode = __root.libinput_event_tablet_pad_get_mode;
    pub const libinput_event_tablet_pad_get_mode_group = __root.libinput_event_tablet_pad_get_mode_group;
    pub const libinput_event_tablet_pad_get_time = __root.libinput_event_tablet_pad_get_time;
    pub const libinput_event_tablet_pad_get_time_usec = __root.libinput_event_tablet_pad_get_time_usec;
    pub const get_base_event = __root.libinput_event_tablet_pad_get_base_event;
    pub const get_ring_position = __root.libinput_event_tablet_pad_get_ring_position;
    pub const get_ring_number = __root.libinput_event_tablet_pad_get_ring_number;
    pub const get_ring_source = __root.libinput_event_tablet_pad_get_ring_source;
    pub const get_strip_position = __root.libinput_event_tablet_pad_get_strip_position;
    pub const get_strip_number = __root.libinput_event_tablet_pad_get_strip_number;
    pub const get_strip_source = __root.libinput_event_tablet_pad_get_strip_source;
    pub const get_button_number = __root.libinput_event_tablet_pad_get_button_number;
    pub const get_button_state = __root.libinput_event_tablet_pad_get_button_state;
    pub const get_key = __root.libinput_event_tablet_pad_get_key;
    pub const get_key_state = __root.libinput_event_tablet_pad_get_key_state;
    pub const get_dial_delta_v120 = __root.libinput_event_tablet_pad_get_dial_delta_v120;
    pub const get_dial_number = __root.libinput_event_tablet_pad_get_dial_number;
    pub const get_mode = __root.libinput_event_tablet_pad_get_mode;
    pub const get_mode_group = __root.libinput_event_tablet_pad_get_mode_group;
    pub const get_time = __root.libinput_event_tablet_pad_get_time;
    pub const get_time_usec = __root.libinput_event_tablet_pad_get_time_usec;
};
pub const LIBINPUT_LOG_PRIORITY_DEBUG: c_int = 10;
pub const LIBINPUT_LOG_PRIORITY_INFO: c_int = 20;
pub const LIBINPUT_LOG_PRIORITY_ERROR: c_int = 30;
pub const enum_libinput_log_priority = c_uint;
pub const LIBINPUT_DEVICE_CAP_KEYBOARD: c_int = 0;
pub const LIBINPUT_DEVICE_CAP_POINTER: c_int = 1;
pub const LIBINPUT_DEVICE_CAP_TOUCH: c_int = 2;
pub const LIBINPUT_DEVICE_CAP_TABLET_TOOL: c_int = 3;
pub const LIBINPUT_DEVICE_CAP_TABLET_PAD: c_int = 4;
pub const LIBINPUT_DEVICE_CAP_GESTURE: c_int = 5;
pub const LIBINPUT_DEVICE_CAP_SWITCH: c_int = 6;
pub const enum_libinput_device_capability = c_uint;
pub const LIBINPUT_KEY_STATE_RELEASED: c_int = 0;
pub const LIBINPUT_KEY_STATE_PRESSED: c_int = 1;
pub const enum_libinput_key_state = c_uint;
pub const LIBINPUT_LED_NUM_LOCK: c_int = 1;
pub const LIBINPUT_LED_CAPS_LOCK: c_int = 2;
pub const LIBINPUT_LED_SCROLL_LOCK: c_int = 4;
pub const LIBINPUT_LED_COMPOSE: c_int = 8;
pub const LIBINPUT_LED_KANA: c_int = 16;
pub const enum_libinput_led = c_uint;
pub const LIBINPUT_BUTTON_STATE_RELEASED: c_int = 0;
pub const LIBINPUT_BUTTON_STATE_PRESSED: c_int = 1;
pub const enum_libinput_button_state = c_uint;
pub const LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL: c_int = 0;
pub const LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL: c_int = 1;
pub const enum_libinput_pointer_axis = c_uint;
pub const LIBINPUT_POINTER_AXIS_SOURCE_WHEEL: c_int = 1;
pub const LIBINPUT_POINTER_AXIS_SOURCE_FINGER: c_int = 2;
pub const LIBINPUT_POINTER_AXIS_SOURCE_CONTINUOUS: c_int = 3;
pub const LIBINPUT_POINTER_AXIS_SOURCE_WHEEL_TILT: c_int = 4;
pub const enum_libinput_pointer_axis_source = c_uint;
pub const LIBINPUT_TABLET_PAD_RING_SOURCE_UNKNOWN: c_int = 1;
pub const LIBINPUT_TABLET_PAD_RING_SOURCE_FINGER: c_int = 2;
pub const enum_libinput_tablet_pad_ring_axis_source = c_uint;
pub const LIBINPUT_TABLET_PAD_STRIP_SOURCE_UNKNOWN: c_int = 1;
pub const LIBINPUT_TABLET_PAD_STRIP_SOURCE_FINGER: c_int = 2;
pub const enum_libinput_tablet_pad_strip_axis_source = c_uint;
pub const LIBINPUT_TABLET_TOOL_TYPE_PEN: c_int = 1;
pub const LIBINPUT_TABLET_TOOL_TYPE_ERASER: c_int = 2;
pub const LIBINPUT_TABLET_TOOL_TYPE_BRUSH: c_int = 3;
pub const LIBINPUT_TABLET_TOOL_TYPE_PENCIL: c_int = 4;
pub const LIBINPUT_TABLET_TOOL_TYPE_AIRBRUSH: c_int = 5;
pub const LIBINPUT_TABLET_TOOL_TYPE_MOUSE: c_int = 6;
pub const LIBINPUT_TABLET_TOOL_TYPE_LENS: c_int = 7;
pub const LIBINPUT_TABLET_TOOL_TYPE_TOTEM: c_int = 8;
pub const enum_libinput_tablet_tool_type = c_uint;
pub const LIBINPUT_TABLET_TOOL_PROXIMITY_STATE_OUT: c_int = 0;
pub const LIBINPUT_TABLET_TOOL_PROXIMITY_STATE_IN: c_int = 1;
pub const enum_libinput_tablet_tool_proximity_state = c_uint;
pub const LIBINPUT_TABLET_TOOL_TIP_UP: c_int = 0;
pub const LIBINPUT_TABLET_TOOL_TIP_DOWN: c_int = 1;
pub const enum_libinput_tablet_tool_tip_state = c_uint;
pub const struct_libinput_tablet_pad_mode_group = opaque {
    pub const libinput_tablet_pad_mode_group_get_index = __root.libinput_tablet_pad_mode_group_get_index;
    pub const libinput_tablet_pad_mode_group_get_num_modes = __root.libinput_tablet_pad_mode_group_get_num_modes;
    pub const libinput_tablet_pad_mode_group_get_mode = __root.libinput_tablet_pad_mode_group_get_mode;
    pub const libinput_tablet_pad_mode_group_has_button = __root.libinput_tablet_pad_mode_group_has_button;
    pub const libinput_tablet_pad_mode_group_has_dial = __root.libinput_tablet_pad_mode_group_has_dial;
    pub const libinput_tablet_pad_mode_group_has_ring = __root.libinput_tablet_pad_mode_group_has_ring;
    pub const libinput_tablet_pad_mode_group_has_strip = __root.libinput_tablet_pad_mode_group_has_strip;
    pub const libinput_tablet_pad_mode_group_button_is_toggle = __root.libinput_tablet_pad_mode_group_button_is_toggle;
    pub const libinput_tablet_pad_mode_group_ref = __root.libinput_tablet_pad_mode_group_ref;
    pub const libinput_tablet_pad_mode_group_unref = __root.libinput_tablet_pad_mode_group_unref;
    pub const libinput_tablet_pad_mode_group_set_user_data = __root.libinput_tablet_pad_mode_group_set_user_data;
    pub const libinput_tablet_pad_mode_group_get_user_data = __root.libinput_tablet_pad_mode_group_get_user_data;
    pub const get_index = __root.libinput_tablet_pad_mode_group_get_index;
    pub const get_num_modes = __root.libinput_tablet_pad_mode_group_get_num_modes;
    pub const get_mode = __root.libinput_tablet_pad_mode_group_get_mode;
    pub const has_button = __root.libinput_tablet_pad_mode_group_has_button;
    pub const has_dial = __root.libinput_tablet_pad_mode_group_has_dial;
    pub const has_ring = __root.libinput_tablet_pad_mode_group_has_ring;
    pub const has_strip = __root.libinput_tablet_pad_mode_group_has_strip;
    pub const button_is_toggle = __root.libinput_tablet_pad_mode_group_button_is_toggle;
    pub const ref = __root.libinput_tablet_pad_mode_group_ref;
    pub const unref = __root.libinput_tablet_pad_mode_group_unref;
    pub const set_user_data = __root.libinput_tablet_pad_mode_group_set_user_data;
    pub const get_user_data = __root.libinput_tablet_pad_mode_group_get_user_data;
};
pub extern fn libinput_device_tablet_pad_get_num_mode_groups(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_tablet_pad_get_mode_group(device: ?*struct_libinput_device, index: c_uint) ?*struct_libinput_tablet_pad_mode_group;
pub extern fn libinput_tablet_pad_mode_group_get_index(group: ?*struct_libinput_tablet_pad_mode_group) c_uint;
pub extern fn libinput_tablet_pad_mode_group_get_num_modes(group: ?*struct_libinput_tablet_pad_mode_group) c_uint;
pub extern fn libinput_tablet_pad_mode_group_get_mode(group: ?*struct_libinput_tablet_pad_mode_group) c_uint;
pub extern fn libinput_tablet_pad_mode_group_has_button(group: ?*struct_libinput_tablet_pad_mode_group, button: c_uint) c_int;
pub extern fn libinput_tablet_pad_mode_group_has_dial(group: ?*struct_libinput_tablet_pad_mode_group, dial: c_uint) c_int;
pub extern fn libinput_tablet_pad_mode_group_has_ring(group: ?*struct_libinput_tablet_pad_mode_group, ring: c_uint) c_int;
pub extern fn libinput_tablet_pad_mode_group_has_strip(group: ?*struct_libinput_tablet_pad_mode_group, strip: c_uint) c_int;
pub extern fn libinput_tablet_pad_mode_group_button_is_toggle(group: ?*struct_libinput_tablet_pad_mode_group, button: c_uint) c_int;
pub extern fn libinput_tablet_pad_mode_group_ref(group: ?*struct_libinput_tablet_pad_mode_group) ?*struct_libinput_tablet_pad_mode_group;
pub extern fn libinput_tablet_pad_mode_group_unref(group: ?*struct_libinput_tablet_pad_mode_group) ?*struct_libinput_tablet_pad_mode_group;
pub extern fn libinput_tablet_pad_mode_group_set_user_data(group: ?*struct_libinput_tablet_pad_mode_group, user_data: ?*anyopaque) void;
pub extern fn libinput_tablet_pad_mode_group_get_user_data(group: ?*struct_libinput_tablet_pad_mode_group) ?*anyopaque;
pub const LIBINPUT_SWITCH_STATE_OFF: c_int = 0;
pub const LIBINPUT_SWITCH_STATE_ON: c_int = 1;
pub const enum_libinput_switch_state = c_uint;
pub const LIBINPUT_SWITCH_LID: c_int = 1;
pub const LIBINPUT_SWITCH_TABLET_MODE: c_int = 2;
pub const LIBINPUT_SWITCH_KEYPAD_SLIDE: c_int = 3;
pub const enum_libinput_switch = c_uint;
pub const struct_libinput_event_switch = opaque {
    pub const libinput_event_switch_get_switch = __root.libinput_event_switch_get_switch;
    pub const libinput_event_switch_get_switch_state = __root.libinput_event_switch_get_switch_state;
    pub const libinput_event_switch_get_base_event = __root.libinput_event_switch_get_base_event;
    pub const libinput_event_switch_get_time = __root.libinput_event_switch_get_time;
    pub const libinput_event_switch_get_time_usec = __root.libinput_event_switch_get_time_usec;
    pub const get_switch = __root.libinput_event_switch_get_switch;
    pub const get_switch_state = __root.libinput_event_switch_get_switch_state;
    pub const get_base_event = __root.libinput_event_switch_get_base_event;
    pub const get_time = __root.libinput_event_switch_get_time;
    pub const get_time_usec = __root.libinput_event_switch_get_time_usec;
};
pub const LIBINPUT_EVENT_NONE: c_int = 0;
pub const LIBINPUT_EVENT_DEVICE_ADDED: c_int = 1;
pub const LIBINPUT_EVENT_DEVICE_REMOVED: c_int = 2;
pub const LIBINPUT_EVENT_KEYBOARD_KEY: c_int = 300;
pub const LIBINPUT_EVENT_POINTER_MOTION: c_int = 400;
pub const LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE: c_int = 401;
pub const LIBINPUT_EVENT_POINTER_BUTTON: c_int = 402;
pub const LIBINPUT_EVENT_POINTER_AXIS: c_int = 403;
pub const LIBINPUT_EVENT_POINTER_SCROLL_WHEEL: c_int = 404;
pub const LIBINPUT_EVENT_POINTER_SCROLL_FINGER: c_int = 405;
pub const LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS: c_int = 406;
pub const LIBINPUT_EVENT_TOUCH_DOWN: c_int = 500;
pub const LIBINPUT_EVENT_TOUCH_UP: c_int = 501;
pub const LIBINPUT_EVENT_TOUCH_MOTION: c_int = 502;
pub const LIBINPUT_EVENT_TOUCH_CANCEL: c_int = 503;
pub const LIBINPUT_EVENT_TOUCH_FRAME: c_int = 504;
pub const LIBINPUT_EVENT_TABLET_TOOL_AXIS: c_int = 600;
pub const LIBINPUT_EVENT_TABLET_TOOL_PROXIMITY: c_int = 601;
pub const LIBINPUT_EVENT_TABLET_TOOL_TIP: c_int = 602;
pub const LIBINPUT_EVENT_TABLET_TOOL_BUTTON: c_int = 603;
pub const LIBINPUT_EVENT_TABLET_PAD_BUTTON: c_int = 700;
pub const LIBINPUT_EVENT_TABLET_PAD_RING: c_int = 701;
pub const LIBINPUT_EVENT_TABLET_PAD_STRIP: c_int = 702;
pub const LIBINPUT_EVENT_TABLET_PAD_KEY: c_int = 703;
pub const LIBINPUT_EVENT_TABLET_PAD_DIAL: c_int = 704;
pub const LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN: c_int = 800;
pub const LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE: c_int = 801;
pub const LIBINPUT_EVENT_GESTURE_SWIPE_END: c_int = 802;
pub const LIBINPUT_EVENT_GESTURE_PINCH_BEGIN: c_int = 803;
pub const LIBINPUT_EVENT_GESTURE_PINCH_UPDATE: c_int = 804;
pub const LIBINPUT_EVENT_GESTURE_PINCH_END: c_int = 805;
pub const LIBINPUT_EVENT_GESTURE_HOLD_BEGIN: c_int = 806;
pub const LIBINPUT_EVENT_GESTURE_HOLD_END: c_int = 807;
pub const LIBINPUT_EVENT_SWITCH_TOGGLE: c_int = 900;
pub const enum_libinput_event_type = c_uint;
pub extern fn libinput_event_destroy(event: ?*struct_libinput_event) void;
pub extern fn libinput_event_get_type(event: ?*struct_libinput_event) enum_libinput_event_type;
pub extern fn libinput_event_get_context(event: ?*struct_libinput_event) ?*struct_libinput;
pub extern fn libinput_event_get_device(event: ?*struct_libinput_event) ?*struct_libinput_device;
pub extern fn libinput_event_get_pointer_event(event: ?*struct_libinput_event) ?*struct_libinput_event_pointer;
pub extern fn libinput_event_get_keyboard_event(event: ?*struct_libinput_event) ?*struct_libinput_event_keyboard;
pub extern fn libinput_event_get_touch_event(event: ?*struct_libinput_event) ?*struct_libinput_event_touch;
pub extern fn libinput_event_get_gesture_event(event: ?*struct_libinput_event) ?*struct_libinput_event_gesture;
pub extern fn libinput_event_get_tablet_tool_event(event: ?*struct_libinput_event) ?*struct_libinput_event_tablet_tool;
pub extern fn libinput_event_get_tablet_pad_event(event: ?*struct_libinput_event) ?*struct_libinput_event_tablet_pad;
pub extern fn libinput_event_get_switch_event(event: ?*struct_libinput_event) ?*struct_libinput_event_switch;
pub extern fn libinput_event_get_device_notify_event(event: ?*struct_libinput_event) ?*struct_libinput_event_device_notify;
pub extern fn libinput_event_device_notify_get_base_event(event: ?*struct_libinput_event_device_notify) ?*struct_libinput_event;
pub extern fn libinput_event_keyboard_get_time(event: ?*struct_libinput_event_keyboard) u32;
pub extern fn libinput_event_keyboard_get_time_usec(event: ?*struct_libinput_event_keyboard) u64;
pub extern fn libinput_event_keyboard_get_key(event: ?*struct_libinput_event_keyboard) u32;
pub extern fn libinput_event_keyboard_get_key_state(event: ?*struct_libinput_event_keyboard) enum_libinput_key_state;
pub extern fn libinput_event_keyboard_get_base_event(event: ?*struct_libinput_event_keyboard) ?*struct_libinput_event;
pub extern fn libinput_event_keyboard_get_seat_key_count(event: ?*struct_libinput_event_keyboard) u32;
pub extern fn libinput_event_pointer_get_time(event: ?*struct_libinput_event_pointer) u32;
pub extern fn libinput_event_pointer_get_time_usec(event: ?*struct_libinput_event_pointer) u64;
pub extern fn libinput_event_pointer_get_dx(event: ?*struct_libinput_event_pointer) f64;
pub extern fn libinput_event_pointer_get_dy(event: ?*struct_libinput_event_pointer) f64;
pub extern fn libinput_event_pointer_get_dx_unaccelerated(event: ?*struct_libinput_event_pointer) f64;
pub extern fn libinput_event_pointer_get_dy_unaccelerated(event: ?*struct_libinput_event_pointer) f64;
pub extern fn libinput_event_pointer_get_absolute_x(event: ?*struct_libinput_event_pointer) f64;
pub extern fn libinput_event_pointer_get_absolute_y(event: ?*struct_libinput_event_pointer) f64;
pub extern fn libinput_event_pointer_get_absolute_x_transformed(event: ?*struct_libinput_event_pointer, width: u32) f64;
pub extern fn libinput_event_pointer_get_absolute_y_transformed(event: ?*struct_libinput_event_pointer, height: u32) f64;
pub extern fn libinput_event_pointer_get_button(event: ?*struct_libinput_event_pointer) u32;
pub extern fn libinput_event_pointer_get_button_state(event: ?*struct_libinput_event_pointer) enum_libinput_button_state;
pub extern fn libinput_event_pointer_get_seat_button_count(event: ?*struct_libinput_event_pointer) u32;
pub extern fn libinput_event_pointer_has_axis(event: ?*struct_libinput_event_pointer, axis: enum_libinput_pointer_axis) c_int;
pub extern fn libinput_event_pointer_get_axis_value(event: ?*struct_libinput_event_pointer, axis: enum_libinput_pointer_axis) f64;
pub extern fn libinput_event_pointer_get_axis_source(event: ?*struct_libinput_event_pointer) enum_libinput_pointer_axis_source;
pub extern fn libinput_event_pointer_get_axis_value_discrete(event: ?*struct_libinput_event_pointer, axis: enum_libinput_pointer_axis) f64;
pub extern fn libinput_event_pointer_get_scroll_value(event: ?*struct_libinput_event_pointer, axis: enum_libinput_pointer_axis) f64;
pub extern fn libinput_event_pointer_get_scroll_value_v120(event: ?*struct_libinput_event_pointer, axis: enum_libinput_pointer_axis) f64;
pub extern fn libinput_event_pointer_get_base_event(event: ?*struct_libinput_event_pointer) ?*struct_libinput_event;
pub extern fn libinput_event_touch_get_time(event: ?*struct_libinput_event_touch) u32;
pub extern fn libinput_event_touch_get_time_usec(event: ?*struct_libinput_event_touch) u64;
pub extern fn libinput_event_touch_get_slot(event: ?*struct_libinput_event_touch) i32;
pub extern fn libinput_event_touch_get_seat_slot(event: ?*struct_libinput_event_touch) i32;
pub extern fn libinput_event_touch_get_x(event: ?*struct_libinput_event_touch) f64;
pub extern fn libinput_event_touch_get_y(event: ?*struct_libinput_event_touch) f64;
pub extern fn libinput_event_touch_get_x_transformed(event: ?*struct_libinput_event_touch, width: u32) f64;
pub extern fn libinput_event_touch_get_y_transformed(event: ?*struct_libinput_event_touch, height: u32) f64;
pub extern fn libinput_event_touch_get_base_event(event: ?*struct_libinput_event_touch) ?*struct_libinput_event;
pub extern fn libinput_event_gesture_get_time(event: ?*struct_libinput_event_gesture) u32;
pub extern fn libinput_event_gesture_get_time_usec(event: ?*struct_libinput_event_gesture) u64;
pub extern fn libinput_event_gesture_get_base_event(event: ?*struct_libinput_event_gesture) ?*struct_libinput_event;
pub extern fn libinput_event_gesture_get_finger_count(event: ?*struct_libinput_event_gesture) c_int;
pub extern fn libinput_event_gesture_get_cancelled(event: ?*struct_libinput_event_gesture) c_int;
pub extern fn libinput_event_gesture_get_dx(event: ?*struct_libinput_event_gesture) f64;
pub extern fn libinput_event_gesture_get_dy(event: ?*struct_libinput_event_gesture) f64;
pub extern fn libinput_event_gesture_get_dx_unaccelerated(event: ?*struct_libinput_event_gesture) f64;
pub extern fn libinput_event_gesture_get_dy_unaccelerated(event: ?*struct_libinput_event_gesture) f64;
pub extern fn libinput_event_gesture_get_scale(event: ?*struct_libinput_event_gesture) f64;
pub extern fn libinput_event_gesture_get_angle_delta(event: ?*struct_libinput_event_gesture) f64;
pub extern fn libinput_event_tablet_tool_get_base_event(event: ?*struct_libinput_event_tablet_tool) ?*struct_libinput_event;
pub extern fn libinput_event_tablet_tool_x_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_y_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_pressure_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_distance_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_tilt_x_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_tilt_y_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_rotation_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_slider_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_size_major_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_size_minor_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_wheel_has_changed(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_get_x(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_y(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_dx(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_dy(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_pressure(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_distance(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_tilt_x(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_tilt_y(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_rotation(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_slider_position(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_size_major(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_size_minor(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_wheel_delta(event: ?*struct_libinput_event_tablet_tool) f64;
pub extern fn libinput_event_tablet_tool_get_wheel_delta_discrete(event: ?*struct_libinput_event_tablet_tool) c_int;
pub extern fn libinput_event_tablet_tool_get_x_transformed(event: ?*struct_libinput_event_tablet_tool, width: u32) f64;
pub extern fn libinput_event_tablet_tool_get_y_transformed(event: ?*struct_libinput_event_tablet_tool, height: u32) f64;
pub extern fn libinput_event_tablet_tool_get_tool(event: ?*struct_libinput_event_tablet_tool) ?*struct_libinput_tablet_tool;
pub extern fn libinput_event_tablet_tool_get_proximity_state(event: ?*struct_libinput_event_tablet_tool) enum_libinput_tablet_tool_proximity_state;
pub extern fn libinput_event_tablet_tool_get_tip_state(event: ?*struct_libinput_event_tablet_tool) enum_libinput_tablet_tool_tip_state;
pub extern fn libinput_event_tablet_tool_get_button(event: ?*struct_libinput_event_tablet_tool) u32;
pub extern fn libinput_event_tablet_tool_get_button_state(event: ?*struct_libinput_event_tablet_tool) enum_libinput_button_state;
pub extern fn libinput_event_tablet_tool_get_seat_button_count(event: ?*struct_libinput_event_tablet_tool) u32;
pub extern fn libinput_event_tablet_tool_get_time(event: ?*struct_libinput_event_tablet_tool) u32;
pub extern fn libinput_event_tablet_tool_get_time_usec(event: ?*struct_libinput_event_tablet_tool) u64;
pub extern fn libinput_tablet_tool_get_type(tool: ?*struct_libinput_tablet_tool) enum_libinput_tablet_tool_type;
pub extern fn libinput_tablet_tool_get_tool_id(tool: ?*struct_libinput_tablet_tool) u64;
pub extern fn libinput_tablet_tool_get_name(tool: ?*struct_libinput_tablet_tool) [*c]const u8;
pub extern fn libinput_tablet_tool_ref(tool: ?*struct_libinput_tablet_tool) ?*struct_libinput_tablet_tool;
pub extern fn libinput_tablet_tool_unref(tool: ?*struct_libinput_tablet_tool) ?*struct_libinput_tablet_tool;
pub extern fn libinput_tablet_tool_has_pressure(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_distance(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_tilt(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_rotation(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_slider(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_size(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_wheel(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_has_button(tool: ?*struct_libinput_tablet_tool, code: u32) c_int;
pub extern fn libinput_tablet_tool_is_unique(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_get_serial(tool: ?*struct_libinput_tablet_tool) u64;
pub extern fn libinput_tablet_tool_get_user_data(tool: ?*struct_libinput_tablet_tool) ?*anyopaque;
pub extern fn libinput_tablet_tool_set_user_data(tool: ?*struct_libinput_tablet_tool, user_data: ?*anyopaque) void;
pub extern fn libinput_event_tablet_pad_get_base_event(event: ?*struct_libinput_event_tablet_pad) ?*struct_libinput_event;
pub extern fn libinput_event_tablet_pad_get_ring_position(event: ?*struct_libinput_event_tablet_pad) f64;
pub extern fn libinput_event_tablet_pad_get_ring_number(event: ?*struct_libinput_event_tablet_pad) c_uint;
pub extern fn libinput_event_tablet_pad_get_ring_source(event: ?*struct_libinput_event_tablet_pad) enum_libinput_tablet_pad_ring_axis_source;
pub extern fn libinput_event_tablet_pad_get_strip_position(event: ?*struct_libinput_event_tablet_pad) f64;
pub extern fn libinput_event_tablet_pad_get_strip_number(event: ?*struct_libinput_event_tablet_pad) c_uint;
pub extern fn libinput_event_tablet_pad_get_strip_source(event: ?*struct_libinput_event_tablet_pad) enum_libinput_tablet_pad_strip_axis_source;
pub extern fn libinput_event_tablet_pad_get_button_number(event: ?*struct_libinput_event_tablet_pad) u32;
pub extern fn libinput_event_tablet_pad_get_button_state(event: ?*struct_libinput_event_tablet_pad) enum_libinput_button_state;
pub extern fn libinput_event_tablet_pad_get_key(event: ?*struct_libinput_event_tablet_pad) u32;
pub extern fn libinput_event_tablet_pad_get_key_state(event: ?*struct_libinput_event_tablet_pad) enum_libinput_key_state;
pub extern fn libinput_event_tablet_pad_get_dial_delta_v120(event: ?*struct_libinput_event_tablet_pad) f64;
pub extern fn libinput_event_tablet_pad_get_dial_number(event: ?*struct_libinput_event_tablet_pad) c_uint;
pub extern fn libinput_event_tablet_pad_get_mode(event: ?*struct_libinput_event_tablet_pad) c_uint;
pub extern fn libinput_event_tablet_pad_get_mode_group(event: ?*struct_libinput_event_tablet_pad) ?*struct_libinput_tablet_pad_mode_group;
pub extern fn libinput_event_tablet_pad_get_time(event: ?*struct_libinput_event_tablet_pad) u32;
pub extern fn libinput_event_tablet_pad_get_time_usec(event: ?*struct_libinput_event_tablet_pad) u64;
pub extern fn libinput_event_switch_get_switch(event: ?*struct_libinput_event_switch) enum_libinput_switch;
pub extern fn libinput_event_switch_get_switch_state(event: ?*struct_libinput_event_switch) enum_libinput_switch_state;
pub extern fn libinput_event_switch_get_base_event(event: ?*struct_libinput_event_switch) ?*struct_libinput_event;
pub extern fn libinput_event_switch_get_time(event: ?*struct_libinput_event_switch) u32;
pub extern fn libinput_event_switch_get_time_usec(event: ?*struct_libinput_event_switch) u64;
pub const struct_libinput_interface = extern struct {
    open_restricted: ?*const fn (path: [*c]const u8, flags: c_int, user_data: ?*anyopaque) callconv(.c) c_int,
    close_restricted: ?*const fn (fd: c_int, user_data: ?*anyopaque) callconv(.c) void,
    pub const libinput_udev_create_context = __root.libinput_udev_create_context;
    pub const libinput_path_create_context = __root.libinput_path_create_context;
    pub const context = __root.libinput_udev_create_context;
};
pub extern fn libinput_udev_create_context(interface: [*c]const struct_libinput_interface, user_data: ?*anyopaque, udev: ?*struct_udev) ?*struct_libinput;
pub extern fn libinput_udev_assign_seat(libinput: ?*struct_libinput, seat_id: [*c]const u8) c_int;
pub extern fn libinput_path_create_context(interface: [*c]const struct_libinput_interface, user_data: ?*anyopaque) ?*struct_libinput;
pub extern fn libinput_path_add_device(libinput: ?*struct_libinput, path: [*c]const u8) ?*struct_libinput_device;
pub extern fn libinput_path_remove_device(device: ?*struct_libinput_device) void;
pub extern fn libinput_plugin_system_append_path(libinput: ?*struct_libinput, path: [*c]const u8) void;
pub extern fn libinput_plugin_system_append_default_paths(libinput: ?*struct_libinput) void;
pub const LIBINPUT_PLUGIN_SYSTEM_FLAG_NONE: c_int = 0;
pub const enum_libinput_plugin_system_flags = c_uint;
pub extern fn libinput_plugin_system_load_plugins(libinput: ?*struct_libinput, flags: enum_libinput_plugin_system_flags) c_int;
pub extern fn libinput_get_fd(libinput: ?*struct_libinput) c_int;
pub extern fn libinput_dispatch(libinput: ?*struct_libinput) c_int;
pub extern fn libinput_get_event(libinput: ?*struct_libinput) ?*struct_libinput_event;
pub extern fn libinput_next_event_type(libinput: ?*struct_libinput) enum_libinput_event_type;
pub extern fn libinput_set_user_data(libinput: ?*struct_libinput, user_data: ?*anyopaque) void;
pub extern fn libinput_get_user_data(libinput: ?*struct_libinput) ?*anyopaque;
pub extern fn libinput_resume(libinput: ?*struct_libinput) c_int;
pub extern fn libinput_suspend(libinput: ?*struct_libinput) void;
pub extern fn libinput_ref(libinput: ?*struct_libinput) ?*struct_libinput;
pub extern fn libinput_unref(libinput: ?*struct_libinput) ?*struct_libinput;
pub extern fn libinput_log_set_priority(libinput: ?*struct_libinput, priority: enum_libinput_log_priority) void;
pub extern fn libinput_log_get_priority(libinput: ?*const struct_libinput) enum_libinput_log_priority;
pub const libinput_log_handler = ?*const fn (libinput: ?*struct_libinput, priority: enum_libinput_log_priority, format: [*c]const u8, args: [*c]struct___va_list_tag_3) callconv(.c) void;
pub extern fn libinput_log_set_handler(libinput: ?*struct_libinput, log_handler: libinput_log_handler) void;
pub extern fn libinput_seat_ref(seat: ?*struct_libinput_seat) ?*struct_libinput_seat;
pub extern fn libinput_seat_unref(seat: ?*struct_libinput_seat) ?*struct_libinput_seat;
pub extern fn libinput_seat_set_user_data(seat: ?*struct_libinput_seat, user_data: ?*anyopaque) void;
pub extern fn libinput_seat_get_user_data(seat: ?*struct_libinput_seat) ?*anyopaque;
pub extern fn libinput_seat_get_context(seat: ?*struct_libinput_seat) ?*struct_libinput;
pub extern fn libinput_seat_get_physical_name(seat: ?*struct_libinput_seat) [*c]const u8;
pub extern fn libinput_seat_get_logical_name(seat: ?*struct_libinput_seat) [*c]const u8;
pub extern fn libinput_device_ref(device: ?*struct_libinput_device) ?*struct_libinput_device;
pub extern fn libinput_device_unref(device: ?*struct_libinput_device) ?*struct_libinput_device;
pub extern fn libinput_device_set_user_data(device: ?*struct_libinput_device, user_data: ?*anyopaque) void;
pub extern fn libinput_device_get_user_data(device: ?*struct_libinput_device) ?*anyopaque;
pub extern fn libinput_device_get_context(device: ?*struct_libinput_device) ?*struct_libinput;
pub extern fn libinput_device_get_device_group(device: ?*struct_libinput_device) ?*struct_libinput_device_group;
pub extern fn libinput_device_get_sysname(device: ?*struct_libinput_device) [*c]const u8;
pub extern fn libinput_device_get_name(device: ?*struct_libinput_device) [*c]const u8;
pub extern fn libinput_device_get_id_bustype(device: ?*struct_libinput_device) c_uint;
pub extern fn libinput_device_get_id_product(device: ?*struct_libinput_device) c_uint;
pub extern fn libinput_device_get_id_vendor(device: ?*struct_libinput_device) c_uint;
pub extern fn libinput_device_get_output_name(device: ?*struct_libinput_device) [*c]const u8;
pub extern fn libinput_device_get_seat(device: ?*struct_libinput_device) ?*struct_libinput_seat;
pub extern fn libinput_device_set_seat_logical_name(device: ?*struct_libinput_device, name: [*c]const u8) c_int;
pub extern fn libinput_device_get_udev_device(device: ?*struct_libinput_device) ?*struct_udev_device;
pub extern fn libinput_device_led_update(device: ?*struct_libinput_device, leds: enum_libinput_led) void;
pub extern fn libinput_device_has_capability(device: ?*struct_libinput_device, capability: enum_libinput_device_capability) c_int;
pub extern fn libinput_device_get_size(device: ?*struct_libinput_device, width: [*c]f64, height: [*c]f64) c_int;
pub extern fn libinput_device_pointer_has_button(device: ?*struct_libinput_device, code: u32) c_int;
pub extern fn libinput_device_keyboard_has_key(device: ?*struct_libinput_device, code: u32) c_int;
pub extern fn libinput_device_touch_get_touch_count(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_switch_has_switch(device: ?*struct_libinput_device, sw: enum_libinput_switch) c_int;
pub extern fn libinput_device_tablet_pad_get_num_buttons(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_tablet_pad_get_num_dials(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_tablet_pad_get_num_rings(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_tablet_pad_get_num_strips(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_tablet_pad_has_key(device: ?*struct_libinput_device, code: u32) c_int;
pub extern fn libinput_device_group_ref(group: ?*struct_libinput_device_group) ?*struct_libinput_device_group;
pub extern fn libinput_device_group_unref(group: ?*struct_libinput_device_group) ?*struct_libinput_device_group;
pub extern fn libinput_device_group_set_user_data(group: ?*struct_libinput_device_group, user_data: ?*anyopaque) void;
pub extern fn libinput_device_group_get_user_data(group: ?*struct_libinput_device_group) ?*anyopaque;
pub const LIBINPUT_CONFIG_STATUS_SUCCESS: c_int = 0;
pub const LIBINPUT_CONFIG_STATUS_UNSUPPORTED: c_int = 1;
pub const LIBINPUT_CONFIG_STATUS_INVALID: c_int = 2;
pub const enum_libinput_config_status = c_uint;
pub extern fn libinput_config_status_to_str(status: enum_libinput_config_status) [*c]const u8;
pub const LIBINPUT_CONFIG_TAP_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_TAP_ENABLED: c_int = 1;
pub const enum_libinput_config_tap_state = c_uint;
pub extern fn libinput_device_config_tap_get_finger_count(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_tap_set_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_tap_state) enum_libinput_config_status;
pub extern fn libinput_device_config_tap_get_enabled(device: ?*struct_libinput_device) enum_libinput_config_tap_state;
pub extern fn libinput_device_config_tap_get_default_enabled(device: ?*struct_libinput_device) enum_libinput_config_tap_state;
pub const LIBINPUT_CONFIG_TAP_MAP_LRM: c_int = 0;
pub const LIBINPUT_CONFIG_TAP_MAP_LMR: c_int = 1;
pub const enum_libinput_config_tap_button_map = c_uint;
pub const LIBINPUT_CONFIG_CLICKFINGER_MAP_LRM: c_int = 0;
pub const LIBINPUT_CONFIG_CLICKFINGER_MAP_LMR: c_int = 1;
pub const enum_libinput_config_clickfinger_button_map = c_uint;
pub extern fn libinput_device_config_tap_set_button_map(device: ?*struct_libinput_device, map: enum_libinput_config_tap_button_map) enum_libinput_config_status;
pub extern fn libinput_device_config_tap_get_button_map(device: ?*struct_libinput_device) enum_libinput_config_tap_button_map;
pub extern fn libinput_device_config_tap_get_default_button_map(device: ?*struct_libinput_device) enum_libinput_config_tap_button_map;
pub const LIBINPUT_CONFIG_DRAG_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_DRAG_ENABLED: c_int = 1;
pub const enum_libinput_config_drag_state = c_uint;
pub extern fn libinput_device_config_tap_set_drag_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_drag_state) enum_libinput_config_status;
pub extern fn libinput_device_config_tap_get_drag_enabled(device: ?*struct_libinput_device) enum_libinput_config_drag_state;
pub extern fn libinput_device_config_tap_get_default_drag_enabled(device: ?*struct_libinput_device) enum_libinput_config_drag_state;
pub const LIBINPUT_CONFIG_DRAG_LOCK_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_DRAG_LOCK_ENABLED_TIMEOUT: c_int = 1;
pub const LIBINPUT_CONFIG_DRAG_LOCK_ENABLED: c_int = 1;
pub const LIBINPUT_CONFIG_DRAG_LOCK_ENABLED_STICKY: c_int = 2;
pub const enum_libinput_config_drag_lock_state = c_uint;
pub extern fn libinput_device_config_tap_set_drag_lock_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_drag_lock_state) enum_libinput_config_status;
pub extern fn libinput_device_config_tap_get_drag_lock_enabled(device: ?*struct_libinput_device) enum_libinput_config_drag_lock_state;
pub extern fn libinput_device_config_tap_get_default_drag_lock_enabled(device: ?*struct_libinput_device) enum_libinput_config_drag_lock_state;
pub const LIBINPUT_CONFIG_3FG_DRAG_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_3FG_DRAG_ENABLED_3FG: c_int = 1;
pub const LIBINPUT_CONFIG_3FG_DRAG_ENABLED_4FG: c_int = 2;
pub const enum_libinput_config_3fg_drag_state = c_uint;
pub extern fn libinput_device_config_3fg_drag_get_finger_count(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_3fg_drag_set_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_3fg_drag_state) enum_libinput_config_status;
pub extern fn libinput_device_config_3fg_drag_get_enabled(device: ?*struct_libinput_device) enum_libinput_config_3fg_drag_state;
pub extern fn libinput_device_config_3fg_drag_get_default_enabled(device: ?*struct_libinput_device) enum_libinput_config_3fg_drag_state;
pub extern fn libinput_device_config_calibration_has_matrix(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_calibration_set_matrix(device: ?*struct_libinput_device, matrix: [*c]const f32) enum_libinput_config_status;
pub extern fn libinput_device_config_calibration_get_matrix(device: ?*struct_libinput_device, matrix: [*c]f32) c_int;
pub extern fn libinput_device_config_calibration_get_default_matrix(device: ?*struct_libinput_device, matrix: [*c]f32) c_int;
pub const struct_libinput_config_area_rectangle = extern struct {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
};
pub extern fn libinput_device_config_area_has_rectangle(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_area_set_rectangle(device: ?*struct_libinput_device, rect: [*c]const struct_libinput_config_area_rectangle) enum_libinput_config_status;
pub extern fn libinput_device_config_area_get_rectangle(device: ?*struct_libinput_device) struct_libinput_config_area_rectangle;
pub extern fn libinput_device_config_area_get_default_rectangle(device: ?*struct_libinput_device) struct_libinput_config_area_rectangle;
pub const LIBINPUT_CONFIG_SEND_EVENTS_ENABLED: c_int = 0;
pub const LIBINPUT_CONFIG_SEND_EVENTS_DISABLED: c_int = 1;
pub const LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE: c_int = 2;
pub const enum_libinput_config_send_events_mode = c_uint;
pub extern fn libinput_device_config_send_events_get_modes(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_send_events_set_mode(device: ?*struct_libinput_device, mode: u32) enum_libinput_config_status;
pub extern fn libinput_device_config_send_events_get_mode(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_send_events_get_default_mode(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_accel_is_available(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_accel_set_speed(device: ?*struct_libinput_device, speed: f64) enum_libinput_config_status;
pub extern fn libinput_device_config_accel_get_speed(device: ?*struct_libinput_device) f64;
pub extern fn libinput_device_config_accel_get_default_speed(device: ?*struct_libinput_device) f64;
pub const LIBINPUT_CONFIG_ACCEL_PROFILE_NONE: c_int = 0;
pub const LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT: c_int = 1;
pub const LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE: c_int = 2;
pub const LIBINPUT_CONFIG_ACCEL_PROFILE_CUSTOM: c_int = 4;
pub const enum_libinput_config_accel_profile = c_uint;
pub const struct_libinput_config_accel = opaque {
    pub const libinput_config_accel_destroy = __root.libinput_config_accel_destroy;
    pub const libinput_config_accel_set_points = __root.libinput_config_accel_set_points;
    pub const destroy = __root.libinput_config_accel_destroy;
    pub const set_points = __root.libinput_config_accel_set_points;
};
pub extern fn libinput_config_accel_create(profile: enum_libinput_config_accel_profile) ?*struct_libinput_config_accel;
pub extern fn libinput_config_accel_destroy(accel_config: ?*struct_libinput_config_accel) void;
pub extern fn libinput_device_config_accel_apply(device: ?*struct_libinput_device, accel_config: ?*struct_libinput_config_accel) enum_libinput_config_status;
pub const LIBINPUT_ACCEL_TYPE_FALLBACK: c_int = 0;
pub const LIBINPUT_ACCEL_TYPE_MOTION: c_int = 1;
pub const LIBINPUT_ACCEL_TYPE_SCROLL: c_int = 2;
pub const enum_libinput_config_accel_type = c_uint;
pub extern fn libinput_config_accel_set_points(accel_config: ?*struct_libinput_config_accel, accel_type: enum_libinput_config_accel_type, step: f64, npoints: usize, points: [*c]const f64) enum_libinput_config_status;
pub extern fn libinput_device_config_accel_get_profiles(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_accel_set_profile(device: ?*struct_libinput_device, profile: enum_libinput_config_accel_profile) enum_libinput_config_status;
pub extern fn libinput_device_config_accel_get_profile(device: ?*struct_libinput_device) enum_libinput_config_accel_profile;
pub extern fn libinput_device_config_accel_get_default_profile(device: ?*struct_libinput_device) enum_libinput_config_accel_profile;
pub extern fn libinput_device_config_scroll_has_natural_scroll(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_scroll_set_natural_scroll_enabled(device: ?*struct_libinput_device, enable: c_int) enum_libinput_config_status;
pub extern fn libinput_device_config_scroll_get_natural_scroll_enabled(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_scroll_get_default_natural_scroll_enabled(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_left_handed_is_available(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_left_handed_set(device: ?*struct_libinput_device, left_handed: c_int) enum_libinput_config_status;
pub extern fn libinput_device_config_left_handed_get(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_left_handed_get_default(device: ?*struct_libinput_device) c_int;
pub const LIBINPUT_CONFIG_CLICK_METHOD_NONE: c_int = 0;
pub const LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS: c_int = 1;
pub const LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER: c_int = 2;
pub const enum_libinput_config_click_method = c_uint;
pub extern fn libinput_device_config_click_get_methods(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_click_set_method(device: ?*struct_libinput_device, method: enum_libinput_config_click_method) enum_libinput_config_status;
pub extern fn libinput_device_config_click_get_method(device: ?*struct_libinput_device) enum_libinput_config_click_method;
pub extern fn libinput_device_config_click_get_default_method(device: ?*struct_libinput_device) enum_libinput_config_click_method;
pub extern fn libinput_device_config_click_set_clickfinger_button_map(device: ?*struct_libinput_device, map: enum_libinput_config_clickfinger_button_map) enum_libinput_config_status;
pub extern fn libinput_device_config_click_get_clickfinger_button_map(device: ?*struct_libinput_device) enum_libinput_config_clickfinger_button_map;
pub extern fn libinput_device_config_click_get_default_clickfinger_button_map(device: ?*struct_libinput_device) enum_libinput_config_clickfinger_button_map;
pub const LIBINPUT_CONFIG_MIDDLE_EMULATION_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_MIDDLE_EMULATION_ENABLED: c_int = 1;
pub const enum_libinput_config_middle_emulation_state = c_uint;
pub extern fn libinput_device_config_middle_emulation_is_available(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_middle_emulation_set_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_middle_emulation_state) enum_libinput_config_status;
pub extern fn libinput_device_config_middle_emulation_get_enabled(device: ?*struct_libinput_device) enum_libinput_config_middle_emulation_state;
pub extern fn libinput_device_config_middle_emulation_get_default_enabled(device: ?*struct_libinput_device) enum_libinput_config_middle_emulation_state;
pub const LIBINPUT_CONFIG_SCROLL_NO_SCROLL: c_int = 0;
pub const LIBINPUT_CONFIG_SCROLL_2FG: c_int = 1;
pub const LIBINPUT_CONFIG_SCROLL_EDGE: c_int = 2;
pub const LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN: c_int = 4;
pub const enum_libinput_config_scroll_method = c_uint;
pub extern fn libinput_device_config_scroll_get_methods(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_scroll_set_method(device: ?*struct_libinput_device, method: enum_libinput_config_scroll_method) enum_libinput_config_status;
pub extern fn libinput_device_config_scroll_get_method(device: ?*struct_libinput_device) enum_libinput_config_scroll_method;
pub extern fn libinput_device_config_scroll_get_default_method(device: ?*struct_libinput_device) enum_libinput_config_scroll_method;
pub extern fn libinput_device_config_scroll_set_button(device: ?*struct_libinput_device, button: u32) enum_libinput_config_status;
pub extern fn libinput_device_config_scroll_get_button(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_scroll_get_default_button(device: ?*struct_libinput_device) u32;
pub const LIBINPUT_CONFIG_SCROLL_BUTTON_LOCK_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_SCROLL_BUTTON_LOCK_ENABLED: c_int = 1;
pub const enum_libinput_config_scroll_button_lock_state = c_uint;
pub extern fn libinput_device_config_scroll_set_button_lock(device: ?*struct_libinput_device, state: enum_libinput_config_scroll_button_lock_state) enum_libinput_config_status;
pub extern fn libinput_device_config_scroll_get_button_lock(device: ?*struct_libinput_device) enum_libinput_config_scroll_button_lock_state;
pub extern fn libinput_device_config_scroll_get_default_button_lock(device: ?*struct_libinput_device) enum_libinput_config_scroll_button_lock_state;
pub const LIBINPUT_CONFIG_DWT_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_DWT_ENABLED: c_int = 1;
pub const enum_libinput_config_dwt_state = c_uint;
pub extern fn libinput_device_config_dwt_is_available(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_dwt_set_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_dwt_state) enum_libinput_config_status;
pub extern fn libinput_device_config_dwt_get_enabled(device: ?*struct_libinput_device) enum_libinput_config_dwt_state;
pub extern fn libinput_device_config_dwt_get_default_enabled(device: ?*struct_libinput_device) enum_libinput_config_dwt_state;
pub extern fn libinput_device_config_dwt_set_timeout(device: ?*struct_libinput_device, millis: u32) enum_libinput_config_status;
pub extern fn libinput_device_config_dwt_get_timeout(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_dwt_get_default_timeout(device: ?*struct_libinput_device) u32;
pub const LIBINPUT_CONFIG_DWTP_DISABLED: c_int = 0;
pub const LIBINPUT_CONFIG_DWTP_ENABLED: c_int = 1;
pub const enum_libinput_config_dwtp_state = c_uint;
pub extern fn libinput_device_config_dwtp_is_available(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_dwtp_set_enabled(device: ?*struct_libinput_device, enable: enum_libinput_config_dwtp_state) enum_libinput_config_status;
pub extern fn libinput_device_config_dwtp_get_enabled(device: ?*struct_libinput_device) enum_libinput_config_dwtp_state;
pub extern fn libinput_device_config_dwtp_get_default_enabled(device: ?*struct_libinput_device) enum_libinput_config_dwtp_state;
pub extern fn libinput_device_config_dwtp_set_timeout(device: ?*struct_libinput_device, millis: u32) enum_libinput_config_status;
pub extern fn libinput_device_config_dwtp_get_timeout(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_dwtp_get_default_timeout(device: ?*struct_libinput_device) u32;
pub extern fn libinput_device_config_rotation_is_available(device: ?*struct_libinput_device) c_int;
pub extern fn libinput_device_config_rotation_set_angle(device: ?*struct_libinput_device, degrees_cw: c_uint) enum_libinput_config_status;
pub extern fn libinput_device_config_rotation_get_angle(device: ?*struct_libinput_device) c_uint;
pub extern fn libinput_device_config_rotation_get_default_angle(device: ?*struct_libinput_device) c_uint;
pub extern fn libinput_tablet_tool_config_pressure_range_is_available(tool: ?*struct_libinput_tablet_tool) c_int;
pub extern fn libinput_tablet_tool_config_pressure_range_set(tool: ?*struct_libinput_tablet_tool, minimum: f64, maximum: f64) enum_libinput_config_status;
pub extern fn libinput_tablet_tool_config_pressure_range_get_minimum(tool: ?*struct_libinput_tablet_tool) f64;
pub extern fn libinput_tablet_tool_config_pressure_range_get_maximum(tool: ?*struct_libinput_tablet_tool) f64;
pub extern fn libinput_tablet_tool_config_pressure_range_get_default_minimum(tool: ?*struct_libinput_tablet_tool) f64;
pub extern fn libinput_tablet_tool_config_pressure_range_get_default_maximum(tool: ?*struct_libinput_tablet_tool) f64;
pub const LIBINPUT_CONFIG_ERASER_BUTTON_DEFAULT: c_int = 0;
pub const LIBINPUT_CONFIG_ERASER_BUTTON_BUTTON: c_int = 1;
pub const enum_libinput_config_eraser_button_mode = c_uint;
pub extern fn libinput_tablet_tool_config_eraser_button_get_modes(tool: ?*struct_libinput_tablet_tool) u32;
pub extern fn libinput_tablet_tool_config_eraser_button_set_mode(tool: ?*struct_libinput_tablet_tool, mode: enum_libinput_config_eraser_button_mode) enum_libinput_config_status;
pub extern fn libinput_tablet_tool_config_eraser_button_get_mode(tool: ?*struct_libinput_tablet_tool) enum_libinput_config_eraser_button_mode;
pub extern fn libinput_tablet_tool_config_eraser_button_get_default_mode(tool: ?*struct_libinput_tablet_tool) enum_libinput_config_eraser_button_mode;
pub extern fn libinput_tablet_tool_config_eraser_button_set_button(tool: ?*struct_libinput_tablet_tool, button: u32) enum_libinput_config_status;
pub extern fn libinput_tablet_tool_config_eraser_button_get_button(tool: ?*struct_libinput_tablet_tool) c_uint;
pub extern fn libinput_tablet_tool_config_eraser_button_get_default_button(tool: ?*struct_libinput_tablet_tool) c_uint;

pub const __VERSION__ = "Aro 0.0.0";
pub const __Aro__ = "";
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const __STDC_EMBED_NOT_FOUND__ = @as(c_int, 0);
pub const __STDC_EMBED_FOUND__ = @as(c_int, 1);
pub const __STDC_EMBED_EMPTY__ = @as(c_int, 2);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __GNUC__ = @as(c_int, 7);
pub const __GNUC_MINOR__ = @as(c_int, 1);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 0);
pub const __ARO_EMULATE_NO__ = @as(c_int, 0);
pub const __ARO_EMULATE_CLANG__ = @as(c_int, 1);
pub const __ARO_EMULATE_GCC__ = @as(c_int, 2);
pub const __ARO_EMULATE_MSVC__ = @as(c_int, 3);
pub const __ARO_EMULATE__ = __ARO_EMULATE_NO__;
pub inline fn __building_module(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub const linux = @as(c_int, 1);
pub const __linux = @as(c_int, 1);
pub const __linux__ = @as(c_int, 1);
pub const unix = @as(c_int, 1);
pub const __unix = @as(c_int, 1);
pub const __unix__ = @as(c_int, 1);
pub const __code_model_small__ = @as(c_int, 1);
pub const __amd64__ = @as(c_int, 1);
pub const __amd64 = @as(c_int, 1);
pub const __x86_64__ = @as(c_int, 1);
pub const __x86_64 = @as(c_int, 1);
pub const __SEG_GS = @as(c_int, 1);
pub const __SEG_FS = @as(c_int, 1);
pub const __seg_gs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:33:9
pub const __seg_fs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:34:9
pub const __LAHF_SAHF__ = @as(c_int, 1);
pub const __AES__ = @as(c_int, 1);
pub const __VAES__ = @as(c_int, 1);
pub const __PCLMUL__ = @as(c_int, 1);
pub const __VPCLMULQDQ__ = @as(c_int, 1);
pub const __LZCNT__ = @as(c_int, 1);
pub const __RDRND__ = @as(c_int, 1);
pub const __FSGSBASE__ = @as(c_int, 1);
pub const __BMI__ = @as(c_int, 1);
pub const __BMI2__ = @as(c_int, 1);
pub const __POPCNT__ = @as(c_int, 1);
pub const __PRFCHW__ = @as(c_int, 1);
pub const __RDSEED__ = @as(c_int, 1);
pub const __ADX__ = @as(c_int, 1);
pub const __MOVBE__ = @as(c_int, 1);
pub const __FMA__ = @as(c_int, 1);
pub const __F16C__ = @as(c_int, 1);
pub const __GFNI__ = @as(c_int, 1);
pub const __SHA__ = @as(c_int, 1);
pub const __FXSR__ = @as(c_int, 1);
pub const __XSAVE__ = @as(c_int, 1);
pub const __XSAVEOPT__ = @as(c_int, 1);
pub const __XSAVEC__ = @as(c_int, 1);
pub const __XSAVES__ = @as(c_int, 1);
pub const __PKU__ = @as(c_int, 1);
pub const __CLFLUSHOPT__ = @as(c_int, 1);
pub const __CLWB__ = @as(c_int, 1);
pub const __SHSTK__ = @as(c_int, 1);
pub const __RDPID__ = @as(c_int, 1);
pub const __WAITPKG__ = @as(c_int, 1);
pub const __MOVDIRI__ = @as(c_int, 1);
pub const __MOVDIR64B__ = @as(c_int, 1);
pub const __PTWRITE__ = @as(c_int, 1);
pub const __INVPCID__ = @as(c_int, 1);
pub const __HRESET__ = @as(c_int, 1);
pub const __AVXVNNI__ = @as(c_int, 1);
pub const __SERIALIZE__ = @as(c_int, 1);
pub const __CRC32__ = @as(c_int, 1);
pub const __AVX2__ = @as(c_int, 1);
pub const __AVX__ = @as(c_int, 1);
pub const __SSE4_2__ = @as(c_int, 1);
pub const __SSE4_1__ = @as(c_int, 1);
pub const __SSSE3__ = @as(c_int, 1);
pub const __SSE3__ = @as(c_int, 1);
pub const __SSE2__ = @as(c_int, 1);
pub const __SSE__ = @as(c_int, 1);
pub const __SSE_MATH__ = @as(c_int, 1);
pub const __MMX__ = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = @as(c_int, 1);
pub const __SIZEOF_FLOAT128__ = @as(c_int, 16);
pub const _LP64 = @as(c_int, 1);
pub const __LP64__ = @as(c_int, 1);
pub const __FLOAT128__ = @as(c_int, 1);
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const __ELF__ = @as(c_int, 1);
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __ATOMIC_BOOL_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WINT_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_SHORT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_INT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LLONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_POINTER_LOCK_FREE = @as(c_int, 1);
pub const __WINT_UNSIGNED__ = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 8);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SCHAR_WIDTH__ = @as(c_int, 8);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_WIDTH__ = @as(c_int, 64);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __LONG_LONG_WIDTH__ = @as(c_int, 64);
pub const __WCHAR_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __WINT_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIG_ATOMIC_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __BITINT_MAXWIDTH__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 10);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 8);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 4);
pub const __SIZEOF_WINT_T__ = @as(c_int, 4);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTPTR_TYPE__ = c_long;
pub const __UINTPTR_TYPE__ = c_ulong;
pub const __INTMAX_TYPE__ = c_long;
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:160:9
pub const __INTMAX_C = __helpers.L_SUFFIX;
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:163:9
pub const __UINTMAX_C = __helpers.UL_SUFFIX;
pub const __PTRDIFF_TYPE__ = c_long;
pub const __SIZE_TYPE__ = c_ulong;
pub const __WCHAR_TYPE__ = c_int;
pub const __WINT_TYPE__ = c_uint;
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub inline fn __INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub inline fn __INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub inline fn __INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT64_TYPE__ = c_long;
pub const __INT64_FMTd__ = "ld";
pub const __INT64_FMTi__ = "li";
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:189:9
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub inline fn __UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub inline fn __UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`"); // <builtin>:214:9
pub const __UINT32_C = __helpers.U_SUFFIX;
pub const __UINT32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulong;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:223:9
pub const __UINT64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __INT64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const INT_LEAST8_FMTd__ = "hhd";
pub const INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const UINT_LEAST8_FMTo__ = "hho";
pub const UINT_LEAST8_FMTu__ = "hhu";
pub const UINT_LEAST8_FMTx__ = "hhx";
pub const UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const INT_FAST8_FMTd__ = "hhd";
pub const INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const UINT_FAST8_FMTo__ = "hho";
pub const UINT_FAST8_FMTu__ = "hhu";
pub const UINT_FAST8_FMTx__ = "hhx";
pub const UINT_FAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const INT_LEAST16_FMTd__ = "hd";
pub const INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST16_FMTo__ = "ho";
pub const UINT_LEAST16_FMTu__ = "hu";
pub const UINT_LEAST16_FMTx__ = "hx";
pub const UINT_LEAST16_FMTX__ = "hX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const INT_FAST16_FMTd__ = "hd";
pub const INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_FAST16_FMTo__ = "ho";
pub const UINT_FAST16_FMTu__ = "hu";
pub const UINT_FAST16_FMTx__ = "hx";
pub const UINT_FAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const INT_LEAST32_FMTd__ = "d";
pub const INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST32_FMTo__ = "o";
pub const UINT_LEAST32_FMTu__ = "u";
pub const UINT_LEAST32_FMTx__ = "x";
pub const UINT_LEAST32_FMTX__ = "X";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const INT_FAST32_FMTd__ = "d";
pub const INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_FAST32_FMTo__ = "o";
pub const UINT_FAST32_FMTu__ = "u";
pub const UINT_FAST32_FMTx__ = "x";
pub const UINT_FAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_long;
pub const __INT_LEAST64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const INT_LEAST64_FMTd__ = "ld";
pub const INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_TYPE__ = c_ulong;
pub const __UINT_LEAST64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_LEAST64_FMTo__ = "lo";
pub const UINT_LEAST64_FMTu__ = "lu";
pub const UINT_LEAST64_FMTx__ = "lx";
pub const UINT_LEAST64_FMTX__ = "lX";
pub const __INT_FAST64_TYPE__ = c_long;
pub const __INT_FAST64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const INT_FAST64_FMTd__ = "ld";
pub const INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_TYPE__ = c_ulong;
pub const __UINT_FAST64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST64_FMTo__ = "lo";
pub const UINT_FAST64_FMTu__ = "lu";
pub const UINT_FAST64_FMTx__ = "lx";
pub const UINT_FAST64_FMTX__ = "lX";
pub const __FLT16_DENORM_MIN__ = @as(f16, 5.9604644775390625e-8);
pub const __FLT16_HAS_DENORM__ = "";
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_EPSILON__ = @as(f16, 9.765625e-4);
pub const __FLT16_HAS_INFINITY__ = "";
pub const __FLT16_HAS_QUIET_NAN__ = "";
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT16_MIN__ = @as(f16, 6.103515625e-5);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = "";
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = "";
pub const __FLT_HAS_QUIET_NAN__ = "";
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_HAS_DENORM__ = "";
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = "";
pub const __DBL_HAS_QUIET_NAN__ = "";
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 3.64519953188247460253e-4951);
pub const __LDBL_HAS_DENORM__ = "";
pub const __LDBL_DIG__ = @as(c_int, 18);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 21);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.08420217248550443401e-19);
pub const __LDBL_HAS_INFINITY__ = "";
pub const __LDBL_HAS_QUIET_NAN__ = "";
pub const __LDBL_MANT_DIG__ = @as(c_int, 64);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 4932);
pub const __LDBL_MAX_EXP__ = @as(c_int, 16384);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176502e+4932);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 4931);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 16381);
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626e-4932);
pub const __FLT_EVAL_METHOD__ = @as(c_int, 0);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const _INPUT_EVENT_CODES_H = "";
pub const INPUT_PROP_POINTER = @as(c_int, 0x00);
pub const INPUT_PROP_DIRECT = @as(c_int, 0x01);
pub const INPUT_PROP_BUTTONPAD = @as(c_int, 0x02);
pub const INPUT_PROP_SEMI_MT = @as(c_int, 0x03);
pub const INPUT_PROP_TOPBUTTONPAD = @as(c_int, 0x04);
pub const INPUT_PROP_POINTING_STICK = @as(c_int, 0x05);
pub const INPUT_PROP_ACCELEROMETER = @as(c_int, 0x06);
pub const INPUT_PROP_PRESSUREPAD = @as(c_int, 0x07);
pub const INPUT_PROP_MAX = @as(c_int, 0x1f);
pub const INPUT_PROP_CNT = INPUT_PROP_MAX + @as(c_int, 1);
pub const EV_SYN = @as(c_int, 0x00);
pub const EV_KEY = @as(c_int, 0x01);
pub const EV_REL = @as(c_int, 0x02);
pub const EV_ABS = @as(c_int, 0x03);
pub const EV_MSC = @as(c_int, 0x04);
pub const EV_SW = @as(c_int, 0x05);
pub const EV_LED = @as(c_int, 0x11);
pub const EV_SND = @as(c_int, 0x12);
pub const EV_REP = @as(c_int, 0x14);
pub const EV_FF = @as(c_int, 0x15);
pub const EV_PWR = @as(c_int, 0x16);
pub const EV_FF_STATUS = @as(c_int, 0x17);
pub const EV_MAX = @as(c_int, 0x1f);
pub const EV_CNT = EV_MAX + @as(c_int, 1);
pub const SYN_REPORT = @as(c_int, 0);
pub const SYN_CONFIG = @as(c_int, 1);
pub const SYN_MT_REPORT = @as(c_int, 2);
pub const SYN_DROPPED = @as(c_int, 3);
pub const SYN_MAX = @as(c_int, 0xf);
pub const SYN_CNT = SYN_MAX + @as(c_int, 1);
pub const KEY_RESERVED = @as(c_int, 0);
pub const KEY_ESC = @as(c_int, 1);
pub const KEY_1 = @as(c_int, 2);
pub const KEY_2 = @as(c_int, 3);
pub const KEY_3 = @as(c_int, 4);
pub const KEY_4 = @as(c_int, 5);
pub const KEY_5 = @as(c_int, 6);
pub const KEY_6 = @as(c_int, 7);
pub const KEY_7 = @as(c_int, 8);
pub const KEY_8 = @as(c_int, 9);
pub const KEY_9 = @as(c_int, 10);
pub const KEY_0 = @as(c_int, 11);
pub const KEY_MINUS = @as(c_int, 12);
pub const KEY_EQUAL = @as(c_int, 13);
pub const KEY_BACKSPACE = @as(c_int, 14);
pub const KEY_TAB = @as(c_int, 15);
pub const KEY_Q = @as(c_int, 16);
pub const KEY_W = @as(c_int, 17);
pub const KEY_E = @as(c_int, 18);
pub const KEY_R = @as(c_int, 19);
pub const KEY_T = @as(c_int, 20);
pub const KEY_Y = @as(c_int, 21);
pub const KEY_U = @as(c_int, 22);
pub const KEY_I = @as(c_int, 23);
pub const KEY_O = @as(c_int, 24);
pub const KEY_P = @as(c_int, 25);
pub const KEY_LEFTBRACE = @as(c_int, 26);
pub const KEY_RIGHTBRACE = @as(c_int, 27);
pub const KEY_ENTER = @as(c_int, 28);
pub const KEY_LEFTCTRL = @as(c_int, 29);
pub const KEY_A = @as(c_int, 30);
pub const KEY_S = @as(c_int, 31);
pub const KEY_D = @as(c_int, 32);
pub const KEY_F = @as(c_int, 33);
pub const KEY_G = @as(c_int, 34);
pub const KEY_H = @as(c_int, 35);
pub const KEY_J = @as(c_int, 36);
pub const KEY_K = @as(c_int, 37);
pub const KEY_L = @as(c_int, 38);
pub const KEY_SEMICOLON = @as(c_int, 39);
pub const KEY_APOSTROPHE = @as(c_int, 40);
pub const KEY_GRAVE = @as(c_int, 41);
pub const KEY_LEFTSHIFT = @as(c_int, 42);
pub const KEY_BACKSLASH = @as(c_int, 43);
pub const KEY_Z = @as(c_int, 44);
pub const KEY_X = @as(c_int, 45);
pub const KEY_C = @as(c_int, 46);
pub const KEY_V = @as(c_int, 47);
pub const KEY_B = @as(c_int, 48);
pub const KEY_N = @as(c_int, 49);
pub const KEY_M = @as(c_int, 50);
pub const KEY_COMMA = @as(c_int, 51);
pub const KEY_DOT = @as(c_int, 52);
pub const KEY_SLASH = @as(c_int, 53);
pub const KEY_RIGHTSHIFT = @as(c_int, 54);
pub const KEY_KPASTERISK = @as(c_int, 55);
pub const KEY_LEFTALT = @as(c_int, 56);
pub const KEY_SPACE = @as(c_int, 57);
pub const KEY_CAPSLOCK = @as(c_int, 58);
pub const KEY_F1 = @as(c_int, 59);
pub const KEY_F2 = @as(c_int, 60);
pub const KEY_F3 = @as(c_int, 61);
pub const KEY_F4 = @as(c_int, 62);
pub const KEY_F5 = @as(c_int, 63);
pub const KEY_F6 = @as(c_int, 64);
pub const KEY_F7 = @as(c_int, 65);
pub const KEY_F8 = @as(c_int, 66);
pub const KEY_F9 = @as(c_int, 67);
pub const KEY_F10 = @as(c_int, 68);
pub const KEY_NUMLOCK = @as(c_int, 69);
pub const KEY_SCROLLLOCK = @as(c_int, 70);
pub const KEY_KP7 = @as(c_int, 71);
pub const KEY_KP8 = @as(c_int, 72);
pub const KEY_KP9 = @as(c_int, 73);
pub const KEY_KPMINUS = @as(c_int, 74);
pub const KEY_KP4 = @as(c_int, 75);
pub const KEY_KP5 = @as(c_int, 76);
pub const KEY_KP6 = @as(c_int, 77);
pub const KEY_KPPLUS = @as(c_int, 78);
pub const KEY_KP1 = @as(c_int, 79);
pub const KEY_KP2 = @as(c_int, 80);
pub const KEY_KP3 = @as(c_int, 81);
pub const KEY_KP0 = @as(c_int, 82);
pub const KEY_KPDOT = @as(c_int, 83);
pub const KEY_ZENKAKUHANKAKU = @as(c_int, 85);
pub const KEY_102ND = @as(c_int, 86);
pub const KEY_F11 = @as(c_int, 87);
pub const KEY_F12 = @as(c_int, 88);
pub const KEY_RO = @as(c_int, 89);
pub const KEY_KATAKANA = @as(c_int, 90);
pub const KEY_HIRAGANA = @as(c_int, 91);
pub const KEY_HENKAN = @as(c_int, 92);
pub const KEY_KATAKANAHIRAGANA = @as(c_int, 93);
pub const KEY_MUHENKAN = @as(c_int, 94);
pub const KEY_KPJPCOMMA = @as(c_int, 95);
pub const KEY_KPENTER = @as(c_int, 96);
pub const KEY_RIGHTCTRL = @as(c_int, 97);
pub const KEY_KPSLASH = @as(c_int, 98);
pub const KEY_SYSRQ = @as(c_int, 99);
pub const KEY_RIGHTALT = @as(c_int, 100);
pub const KEY_LINEFEED = @as(c_int, 101);
pub const KEY_HOME = @as(c_int, 102);
pub const KEY_UP = @as(c_int, 103);
pub const KEY_PAGEUP = @as(c_int, 104);
pub const KEY_LEFT = @as(c_int, 105);
pub const KEY_RIGHT = @as(c_int, 106);
pub const KEY_END = @as(c_int, 107);
pub const KEY_DOWN = @as(c_int, 108);
pub const KEY_PAGEDOWN = @as(c_int, 109);
pub const KEY_INSERT = @as(c_int, 110);
pub const KEY_DELETE = @as(c_int, 111);
pub const KEY_MACRO = @as(c_int, 112);
pub const KEY_MUTE = @as(c_int, 113);
pub const KEY_VOLUMEDOWN = @as(c_int, 114);
pub const KEY_VOLUMEUP = @as(c_int, 115);
pub const KEY_POWER = @as(c_int, 116);
pub const KEY_KPEQUAL = @as(c_int, 117);
pub const KEY_KPPLUSMINUS = @as(c_int, 118);
pub const KEY_PAUSE = @as(c_int, 119);
pub const KEY_SCALE = @as(c_int, 120);
pub const KEY_KPCOMMA = @as(c_int, 121);
pub const KEY_HANGEUL = @as(c_int, 122);
pub const KEY_HANGUEL = KEY_HANGEUL;
pub const KEY_HANJA = @as(c_int, 123);
pub const KEY_YEN = @as(c_int, 124);
pub const KEY_LEFTMETA = @as(c_int, 125);
pub const KEY_RIGHTMETA = @as(c_int, 126);
pub const KEY_COMPOSE = @as(c_int, 127);
pub const KEY_STOP = @as(c_int, 128);
pub const KEY_AGAIN = @as(c_int, 129);
pub const KEY_PROPS = @as(c_int, 130);
pub const KEY_UNDO = @as(c_int, 131);
pub const KEY_FRONT = @as(c_int, 132);
pub const KEY_COPY = @as(c_int, 133);
pub const KEY_OPEN = @as(c_int, 134);
pub const KEY_PASTE = @as(c_int, 135);
pub const KEY_FIND = @as(c_int, 136);
pub const KEY_CUT = @as(c_int, 137);
pub const KEY_HELP = @as(c_int, 138);
pub const KEY_MENU = @as(c_int, 139);
pub const KEY_CALC = @as(c_int, 140);
pub const KEY_SETUP = @as(c_int, 141);
pub const KEY_SLEEP = @as(c_int, 142);
pub const KEY_WAKEUP = @as(c_int, 143);
pub const KEY_FILE = @as(c_int, 144);
pub const KEY_SENDFILE = @as(c_int, 145);
pub const KEY_DELETEFILE = @as(c_int, 146);
pub const KEY_XFER = @as(c_int, 147);
pub const KEY_PROG1 = @as(c_int, 148);
pub const KEY_PROG2 = @as(c_int, 149);
pub const KEY_WWW = @as(c_int, 150);
pub const KEY_MSDOS = @as(c_int, 151);
pub const KEY_COFFEE = @as(c_int, 152);
pub const KEY_SCREENLOCK = KEY_COFFEE;
pub const KEY_ROTATE_DISPLAY = @as(c_int, 153);
pub const KEY_DIRECTION = KEY_ROTATE_DISPLAY;
pub const KEY_CYCLEWINDOWS = @as(c_int, 154);
pub const KEY_MAIL = @as(c_int, 155);
pub const KEY_BOOKMARKS = @as(c_int, 156);
pub const KEY_COMPUTER = @as(c_int, 157);
pub const KEY_BACK = @as(c_int, 158);
pub const KEY_FORWARD = @as(c_int, 159);
pub const KEY_CLOSECD = @as(c_int, 160);
pub const KEY_EJECTCD = @as(c_int, 161);
pub const KEY_EJECTCLOSECD = @as(c_int, 162);
pub const KEY_NEXTSONG = @as(c_int, 163);
pub const KEY_PLAYPAUSE = @as(c_int, 164);
pub const KEY_PREVIOUSSONG = @as(c_int, 165);
pub const KEY_STOPCD = @as(c_int, 166);
pub const KEY_RECORD = @as(c_int, 167);
pub const KEY_REWIND = @as(c_int, 168);
pub const KEY_PHONE = @as(c_int, 169);
pub const KEY_ISO = @as(c_int, 170);
pub const KEY_CONFIG = @as(c_int, 171);
pub const KEY_HOMEPAGE = @as(c_int, 172);
pub const KEY_REFRESH = @as(c_int, 173);
pub const KEY_EXIT = @as(c_int, 174);
pub const KEY_MOVE = @as(c_int, 175);
pub const KEY_EDIT = @as(c_int, 176);
pub const KEY_SCROLLUP = @as(c_int, 177);
pub const KEY_SCROLLDOWN = @as(c_int, 178);
pub const KEY_KPLEFTPAREN = @as(c_int, 179);
pub const KEY_KPRIGHTPAREN = @as(c_int, 180);
pub const KEY_NEW = @as(c_int, 181);
pub const KEY_REDO = @as(c_int, 182);
pub const KEY_F13 = @as(c_int, 183);
pub const KEY_F14 = @as(c_int, 184);
pub const KEY_F15 = @as(c_int, 185);
pub const KEY_F16 = @as(c_int, 186);
pub const KEY_F17 = @as(c_int, 187);
pub const KEY_F18 = @as(c_int, 188);
pub const KEY_F19 = @as(c_int, 189);
pub const KEY_F20 = @as(c_int, 190);
pub const KEY_F21 = @as(c_int, 191);
pub const KEY_F22 = @as(c_int, 192);
pub const KEY_F23 = @as(c_int, 193);
pub const KEY_F24 = @as(c_int, 194);
pub const KEY_PLAYCD = @as(c_int, 200);
pub const KEY_PAUSECD = @as(c_int, 201);
pub const KEY_PROG3 = @as(c_int, 202);
pub const KEY_PROG4 = @as(c_int, 203);
pub const KEY_ALL_APPLICATIONS = @as(c_int, 204);
pub const KEY_DASHBOARD = KEY_ALL_APPLICATIONS;
pub const KEY_SUSPEND = @as(c_int, 205);
pub const KEY_CLOSE = @as(c_int, 206);
pub const KEY_PLAY = @as(c_int, 207);
pub const KEY_FASTFORWARD = @as(c_int, 208);
pub const KEY_BASSBOOST = @as(c_int, 209);
pub const KEY_PRINT = @as(c_int, 210);
pub const KEY_HP = @as(c_int, 211);
pub const KEY_CAMERA = @as(c_int, 212);
pub const KEY_SOUND = @as(c_int, 213);
pub const KEY_QUESTION = @as(c_int, 214);
pub const KEY_EMAIL = @as(c_int, 215);
pub const KEY_CHAT = @as(c_int, 216);
pub const KEY_SEARCH = @as(c_int, 217);
pub const KEY_CONNECT = @as(c_int, 218);
pub const KEY_FINANCE = @as(c_int, 219);
pub const KEY_SPORT = @as(c_int, 220);
pub const KEY_SHOP = @as(c_int, 221);
pub const KEY_ALTERASE = @as(c_int, 222);
pub const KEY_CANCEL = @as(c_int, 223);
pub const KEY_BRIGHTNESSDOWN = @as(c_int, 224);
pub const KEY_BRIGHTNESSUP = @as(c_int, 225);
pub const KEY_MEDIA = @as(c_int, 226);
pub const KEY_SWITCHVIDEOMODE = @as(c_int, 227);
pub const KEY_KBDILLUMTOGGLE = @as(c_int, 228);
pub const KEY_KBDILLUMDOWN = @as(c_int, 229);
pub const KEY_KBDILLUMUP = @as(c_int, 230);
pub const KEY_SEND = @as(c_int, 231);
pub const KEY_REPLY = @as(c_int, 232);
pub const KEY_FORWARDMAIL = @as(c_int, 233);
pub const KEY_SAVE = @as(c_int, 234);
pub const KEY_DOCUMENTS = @as(c_int, 235);
pub const KEY_BATTERY = @as(c_int, 236);
pub const KEY_BLUETOOTH = @as(c_int, 237);
pub const KEY_WLAN = @as(c_int, 238);
pub const KEY_UWB = @as(c_int, 239);
pub const KEY_UNKNOWN = @as(c_int, 240);
pub const KEY_VIDEO_NEXT = @as(c_int, 241);
pub const KEY_VIDEO_PREV = @as(c_int, 242);
pub const KEY_BRIGHTNESS_CYCLE = @as(c_int, 243);
pub const KEY_BRIGHTNESS_AUTO = @as(c_int, 244);
pub const KEY_BRIGHTNESS_ZERO = KEY_BRIGHTNESS_AUTO;
pub const KEY_DISPLAY_OFF = @as(c_int, 245);
pub const KEY_WWAN = @as(c_int, 246);
pub const KEY_WIMAX = KEY_WWAN;
pub const KEY_RFKILL = @as(c_int, 247);
pub const KEY_MICMUTE = @as(c_int, 248);
pub const BTN_MISC = @as(c_int, 0x100);
pub const BTN_0 = @as(c_int, 0x100);
pub const BTN_1 = @as(c_int, 0x101);
pub const BTN_2 = @as(c_int, 0x102);
pub const BTN_3 = @as(c_int, 0x103);
pub const BTN_4 = @as(c_int, 0x104);
pub const BTN_5 = @as(c_int, 0x105);
pub const BTN_6 = @as(c_int, 0x106);
pub const BTN_7 = @as(c_int, 0x107);
pub const BTN_8 = @as(c_int, 0x108);
pub const BTN_9 = @as(c_int, 0x109);
pub const BTN_MOUSE = @as(c_int, 0x110);
pub const BTN_LEFT = @as(c_int, 0x110);
pub const BTN_RIGHT = @as(c_int, 0x111);
pub const BTN_MIDDLE = @as(c_int, 0x112);
pub const BTN_SIDE = @as(c_int, 0x113);
pub const BTN_EXTRA = @as(c_int, 0x114);
pub const BTN_FORWARD = @as(c_int, 0x115);
pub const BTN_BACK = @as(c_int, 0x116);
pub const BTN_TASK = @as(c_int, 0x117);
pub const BTN_JOYSTICK = @as(c_int, 0x120);
pub const BTN_TRIGGER = @as(c_int, 0x120);
pub const BTN_THUMB = @as(c_int, 0x121);
pub const BTN_THUMB2 = @as(c_int, 0x122);
pub const BTN_TOP = @as(c_int, 0x123);
pub const BTN_TOP2 = @as(c_int, 0x124);
pub const BTN_PINKIE = @as(c_int, 0x125);
pub const BTN_BASE = @as(c_int, 0x126);
pub const BTN_BASE2 = @as(c_int, 0x127);
pub const BTN_BASE3 = @as(c_int, 0x128);
pub const BTN_BASE4 = @as(c_int, 0x129);
pub const BTN_BASE5 = @as(c_int, 0x12a);
pub const BTN_BASE6 = @as(c_int, 0x12b);
pub const BTN_DEAD = @as(c_int, 0x12f);
pub const BTN_GAMEPAD = @as(c_int, 0x130);
pub const BTN_SOUTH = @as(c_int, 0x130);
pub const BTN_A = BTN_SOUTH;
pub const BTN_EAST = @as(c_int, 0x131);
pub const BTN_B = BTN_EAST;
pub const BTN_C = @as(c_int, 0x132);
pub const BTN_NORTH = @as(c_int, 0x133);
pub const BTN_X = BTN_NORTH;
pub const BTN_WEST = @as(c_int, 0x134);
pub const BTN_Y = BTN_WEST;
pub const BTN_Z = @as(c_int, 0x135);
pub const BTN_TL = @as(c_int, 0x136);
pub const BTN_TR = @as(c_int, 0x137);
pub const BTN_TL2 = @as(c_int, 0x138);
pub const BTN_TR2 = @as(c_int, 0x139);
pub const BTN_SELECT = @as(c_int, 0x13a);
pub const BTN_START = @as(c_int, 0x13b);
pub const BTN_MODE = @as(c_int, 0x13c);
pub const BTN_THUMBL = @as(c_int, 0x13d);
pub const BTN_THUMBR = @as(c_int, 0x13e);
pub const BTN_DIGI = @as(c_int, 0x140);
pub const BTN_TOOL_PEN = @as(c_int, 0x140);
pub const BTN_TOOL_RUBBER = @as(c_int, 0x141);
pub const BTN_TOOL_BRUSH = @as(c_int, 0x142);
pub const BTN_TOOL_PENCIL = @as(c_int, 0x143);
pub const BTN_TOOL_AIRBRUSH = @as(c_int, 0x144);
pub const BTN_TOOL_FINGER = @as(c_int, 0x145);
pub const BTN_TOOL_MOUSE = @as(c_int, 0x146);
pub const BTN_TOOL_LENS = @as(c_int, 0x147);
pub const BTN_TOOL_QUINTTAP = @as(c_int, 0x148);
pub const BTN_STYLUS3 = @as(c_int, 0x149);
pub const BTN_TOUCH = @as(c_int, 0x14a);
pub const BTN_STYLUS = @as(c_int, 0x14b);
pub const BTN_STYLUS2 = @as(c_int, 0x14c);
pub const BTN_TOOL_DOUBLETAP = @as(c_int, 0x14d);
pub const BTN_TOOL_TRIPLETAP = @as(c_int, 0x14e);
pub const BTN_TOOL_QUADTAP = @as(c_int, 0x14f);
pub const BTN_WHEEL = @as(c_int, 0x150);
pub const BTN_GEAR_DOWN = @as(c_int, 0x150);
pub const BTN_GEAR_UP = @as(c_int, 0x151);
pub const KEY_OK = @as(c_int, 0x160);
pub const KEY_SELECT = @as(c_int, 0x161);
pub const KEY_GOTO = @as(c_int, 0x162);
pub const KEY_CLEAR = @as(c_int, 0x163);
pub const KEY_POWER2 = @as(c_int, 0x164);
pub const KEY_OPTION = @as(c_int, 0x165);
pub const KEY_INFO = @as(c_int, 0x166);
pub const KEY_TIME = @as(c_int, 0x167);
pub const KEY_VENDOR = @as(c_int, 0x168);
pub const KEY_ARCHIVE = @as(c_int, 0x169);
pub const KEY_PROGRAM = @as(c_int, 0x16a);
pub const KEY_CHANNEL = @as(c_int, 0x16b);
pub const KEY_FAVORITES = @as(c_int, 0x16c);
pub const KEY_EPG = @as(c_int, 0x16d);
pub const KEY_PVR = @as(c_int, 0x16e);
pub const KEY_MHP = @as(c_int, 0x16f);
pub const KEY_LANGUAGE = @as(c_int, 0x170);
pub const KEY_TITLE = @as(c_int, 0x171);
pub const KEY_SUBTITLE = @as(c_int, 0x172);
pub const KEY_ANGLE = @as(c_int, 0x173);
pub const KEY_FULL_SCREEN = @as(c_int, 0x174);
pub const KEY_ZOOM = KEY_FULL_SCREEN;
pub const KEY_MODE = @as(c_int, 0x175);
pub const KEY_KEYBOARD = @as(c_int, 0x176);
pub const KEY_ASPECT_RATIO = @as(c_int, 0x177);
pub const KEY_SCREEN = KEY_ASPECT_RATIO;
pub const KEY_PC = @as(c_int, 0x178);
pub const KEY_TV = @as(c_int, 0x179);
pub const KEY_TV2 = @as(c_int, 0x17a);
pub const KEY_VCR = @as(c_int, 0x17b);
pub const KEY_VCR2 = @as(c_int, 0x17c);
pub const KEY_SAT = @as(c_int, 0x17d);
pub const KEY_SAT2 = @as(c_int, 0x17e);
pub const KEY_CD = @as(c_int, 0x17f);
pub const KEY_TAPE = @as(c_int, 0x180);
pub const KEY_RADIO = @as(c_int, 0x181);
pub const KEY_TUNER = @as(c_int, 0x182);
pub const KEY_PLAYER = @as(c_int, 0x183);
pub const KEY_TEXT = @as(c_int, 0x184);
pub const KEY_DVD = @as(c_int, 0x185);
pub const KEY_AUX = @as(c_int, 0x186);
pub const KEY_MP3 = @as(c_int, 0x187);
pub const KEY_AUDIO = @as(c_int, 0x188);
pub const KEY_VIDEO = @as(c_int, 0x189);
pub const KEY_DIRECTORY = @as(c_int, 0x18a);
pub const KEY_LIST = @as(c_int, 0x18b);
pub const KEY_MEMO = @as(c_int, 0x18c);
pub const KEY_CALENDAR = @as(c_int, 0x18d);
pub const KEY_RED = @as(c_int, 0x18e);
pub const KEY_GREEN = @as(c_int, 0x18f);
pub const KEY_YELLOW = @as(c_int, 0x190);
pub const KEY_BLUE = @as(c_int, 0x191);
pub const KEY_CHANNELUP = @as(c_int, 0x192);
pub const KEY_CHANNELDOWN = @as(c_int, 0x193);
pub const KEY_FIRST = @as(c_int, 0x194);
pub const KEY_LAST = @as(c_int, 0x195);
pub const KEY_AB = @as(c_int, 0x196);
pub const KEY_NEXT = @as(c_int, 0x197);
pub const KEY_RESTART = @as(c_int, 0x198);
pub const KEY_SLOW = @as(c_int, 0x199);
pub const KEY_SHUFFLE = @as(c_int, 0x19a);
pub const KEY_BREAK = @as(c_int, 0x19b);
pub const KEY_PREVIOUS = @as(c_int, 0x19c);
pub const KEY_DIGITS = @as(c_int, 0x19d);
pub const KEY_TEEN = @as(c_int, 0x19e);
pub const KEY_TWEN = @as(c_int, 0x19f);
pub const KEY_VIDEOPHONE = @as(c_int, 0x1a0);
pub const KEY_GAMES = @as(c_int, 0x1a1);
pub const KEY_ZOOMIN = @as(c_int, 0x1a2);
pub const KEY_ZOOMOUT = @as(c_int, 0x1a3);
pub const KEY_ZOOMRESET = @as(c_int, 0x1a4);
pub const KEY_WORDPROCESSOR = @as(c_int, 0x1a5);
pub const KEY_EDITOR = @as(c_int, 0x1a6);
pub const KEY_SPREADSHEET = @as(c_int, 0x1a7);
pub const KEY_GRAPHICSEDITOR = @as(c_int, 0x1a8);
pub const KEY_PRESENTATION = @as(c_int, 0x1a9);
pub const KEY_DATABASE = @as(c_int, 0x1aa);
pub const KEY_NEWS = @as(c_int, 0x1ab);
pub const KEY_VOICEMAIL = @as(c_int, 0x1ac);
pub const KEY_ADDRESSBOOK = @as(c_int, 0x1ad);
pub const KEY_MESSENGER = @as(c_int, 0x1ae);
pub const KEY_DISPLAYTOGGLE = @as(c_int, 0x1af);
pub const KEY_BRIGHTNESS_TOGGLE = KEY_DISPLAYTOGGLE;
pub const KEY_SPELLCHECK = @as(c_int, 0x1b0);
pub const KEY_LOGOFF = @as(c_int, 0x1b1);
pub const KEY_DOLLAR = @as(c_int, 0x1b2);
pub const KEY_EURO = @as(c_int, 0x1b3);
pub const KEY_FRAMEBACK = @as(c_int, 0x1b4);
pub const KEY_FRAMEFORWARD = @as(c_int, 0x1b5);
pub const KEY_CONTEXT_MENU = @as(c_int, 0x1b6);
pub const KEY_MEDIA_REPEAT = @as(c_int, 0x1b7);
pub const KEY_10CHANNELSUP = @as(c_int, 0x1b8);
pub const KEY_10CHANNELSDOWN = @as(c_int, 0x1b9);
pub const KEY_IMAGES = @as(c_int, 0x1ba);
pub const KEY_NOTIFICATION_CENTER = @as(c_int, 0x1bc);
pub const KEY_PICKUP_PHONE = @as(c_int, 0x1bd);
pub const KEY_HANGUP_PHONE = @as(c_int, 0x1be);
pub const KEY_LINK_PHONE = @as(c_int, 0x1bf);
pub const KEY_DEL_EOL = @as(c_int, 0x1c0);
pub const KEY_DEL_EOS = @as(c_int, 0x1c1);
pub const KEY_INS_LINE = @as(c_int, 0x1c2);
pub const KEY_DEL_LINE = @as(c_int, 0x1c3);
pub const KEY_FN = @as(c_int, 0x1d0);
pub const KEY_FN_ESC = @as(c_int, 0x1d1);
pub const KEY_FN_F1 = @as(c_int, 0x1d2);
pub const KEY_FN_F2 = @as(c_int, 0x1d3);
pub const KEY_FN_F3 = @as(c_int, 0x1d4);
pub const KEY_FN_F4 = @as(c_int, 0x1d5);
pub const KEY_FN_F5 = @as(c_int, 0x1d6);
pub const KEY_FN_F6 = @as(c_int, 0x1d7);
pub const KEY_FN_F7 = @as(c_int, 0x1d8);
pub const KEY_FN_F8 = @as(c_int, 0x1d9);
pub const KEY_FN_F9 = @as(c_int, 0x1da);
pub const KEY_FN_F10 = @as(c_int, 0x1db);
pub const KEY_FN_F11 = @as(c_int, 0x1dc);
pub const KEY_FN_F12 = @as(c_int, 0x1dd);
pub const KEY_FN_1 = @as(c_int, 0x1de);
pub const KEY_FN_2 = @as(c_int, 0x1df);
pub const KEY_FN_D = @as(c_int, 0x1e0);
pub const KEY_FN_E = @as(c_int, 0x1e1);
pub const KEY_FN_F = @as(c_int, 0x1e2);
pub const KEY_FN_S = @as(c_int, 0x1e3);
pub const KEY_FN_B = @as(c_int, 0x1e4);
pub const KEY_FN_RIGHT_SHIFT = @as(c_int, 0x1e5);
pub const KEY_BRL_DOT1 = @as(c_int, 0x1f1);
pub const KEY_BRL_DOT2 = @as(c_int, 0x1f2);
pub const KEY_BRL_DOT3 = @as(c_int, 0x1f3);
pub const KEY_BRL_DOT4 = @as(c_int, 0x1f4);
pub const KEY_BRL_DOT5 = @as(c_int, 0x1f5);
pub const KEY_BRL_DOT6 = @as(c_int, 0x1f6);
pub const KEY_BRL_DOT7 = @as(c_int, 0x1f7);
pub const KEY_BRL_DOT8 = @as(c_int, 0x1f8);
pub const KEY_BRL_DOT9 = @as(c_int, 0x1f9);
pub const KEY_BRL_DOT10 = @as(c_int, 0x1fa);
pub const KEY_NUMERIC_0 = @as(c_int, 0x200);
pub const KEY_NUMERIC_1 = @as(c_int, 0x201);
pub const KEY_NUMERIC_2 = @as(c_int, 0x202);
pub const KEY_NUMERIC_3 = @as(c_int, 0x203);
pub const KEY_NUMERIC_4 = @as(c_int, 0x204);
pub const KEY_NUMERIC_5 = @as(c_int, 0x205);
pub const KEY_NUMERIC_6 = @as(c_int, 0x206);
pub const KEY_NUMERIC_7 = @as(c_int, 0x207);
pub const KEY_NUMERIC_8 = @as(c_int, 0x208);
pub const KEY_NUMERIC_9 = @as(c_int, 0x209);
pub const KEY_NUMERIC_STAR = @as(c_int, 0x20a);
pub const KEY_NUMERIC_POUND = @as(c_int, 0x20b);
pub const KEY_NUMERIC_A = @as(c_int, 0x20c);
pub const KEY_NUMERIC_B = @as(c_int, 0x20d);
pub const KEY_NUMERIC_C = @as(c_int, 0x20e);
pub const KEY_NUMERIC_D = @as(c_int, 0x20f);
pub const KEY_CAMERA_FOCUS = @as(c_int, 0x210);
pub const KEY_WPS_BUTTON = @as(c_int, 0x211);
pub const KEY_TOUCHPAD_TOGGLE = @as(c_int, 0x212);
pub const KEY_TOUCHPAD_ON = @as(c_int, 0x213);
pub const KEY_TOUCHPAD_OFF = @as(c_int, 0x214);
pub const KEY_CAMERA_ZOOMIN = @as(c_int, 0x215);
pub const KEY_CAMERA_ZOOMOUT = @as(c_int, 0x216);
pub const KEY_CAMERA_UP = @as(c_int, 0x217);
pub const KEY_CAMERA_DOWN = @as(c_int, 0x218);
pub const KEY_CAMERA_LEFT = @as(c_int, 0x219);
pub const KEY_CAMERA_RIGHT = @as(c_int, 0x21a);
pub const KEY_ATTENDANT_ON = @as(c_int, 0x21b);
pub const KEY_ATTENDANT_OFF = @as(c_int, 0x21c);
pub const KEY_ATTENDANT_TOGGLE = @as(c_int, 0x21d);
pub const KEY_LIGHTS_TOGGLE = @as(c_int, 0x21e);
pub const BTN_DPAD_UP = @as(c_int, 0x220);
pub const BTN_DPAD_DOWN = @as(c_int, 0x221);
pub const BTN_DPAD_LEFT = @as(c_int, 0x222);
pub const BTN_DPAD_RIGHT = @as(c_int, 0x223);
pub const BTN_GRIPL = @as(c_int, 0x224);
pub const BTN_GRIPR = @as(c_int, 0x225);
pub const BTN_GRIPL2 = @as(c_int, 0x226);
pub const BTN_GRIPR2 = @as(c_int, 0x227);
pub const KEY_ALS_TOGGLE = @as(c_int, 0x230);
pub const KEY_ROTATE_LOCK_TOGGLE = @as(c_int, 0x231);
pub const KEY_REFRESH_RATE_TOGGLE = @as(c_int, 0x232);
pub const KEY_BUTTONCONFIG = @as(c_int, 0x240);
pub const KEY_TASKMANAGER = @as(c_int, 0x241);
pub const KEY_JOURNAL = @as(c_int, 0x242);
pub const KEY_CONTROLPANEL = @as(c_int, 0x243);
pub const KEY_APPSELECT = @as(c_int, 0x244);
pub const KEY_SCREENSAVER = @as(c_int, 0x245);
pub const KEY_VOICECOMMAND = @as(c_int, 0x246);
pub const KEY_ASSISTANT = @as(c_int, 0x247);
pub const KEY_KBD_LAYOUT_NEXT = @as(c_int, 0x248);
pub const KEY_EMOJI_PICKER = @as(c_int, 0x249);
pub const KEY_DICTATE = @as(c_int, 0x24a);
pub const KEY_CAMERA_ACCESS_ENABLE = @as(c_int, 0x24b);
pub const KEY_CAMERA_ACCESS_DISABLE = @as(c_int, 0x24c);
pub const KEY_CAMERA_ACCESS_TOGGLE = @as(c_int, 0x24d);
pub const KEY_ACCESSIBILITY = @as(c_int, 0x24e);
pub const KEY_DO_NOT_DISTURB = @as(c_int, 0x24f);
pub const KEY_BRIGHTNESS_MIN = @as(c_int, 0x250);
pub const KEY_BRIGHTNESS_MAX = @as(c_int, 0x251);
pub const KEY_EPRIVACY_SCREEN_ON = @as(c_int, 0x252);
pub const KEY_EPRIVACY_SCREEN_OFF = @as(c_int, 0x253);
pub const KEY_ACTION_ON_SELECTION = @as(c_int, 0x254);
pub const KEY_CONTEXTUAL_INSERT = @as(c_int, 0x255);
pub const KEY_CONTEXTUAL_QUERY = @as(c_int, 0x256);
pub const KEY_KBDINPUTASSIST_PREV = @as(c_int, 0x260);
pub const KEY_KBDINPUTASSIST_NEXT = @as(c_int, 0x261);
pub const KEY_KBDINPUTASSIST_PREVGROUP = @as(c_int, 0x262);
pub const KEY_KBDINPUTASSIST_NEXTGROUP = @as(c_int, 0x263);
pub const KEY_KBDINPUTASSIST_ACCEPT = @as(c_int, 0x264);
pub const KEY_KBDINPUTASSIST_CANCEL = @as(c_int, 0x265);
pub const KEY_RIGHT_UP = @as(c_int, 0x266);
pub const KEY_RIGHT_DOWN = @as(c_int, 0x267);
pub const KEY_LEFT_UP = @as(c_int, 0x268);
pub const KEY_LEFT_DOWN = @as(c_int, 0x269);
pub const KEY_ROOT_MENU = @as(c_int, 0x26a);
pub const KEY_MEDIA_TOP_MENU = @as(c_int, 0x26b);
pub const KEY_NUMERIC_11 = @as(c_int, 0x26c);
pub const KEY_NUMERIC_12 = @as(c_int, 0x26d);
pub const KEY_AUDIO_DESC = @as(c_int, 0x26e);
pub const KEY_3D_MODE = @as(c_int, 0x26f);
pub const KEY_NEXT_FAVORITE = @as(c_int, 0x270);
pub const KEY_STOP_RECORD = @as(c_int, 0x271);
pub const KEY_PAUSE_RECORD = @as(c_int, 0x272);
pub const KEY_VOD = @as(c_int, 0x273);
pub const KEY_UNMUTE = @as(c_int, 0x274);
pub const KEY_FASTREVERSE = @as(c_int, 0x275);
pub const KEY_SLOWREVERSE = @as(c_int, 0x276);
pub const KEY_DATA = @as(c_int, 0x277);
pub const KEY_ONSCREEN_KEYBOARD = @as(c_int, 0x278);
pub const KEY_PRIVACY_SCREEN_TOGGLE = @as(c_int, 0x279);
pub const KEY_SELECTIVE_SCREENSHOT = @as(c_int, 0x27a);
pub const KEY_NEXT_ELEMENT = @as(c_int, 0x27b);
pub const KEY_PREVIOUS_ELEMENT = @as(c_int, 0x27c);
pub const KEY_AUTOPILOT_ENGAGE_TOGGLE = @as(c_int, 0x27d);
pub const KEY_MARK_WAYPOINT = @as(c_int, 0x27e);
pub const KEY_SOS = @as(c_int, 0x27f);
pub const KEY_NAV_CHART = @as(c_int, 0x280);
pub const KEY_FISHING_CHART = @as(c_int, 0x281);
pub const KEY_SINGLE_RANGE_RADAR = @as(c_int, 0x282);
pub const KEY_DUAL_RANGE_RADAR = @as(c_int, 0x283);
pub const KEY_RADAR_OVERLAY = @as(c_int, 0x284);
pub const KEY_TRADITIONAL_SONAR = @as(c_int, 0x285);
pub const KEY_CLEARVU_SONAR = @as(c_int, 0x286);
pub const KEY_SIDEVU_SONAR = @as(c_int, 0x287);
pub const KEY_NAV_INFO = @as(c_int, 0x288);
pub const KEY_BRIGHTNESS_MENU = @as(c_int, 0x289);
pub const KEY_MACRO1 = @as(c_int, 0x290);
pub const KEY_MACRO2 = @as(c_int, 0x291);
pub const KEY_MACRO3 = @as(c_int, 0x292);
pub const KEY_MACRO4 = @as(c_int, 0x293);
pub const KEY_MACRO5 = @as(c_int, 0x294);
pub const KEY_MACRO6 = @as(c_int, 0x295);
pub const KEY_MACRO7 = @as(c_int, 0x296);
pub const KEY_MACRO8 = @as(c_int, 0x297);
pub const KEY_MACRO9 = @as(c_int, 0x298);
pub const KEY_MACRO10 = @as(c_int, 0x299);
pub const KEY_MACRO11 = @as(c_int, 0x29a);
pub const KEY_MACRO12 = @as(c_int, 0x29b);
pub const KEY_MACRO13 = @as(c_int, 0x29c);
pub const KEY_MACRO14 = @as(c_int, 0x29d);
pub const KEY_MACRO15 = @as(c_int, 0x29e);
pub const KEY_MACRO16 = @as(c_int, 0x29f);
pub const KEY_MACRO17 = @as(c_int, 0x2a0);
pub const KEY_MACRO18 = @as(c_int, 0x2a1);
pub const KEY_MACRO19 = @as(c_int, 0x2a2);
pub const KEY_MACRO20 = @as(c_int, 0x2a3);
pub const KEY_MACRO21 = @as(c_int, 0x2a4);
pub const KEY_MACRO22 = @as(c_int, 0x2a5);
pub const KEY_MACRO23 = @as(c_int, 0x2a6);
pub const KEY_MACRO24 = @as(c_int, 0x2a7);
pub const KEY_MACRO25 = @as(c_int, 0x2a8);
pub const KEY_MACRO26 = @as(c_int, 0x2a9);
pub const KEY_MACRO27 = @as(c_int, 0x2aa);
pub const KEY_MACRO28 = @as(c_int, 0x2ab);
pub const KEY_MACRO29 = @as(c_int, 0x2ac);
pub const KEY_MACRO30 = @as(c_int, 0x2ad);
pub const KEY_MACRO_RECORD_START = @as(c_int, 0x2b0);
pub const KEY_MACRO_RECORD_STOP = @as(c_int, 0x2b1);
pub const KEY_MACRO_PRESET_CYCLE = @as(c_int, 0x2b2);
pub const KEY_MACRO_PRESET1 = @as(c_int, 0x2b3);
pub const KEY_MACRO_PRESET2 = @as(c_int, 0x2b4);
pub const KEY_MACRO_PRESET3 = @as(c_int, 0x2b5);
pub const KEY_KBD_LCD_MENU1 = @as(c_int, 0x2b8);
pub const KEY_KBD_LCD_MENU2 = @as(c_int, 0x2b9);
pub const KEY_KBD_LCD_MENU3 = @as(c_int, 0x2ba);
pub const KEY_KBD_LCD_MENU4 = @as(c_int, 0x2bb);
pub const KEY_KBD_LCD_MENU5 = @as(c_int, 0x2bc);
pub const KEY_PERFORMANCE = @as(c_int, 0x2bd);
pub const BTN_TRIGGER_HAPPY = @as(c_int, 0x2c0);
pub const BTN_TRIGGER_HAPPY1 = @as(c_int, 0x2c0);
pub const BTN_TRIGGER_HAPPY2 = @as(c_int, 0x2c1);
pub const BTN_TRIGGER_HAPPY3 = @as(c_int, 0x2c2);
pub const BTN_TRIGGER_HAPPY4 = @as(c_int, 0x2c3);
pub const BTN_TRIGGER_HAPPY5 = @as(c_int, 0x2c4);
pub const BTN_TRIGGER_HAPPY6 = @as(c_int, 0x2c5);
pub const BTN_TRIGGER_HAPPY7 = @as(c_int, 0x2c6);
pub const BTN_TRIGGER_HAPPY8 = @as(c_int, 0x2c7);
pub const BTN_TRIGGER_HAPPY9 = @as(c_int, 0x2c8);
pub const BTN_TRIGGER_HAPPY10 = @as(c_int, 0x2c9);
pub const BTN_TRIGGER_HAPPY11 = @as(c_int, 0x2ca);
pub const BTN_TRIGGER_HAPPY12 = @as(c_int, 0x2cb);
pub const BTN_TRIGGER_HAPPY13 = @as(c_int, 0x2cc);
pub const BTN_TRIGGER_HAPPY14 = @as(c_int, 0x2cd);
pub const BTN_TRIGGER_HAPPY15 = @as(c_int, 0x2ce);
pub const BTN_TRIGGER_HAPPY16 = @as(c_int, 0x2cf);
pub const BTN_TRIGGER_HAPPY17 = @as(c_int, 0x2d0);
pub const BTN_TRIGGER_HAPPY18 = @as(c_int, 0x2d1);
pub const BTN_TRIGGER_HAPPY19 = @as(c_int, 0x2d2);
pub const BTN_TRIGGER_HAPPY20 = @as(c_int, 0x2d3);
pub const BTN_TRIGGER_HAPPY21 = @as(c_int, 0x2d4);
pub const BTN_TRIGGER_HAPPY22 = @as(c_int, 0x2d5);
pub const BTN_TRIGGER_HAPPY23 = @as(c_int, 0x2d6);
pub const BTN_TRIGGER_HAPPY24 = @as(c_int, 0x2d7);
pub const BTN_TRIGGER_HAPPY25 = @as(c_int, 0x2d8);
pub const BTN_TRIGGER_HAPPY26 = @as(c_int, 0x2d9);
pub const BTN_TRIGGER_HAPPY27 = @as(c_int, 0x2da);
pub const BTN_TRIGGER_HAPPY28 = @as(c_int, 0x2db);
pub const BTN_TRIGGER_HAPPY29 = @as(c_int, 0x2dc);
pub const BTN_TRIGGER_HAPPY30 = @as(c_int, 0x2dd);
pub const BTN_TRIGGER_HAPPY31 = @as(c_int, 0x2de);
pub const BTN_TRIGGER_HAPPY32 = @as(c_int, 0x2df);
pub const BTN_TRIGGER_HAPPY33 = @as(c_int, 0x2e0);
pub const BTN_TRIGGER_HAPPY34 = @as(c_int, 0x2e1);
pub const BTN_TRIGGER_HAPPY35 = @as(c_int, 0x2e2);
pub const BTN_TRIGGER_HAPPY36 = @as(c_int, 0x2e3);
pub const BTN_TRIGGER_HAPPY37 = @as(c_int, 0x2e4);
pub const BTN_TRIGGER_HAPPY38 = @as(c_int, 0x2e5);
pub const BTN_TRIGGER_HAPPY39 = @as(c_int, 0x2e6);
pub const BTN_TRIGGER_HAPPY40 = @as(c_int, 0x2e7);
pub const KEY_MIN_INTERESTING = KEY_MUTE;
pub const KEY_MAX = @as(c_int, 0x2ff);
pub const KEY_CNT = KEY_MAX + @as(c_int, 1);
pub const REL_X = @as(c_int, 0x00);
pub const REL_Y = @as(c_int, 0x01);
pub const REL_Z = @as(c_int, 0x02);
pub const REL_RX = @as(c_int, 0x03);
pub const REL_RY = @as(c_int, 0x04);
pub const REL_RZ = @as(c_int, 0x05);
pub const REL_HWHEEL = @as(c_int, 0x06);
pub const REL_DIAL = @as(c_int, 0x07);
pub const REL_WHEEL = @as(c_int, 0x08);
pub const REL_MISC = @as(c_int, 0x09);
pub const REL_RESERVED = @as(c_int, 0x0a);
pub const REL_WHEEL_HI_RES = @as(c_int, 0x0b);
pub const REL_HWHEEL_HI_RES = @as(c_int, 0x0c);
pub const REL_MAX = @as(c_int, 0x0f);
pub const REL_CNT = REL_MAX + @as(c_int, 1);
pub const ABS_X = @as(c_int, 0x00);
pub const ABS_Y = @as(c_int, 0x01);
pub const ABS_Z = @as(c_int, 0x02);
pub const ABS_RX = @as(c_int, 0x03);
pub const ABS_RY = @as(c_int, 0x04);
pub const ABS_RZ = @as(c_int, 0x05);
pub const ABS_THROTTLE = @as(c_int, 0x06);
pub const ABS_RUDDER = @as(c_int, 0x07);
pub const ABS_WHEEL = @as(c_int, 0x08);
pub const ABS_GAS = @as(c_int, 0x09);
pub const ABS_BRAKE = @as(c_int, 0x0a);
pub const ABS_HAT0X = @as(c_int, 0x10);
pub const ABS_HAT0Y = @as(c_int, 0x11);
pub const ABS_HAT1X = @as(c_int, 0x12);
pub const ABS_HAT1Y = @as(c_int, 0x13);
pub const ABS_HAT2X = @as(c_int, 0x14);
pub const ABS_HAT2Y = @as(c_int, 0x15);
pub const ABS_HAT3X = @as(c_int, 0x16);
pub const ABS_HAT3Y = @as(c_int, 0x17);
pub const ABS_PRESSURE = @as(c_int, 0x18);
pub const ABS_DISTANCE = @as(c_int, 0x19);
pub const ABS_TILT_X = @as(c_int, 0x1a);
pub const ABS_TILT_Y = @as(c_int, 0x1b);
pub const ABS_TOOL_WIDTH = @as(c_int, 0x1c);
pub const ABS_VOLUME = @as(c_int, 0x20);
pub const ABS_PROFILE = @as(c_int, 0x21);
pub const ABS_SND_PROFILE = @as(c_int, 0x22);
pub const ABS_MISC = @as(c_int, 0x28);
pub const ABS_RESERVED = @as(c_int, 0x2e);
pub const ABS_MT_SLOT = @as(c_int, 0x2f);
pub const ABS_MT_TOUCH_MAJOR = @as(c_int, 0x30);
pub const ABS_MT_TOUCH_MINOR = @as(c_int, 0x31);
pub const ABS_MT_WIDTH_MAJOR = @as(c_int, 0x32);
pub const ABS_MT_WIDTH_MINOR = @as(c_int, 0x33);
pub const ABS_MT_ORIENTATION = @as(c_int, 0x34);
pub const ABS_MT_POSITION_X = @as(c_int, 0x35);
pub const ABS_MT_POSITION_Y = @as(c_int, 0x36);
pub const ABS_MT_TOOL_TYPE = @as(c_int, 0x37);
pub const ABS_MT_BLOB_ID = @as(c_int, 0x38);
pub const ABS_MT_TRACKING_ID = @as(c_int, 0x39);
pub const ABS_MT_PRESSURE = @as(c_int, 0x3a);
pub const ABS_MT_DISTANCE = @as(c_int, 0x3b);
pub const ABS_MT_TOOL_X = @as(c_int, 0x3c);
pub const ABS_MT_TOOL_Y = @as(c_int, 0x3d);
pub const ABS_MAX = @as(c_int, 0x3f);
pub const ABS_CNT = ABS_MAX + @as(c_int, 1);
pub const SW_LID = @as(c_int, 0x00);
pub const SW_TABLET_MODE = @as(c_int, 0x01);
pub const SW_HEADPHONE_INSERT = @as(c_int, 0x02);
pub const SW_RFKILL_ALL = @as(c_int, 0x03);
pub const SW_RADIO = SW_RFKILL_ALL;
pub const SW_MICROPHONE_INSERT = @as(c_int, 0x04);
pub const SW_DOCK = @as(c_int, 0x05);
pub const SW_LINEOUT_INSERT = @as(c_int, 0x06);
pub const SW_JACK_PHYSICAL_INSERT = @as(c_int, 0x07);
pub const SW_VIDEOOUT_INSERT = @as(c_int, 0x08);
pub const SW_CAMERA_LENS_COVER = @as(c_int, 0x09);
pub const SW_KEYPAD_SLIDE = @as(c_int, 0x0a);
pub const SW_FRONT_PROXIMITY = @as(c_int, 0x0b);
pub const SW_ROTATE_LOCK = @as(c_int, 0x0c);
pub const SW_LINEIN_INSERT = @as(c_int, 0x0d);
pub const SW_MUTE_DEVICE = @as(c_int, 0x0e);
pub const SW_PEN_INSERTED = @as(c_int, 0x0f);
pub const SW_MACHINE_COVER = @as(c_int, 0x10);
pub const SW_USB_INSERT = @as(c_int, 0x11);
pub const SW_MAX = @as(c_int, 0x11);
pub const SW_CNT = SW_MAX + @as(c_int, 1);
pub const MSC_SERIAL = @as(c_int, 0x00);
pub const MSC_PULSELED = @as(c_int, 0x01);
pub const MSC_GESTURE = @as(c_int, 0x02);
pub const MSC_RAW = @as(c_int, 0x03);
pub const MSC_SCAN = @as(c_int, 0x04);
pub const MSC_TIMESTAMP = @as(c_int, 0x05);
pub const MSC_MAX = @as(c_int, 0x07);
pub const MSC_CNT = MSC_MAX + @as(c_int, 1);
pub const LED_NUML = @as(c_int, 0x00);
pub const LED_CAPSL = @as(c_int, 0x01);
pub const LED_SCROLLL = @as(c_int, 0x02);
pub const LED_COMPOSE = @as(c_int, 0x03);
pub const LED_KANA = @as(c_int, 0x04);
pub const LED_SLEEP = @as(c_int, 0x05);
pub const LED_SUSPEND = @as(c_int, 0x06);
pub const LED_MUTE = @as(c_int, 0x07);
pub const LED_MISC = @as(c_int, 0x08);
pub const LED_MAIL = @as(c_int, 0x09);
pub const LED_CHARGING = @as(c_int, 0x0a);
pub const LED_MAX = @as(c_int, 0x0f);
pub const LED_CNT = LED_MAX + @as(c_int, 1);
pub const REP_DELAY = @as(c_int, 0x00);
pub const REP_PERIOD = @as(c_int, 0x01);
pub const REP_MAX = @as(c_int, 0x01);
pub const REP_CNT = REP_MAX + @as(c_int, 1);
pub const SND_CLICK = @as(c_int, 0x00);
pub const SND_BELL = @as(c_int, 0x01);
pub const SND_TONE = @as(c_int, 0x02);
pub const SND_MAX = @as(c_int, 0x07);
pub const SND_CNT = SND_MAX + @as(c_int, 1);
pub const SND_PROFILE_SILENT = @as(c_int, 0x00);
pub const SND_PROFILE_VIBRATE = @as(c_int, 0x01);
pub const SND_PROFILE_RING = @as(c_int, 0x02);
pub const LIBEVDEV_H = "";
pub const _INPUT_H = "";
pub const _SYS_TIME_H = @as(c_int, 1);
pub const _FEATURES_H = @as(c_int, 1);
pub const __KERNEL_STRICT_NAMES = "";
pub inline fn __GNUC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub inline fn __glibc_clang_prereq(maj: anytype, min: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &maj;
    _ = &min;
    return @as(c_int, 0);
}
pub const __GLIBC_USE = @compileError("unable to translate macro: undefined identifier `__GLIBC_USE_`"); // /usr/include/features.h:197:9
pub const _DEFAULT_SOURCE = @as(c_int, 1);
pub const __GLIBC_USE_ISOC2Y = @as(c_int, 0);
pub const __GLIBC_USE_ISOC23 = @as(c_int, 0);
pub const __USE_ISOC11 = @as(c_int, 1);
pub const __USE_POSIX_IMPLICITLY = @as(c_int, 1);
pub const _POSIX_SOURCE = @as(c_int, 1);
pub const _POSIX_C_SOURCE = @as(c_long, 202405);
pub const __USE_POSIX = @as(c_int, 1);
pub const __USE_POSIX2 = @as(c_int, 1);
pub const __USE_POSIX199309 = @as(c_int, 1);
pub const __USE_POSIX199506 = @as(c_int, 1);
pub const __USE_XOPEN2K = @as(c_int, 1);
pub const __USE_ISOC95 = @as(c_int, 1);
pub const __USE_ISOC99 = @as(c_int, 1);
pub const __USE_XOPEN2K8 = @as(c_int, 1);
pub const _ATFILE_SOURCE = @as(c_int, 1);
pub const __USE_XOPEN2K24 = @as(c_int, 1);
pub const __WORDSIZE = @as(c_int, 64);
pub const __WORDSIZE_TIME64_COMPAT32 = @as(c_int, 1);
pub const __SYSCALL_WORDSIZE = @as(c_int, 64);
pub const __TIMESIZE = __WORDSIZE;
pub const __USE_TIME_BITS64 = @as(c_int, 1);
pub const __USE_MISC = @as(c_int, 1);
pub const __USE_ATFILE = @as(c_int, 1);
pub const __USE_FORTIFY_LEVEL = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_GETS = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_SCANF = @as(c_int, 0);
pub const __GLIBC_USE_C23_STRTOL = @as(c_int, 0);
pub const _STDC_PREDEF_H = @as(c_int, 1);
pub const __STDC_IEC_559__ = @as(c_int, 1);
pub const __STDC_IEC_60559_BFP__ = @as(c_long, 201404);
pub const __STDC_IEC_559_COMPLEX__ = @as(c_int, 1);
pub const __STDC_IEC_60559_COMPLEX__ = @as(c_long, 201404);
pub const __STDC_ISO_10646__ = @as(c_long, 201706);
pub const __GNU_LIBRARY__ = @as(c_int, 6);
pub const __GLIBC__ = @as(c_int, 2);
pub const __GLIBC_MINOR__ = @as(c_int, 43);
pub inline fn __GLIBC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub const _SYS_CDEFS_H = @as(c_int, 1);
pub const __glibc_has_attribute = @compileError("unable to translate macro: undefined identifier `__has_attribute`"); // /usr/include/sys/cdefs.h:45:10
pub inline fn __glibc_has_builtin(name: anytype) @TypeOf(__builtin.has_builtin(name)) {
    _ = &name;
    return __builtin.has_builtin(name);
}
pub const __glibc_has_extension = @compileError("unable to translate macro: undefined identifier `__has_extension`"); // /usr/include/sys/cdefs.h:55:10
pub const __LEAF = @compileError("unable to translate macro: undefined identifier `__leaf__`"); // /usr/include/sys/cdefs.h:65:11
pub const __LEAF_ATTR = @compileError("unable to translate macro: undefined identifier `__leaf__`"); // /usr/include/sys/cdefs.h:66:11
pub const __THROW = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:79:11
pub const __THROWNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:80:11
pub const __NTH = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:81:11
pub const __NTHNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:82:11
pub const __COLD = @compileError("unable to translate macro: undefined identifier `__cold__`"); // /usr/include/sys/cdefs.h:102:11
pub inline fn __P(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub inline fn __PMT(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub const __CONCAT = @compileError("unable to translate C expr: unexpected token '##'"); // /usr/include/sys/cdefs.h:131:9
pub const __STRING = @compileError("unable to translate C expr: unexpected token ''"); // /usr/include/sys/cdefs.h:132:9
pub const __ptr_t = ?*anyopaque;
pub const __BEGIN_DECLS = "";
pub const __END_DECLS = "";
pub const __attribute_overloadable__ = "";
pub inline fn __bos(ptr: anytype) @TypeOf(__builtin.object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1))) {
    _ = &ptr;
    return __builtin.object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1));
}
pub inline fn __bos0(ptr: anytype) @TypeOf(__builtin.object_size(ptr, @as(c_int, 0))) {
    _ = &ptr;
    return __builtin.object_size(ptr, @as(c_int, 0));
}
pub inline fn __glibc_objsize0(__o: anytype) @TypeOf(__bos0(__o)) {
    _ = &__o;
    return __bos0(__o);
}
pub inline fn __glibc_objsize(__o: anytype) @TypeOf(__bos(__o)) {
    _ = &__o;
    return __bos(__o);
}
pub const __warnattr = @compileError("unable to translate macro: undefined identifier `__warning__`"); // /usr/include/sys/cdefs.h:366:10
pub const __errordecl = @compileError("unable to translate macro: undefined identifier `__error__`"); // /usr/include/sys/cdefs.h:367:10
pub const __flexarr = @compileError("unable to translate C expr: unexpected token '['"); // /usr/include/sys/cdefs.h:379:10
pub const __glibc_c99_flexarr_available = @as(c_int, 1);
pub const __REDIRECT = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:410:10
pub const __REDIRECT_NTH = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:417:11
pub const __REDIRECT_NTHNL = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:419:11
pub const __ASMNAME = @compileError("unable to translate macro: undefined identifier `__USER_LABEL_PREFIX__`"); // /usr/include/sys/cdefs.h:422:10
pub inline fn __ASMNAME2(prefix: anytype, cname: anytype) @TypeOf(__STRING(prefix) ++ cname) {
    _ = &prefix;
    _ = &cname;
    return __STRING(prefix) ++ cname;
}
pub const __REDIRECT_FORTIFY = __REDIRECT;
pub const __REDIRECT_FORTIFY_NTH = __REDIRECT_NTH;
pub const __attribute_malloc__ = @compileError("unable to translate macro: undefined identifier `__malloc__`"); // /usr/include/sys/cdefs.h:452:10
pub const __attribute_alloc_size__ = @compileError("unable to translate macro: undefined identifier `__alloc_size__`"); // /usr/include/sys/cdefs.h:460:10
pub const __attribute_alloc_align__ = @compileError("unable to translate macro: undefined identifier `__alloc_align__`"); // /usr/include/sys/cdefs.h:469:10
pub const __attribute_pure__ = @compileError("unable to translate macro: undefined identifier `__pure__`"); // /usr/include/sys/cdefs.h:479:10
pub const __attribute_const__ = @compileError("unable to translate C expr: unexpected token '__attribute__'"); // /usr/include/sys/cdefs.h:486:10
pub const __attribute_maybe_unused__ = @compileError("unable to translate macro: undefined identifier `__unused__`"); // /usr/include/sys/cdefs.h:492:10
pub const __attribute_used__ = @compileError("unable to translate macro: undefined identifier `__used__`"); // /usr/include/sys/cdefs.h:501:10
pub const __attribute_noinline__ = @compileError("unable to translate macro: undefined identifier `__noinline__`"); // /usr/include/sys/cdefs.h:502:10
pub const __attribute_deprecated__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /usr/include/sys/cdefs.h:510:10
pub const __attribute_deprecated_msg__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /usr/include/sys/cdefs.h:520:10
pub const __attribute_format_arg__ = @compileError("unable to translate macro: undefined identifier `__format_arg__`"); // /usr/include/sys/cdefs.h:533:10
pub const __attribute_format_strfmon__ = @compileError("unable to translate macro: undefined identifier `__format__`"); // /usr/include/sys/cdefs.h:543:10
pub const __attribute_nonnull__ = @compileError("unable to translate macro: undefined identifier `__nonnull__`"); // /usr/include/sys/cdefs.h:555:11
pub inline fn __nonnull(params: anytype) @TypeOf(__attribute_nonnull__(params)) {
    _ = &params;
    return __attribute_nonnull__(params);
}
pub const __returns_nonnull = @compileError("unable to translate macro: undefined identifier `__returns_nonnull__`"); // /usr/include/sys/cdefs.h:568:10
pub const __attribute_warn_unused_result__ = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`"); // /usr/include/sys/cdefs.h:577:10
pub const __wur = "";
pub const __always_inline = @compileError("unable to translate macro: undefined identifier `__always_inline__`"); // /usr/include/sys/cdefs.h:595:10
pub const __attribute_artificial__ = @compileError("unable to translate macro: undefined identifier `__artificial__`"); // /usr/include/sys/cdefs.h:604:10
pub const __extern_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/sys/cdefs.h:626:11
pub const __extern_always_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/sys/cdefs.h:627:11
pub const __fortify_function = __extern_always_inline ++ __attribute_artificial__;
pub const __va_arg_pack = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg_pack`"); // /usr/include/sys/cdefs.h:638:10
pub const __va_arg_pack_len = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg_pack_len`"); // /usr/include/sys/cdefs.h:639:10
pub const __restrict_arr = @compileError("unable to translate C expr: unexpected token '__restrict'"); // /usr/include/sys/cdefs.h:666:10
pub inline fn __glibc_unlikely(cond: anytype) @TypeOf(__builtin.expect(cond, @as(c_int, 0))) {
    _ = &cond;
    return __builtin.expect(cond, @as(c_int, 0));
}
pub inline fn __glibc_likely(cond: anytype) @TypeOf(__builtin.expect(cond, @as(c_int, 1))) {
    _ = &cond;
    return __builtin.expect(cond, @as(c_int, 1));
}
pub const __attribute_nonstring__ = "";
pub inline fn __attribute_copy__(arg: anytype) void {
    _ = &arg;
    return;
}
pub const __LDOUBLE_REDIRECTS_TO_FLOAT128_ABI = @as(c_int, 0);
pub inline fn __LDBL_REDIR1(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR(name: anytype, proto: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR1_NTH(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR_NTH(name: anytype, proto: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR2_DECL(name: anytype) void {
    _ = &name;
    return;
}
pub inline fn __LDBL_REDIR_DECL(name: anytype) void {
    _ = &name;
    return;
}
pub inline fn __REDIRECT_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT(name, proto, alias);
}
pub inline fn __REDIRECT_NTH_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT_NTH(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT_NTH(name, proto, alias);
}
pub const __glibc_macro_warning1 = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /usr/include/sys/cdefs.h:807:10
pub const __glibc_macro_warning = @compileError("unable to translate macro: undefined identifier `GCC`"); // /usr/include/sys/cdefs.h:808:10
pub const __HAVE_GENERIC_SELECTION = @as(c_int, 1);
pub const __glibc_const_generic = @compileError("unable to translate C expr: expected type instead got 'const'"); // /usr/include/sys/cdefs.h:837:10
pub inline fn __fortified_attr_access(a: anytype, o: anytype, s: anytype) void {
    _ = &a;
    _ = &o;
    _ = &s;
    return;
}
pub inline fn __attr_access(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __attr_access_none(argno: anytype) void {
    _ = &argno;
    return;
}
pub inline fn __attr_dealloc(dealloc: anytype, argno: anytype) void {
    _ = &dealloc;
    _ = &argno;
    return;
}
pub const __attr_dealloc_free = "";
pub const __attribute_returns_twice__ = @compileError("unable to translate macro: undefined identifier `__returns_twice__`"); // /usr/include/sys/cdefs.h:884:10
pub const __attribute_struct_may_alias__ = @compileError("unable to translate macro: undefined identifier `__may_alias__`"); // /usr/include/sys/cdefs.h:893:10
pub const __stub___compat_bdflush = "";
pub const __stub_chflags = "";
pub const __stub_fchflags = "";
pub const __stub_gtty = "";
pub const __stub_revoke = "";
pub const __stub_setlogin = "";
pub const __stub_sigreturn = "";
pub const __stub_stty = "";
pub const _BITS_TYPES_H = @as(c_int, 1);
pub const __S16_TYPE = c_short;
pub const __U16_TYPE = c_ushort;
pub const __S32_TYPE = c_int;
pub const __U32_TYPE = c_uint;
pub const __SLONGWORD_TYPE = c_long;
pub const __ULONGWORD_TYPE = c_ulong;
pub const __SQUAD_TYPE = c_long;
pub const __UQUAD_TYPE = c_ulong;
pub const __SWORD_TYPE = c_long;
pub const __UWORD_TYPE = c_ulong;
pub const __SLONG32_TYPE = c_int;
pub const __ULONG32_TYPE = c_uint;
pub const __S64_TYPE = c_long;
pub const __U64_TYPE = c_ulong;
pub const _BITS_TYPESIZES_H = @as(c_int, 1);
pub const __SYSCALL_SLONG_TYPE = __SLONGWORD_TYPE;
pub const __SYSCALL_ULONG_TYPE = __ULONGWORD_TYPE;
pub const __DEV_T_TYPE = __UQUAD_TYPE;
pub const __UID_T_TYPE = __U32_TYPE;
pub const __GID_T_TYPE = __U32_TYPE;
pub const __INO_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __INO64_T_TYPE = __UQUAD_TYPE;
pub const __MODE_T_TYPE = __U32_TYPE;
pub const __NLINK_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSWORD_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF64_T_TYPE = __SQUAD_TYPE;
pub const __PID_T_TYPE = __S32_TYPE;
pub const __RLIM_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __RLIM64_T_TYPE = __UQUAD_TYPE;
pub const __BLKCNT_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __BLKCNT64_T_TYPE = __SQUAD_TYPE;
pub const __FSBLKCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSBLKCNT64_T_TYPE = __UQUAD_TYPE;
pub const __FSFILCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSFILCNT64_T_TYPE = __UQUAD_TYPE;
pub const __ID_T_TYPE = __U32_TYPE;
pub const __CLOCK_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __TIME_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __USECONDS_T_TYPE = __U32_TYPE;
pub const __SUSECONDS_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __SUSECONDS64_T_TYPE = __SQUAD_TYPE;
pub const __DADDR_T_TYPE = __S32_TYPE;
pub const __KEY_T_TYPE = __S32_TYPE;
pub const __CLOCKID_T_TYPE = __S32_TYPE;
pub const __TIMER_T_TYPE = ?*anyopaque;
pub const __BLKSIZE_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __FSID_T_TYPE = @compileError("unable to translate macro: undefined identifier `__val`"); // /usr/include/bits/typesizes.h:73:9
pub const __SSIZE_T_TYPE = __SWORD_TYPE;
pub const __CPU_MASK_TYPE = __SYSCALL_ULONG_TYPE;
pub const __OFF_T_MATCHES_OFF64_T = @as(c_int, 1);
pub const __INO_T_MATCHES_INO64_T = @as(c_int, 1);
pub const __RLIM_T_MATCHES_RLIM64_T = @as(c_int, 1);
pub const __STATFS_MATCHES_STATFS64 = @as(c_int, 1);
pub const __KERNEL_OLD_TIMEVAL_MATCHES_TIMEVAL64 = @as(c_int, 1);
pub const _BITS_TIME64_H = @as(c_int, 1);
pub const __TIME64_T_TYPE = __TIME_T_TYPE;
pub const __time_t_defined = @as(c_int, 1);
pub const __timeval_defined = @as(c_int, 1);
pub const __suseconds_t_defined = "";
pub const _SYS_SELECT_H = @as(c_int, 1);
pub const __FD_ZERO = @compileError("unable to translate macro: undefined identifier `__i`"); // /usr/include/bits/select.h:25:9
pub const __FD_SET = @compileError("unable to translate C expr: expected ')' instead got '|='"); // /usr/include/bits/select.h:32:9
pub const __FD_CLR = @compileError("unable to translate C expr: expected ')' instead got '&='"); // /usr/include/bits/select.h:34:9
pub inline fn __FD_ISSET(d: anytype, s: anytype) @TypeOf((__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0)) {
    _ = &d;
    _ = &s;
    return (__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0);
}
pub const __sigset_t_defined = @as(c_int, 1);
pub const ____sigset_t_defined = "";
pub const _SIGSET_NWORDS = __helpers.div(@as(c_int, 1024), @as(c_int, 8) * __helpers.sizeof(c_ulong));
pub const _STRUCT_TIMESPEC = @as(c_int, 1);
pub const _BITS_ENDIAN_H = @as(c_int, 1);
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __PDP_ENDIAN = @as(c_int, 3412);
pub const _BITS_ENDIANNESS_H = @as(c_int, 1);
pub const __BYTE_ORDER = __LITTLE_ENDIAN;
pub const __FLOAT_WORD_ORDER = __BYTE_ORDER;
pub inline fn __LONG_LONG_PAIR(HI: anytype, LO: anytype) @TypeOf(HI) {
    _ = &HI;
    _ = &LO;
    return blk: {
        _ = &LO;
        break :blk HI;
    };
}
pub const __NFDBITS = @as(c_int, 8) * __helpers.cast(c_int, __helpers.sizeof(__fd_mask));
pub inline fn __FD_ELT(d: anytype) @TypeOf(__helpers.div(d, __NFDBITS)) {
    _ = &d;
    return __helpers.div(d, __NFDBITS);
}
pub inline fn __FD_MASK(d: anytype) __fd_mask {
    _ = &d;
    return __helpers.cast(__fd_mask, @as(c_ulong, 1) << __helpers.rem(d, __NFDBITS));
}
pub inline fn __FDS_BITS(set: anytype) @TypeOf(set.*.__fds_bits) {
    _ = &set;
    return set.*.__fds_bits;
}
pub const FD_SETSIZE = __FD_SETSIZE;
pub const NFDBITS = __NFDBITS;
pub inline fn FD_SET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_SET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_SET(fd, fdsetp);
}
pub inline fn FD_CLR(fd: anytype, fdsetp: anytype) @TypeOf(__FD_CLR(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_CLR(fd, fdsetp);
}
pub inline fn FD_ISSET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_ISSET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_ISSET(fd, fdsetp);
}
pub inline fn FD_ZERO(fdsetp: anytype) @TypeOf(__FD_ZERO(fdsetp)) {
    _ = &fdsetp;
    return __FD_ZERO(fdsetp);
}
pub inline fn timerisset(tvp: anytype) @TypeOf((tvp.*.tv_sec != 0) or (tvp.*.tv_usec != 0)) {
    _ = &tvp;
    return (tvp.*.tv_sec != 0) or (tvp.*.tv_usec != 0);
}
pub const timerclear = @compileError("unable to translate C expr: expected ')' instead got '='"); // /usr/include/sys/time.h:232:10
pub inline fn timercmp(a: anytype, b: anytype, CMP: anytype) @TypeOf(if (__helpers.cast(bool, a.*.tv_sec == b.*.tv_sec)) a.*.tv_usec ++ CMP(b).*.tv_usec else a.*.tv_sec ++ CMP(b).*.tv_sec) {
    _ = &a;
    _ = &b;
    _ = &CMP;
    return if (__helpers.cast(bool, a.*.tv_sec == b.*.tv_sec)) a.*.tv_usec ++ CMP(b).*.tv_usec else a.*.tv_sec ++ CMP(b).*.tv_sec;
}
pub const timeradd = @compileError("unable to translate C expr: unexpected token 'do'"); // /usr/include/sys/time.h:237:10
pub const timersub = @compileError("unable to translate C expr: unexpected token 'do'"); // /usr/include/sys/time.h:247:10
pub const _SYS_IOCTL_H = @as(c_int, 1);
pub const __ASM_GENERIC_IOCTLS_H = "";
pub const _LINUX_IOCTL_H = "";
pub const _ASM_GENERIC_IOCTL_H = "";
pub const _IOC_NRBITS = @as(c_int, 8);
pub const _IOC_TYPEBITS = @as(c_int, 8);
pub const _IOC_SIZEBITS = @as(c_int, 14);
pub const _IOC_DIRBITS = @as(c_int, 2);
pub const _IOC_NRMASK = (@as(c_int, 1) << _IOC_NRBITS) - @as(c_int, 1);
pub const _IOC_TYPEMASK = (@as(c_int, 1) << _IOC_TYPEBITS) - @as(c_int, 1);
pub const _IOC_SIZEMASK = (@as(c_int, 1) << _IOC_SIZEBITS) - @as(c_int, 1);
pub const _IOC_DIRMASK = (@as(c_int, 1) << _IOC_DIRBITS) - @as(c_int, 1);
pub const _IOC_NRSHIFT = @as(c_int, 0);
pub const _IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS;
pub const _IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS;
pub const _IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS;
pub const _IOC_NONE = @as(c_uint, 0);
pub const _IOC_WRITE = @as(c_uint, 1);
pub const _IOC_READ = @as(c_uint, 2);
pub inline fn _IOC(dir: anytype, @"type": anytype, nr: anytype, size: anytype) @TypeOf((((dir << _IOC_DIRSHIFT) | (@"type" << _IOC_TYPESHIFT)) | (nr << _IOC_NRSHIFT)) | (size << _IOC_SIZESHIFT)) {
    _ = &dir;
    _ = &@"type";
    _ = &nr;
    _ = &size;
    return (((dir << _IOC_DIRSHIFT) | (@"type" << _IOC_TYPESHIFT)) | (nr << _IOC_NRSHIFT)) | (size << _IOC_SIZESHIFT);
}
pub inline fn _IOC_TYPECHECK(t: anytype) @TypeOf(__helpers.sizeof(t)) {
    _ = &t;
    return __helpers.sizeof(t);
}
pub inline fn _IO(@"type": anytype, nr: anytype) @TypeOf(_IOC(_IOC_NONE, @"type", nr, @as(c_int, 0))) {
    _ = &@"type";
    _ = &nr;
    return _IOC(_IOC_NONE, @"type", nr, @as(c_int, 0));
}
pub inline fn _IOR(@"type": anytype, nr: anytype, argtype: anytype) @TypeOf(_IOC(_IOC_READ, @"type", nr, _IOC_TYPECHECK(argtype))) {
    _ = &@"type";
    _ = &nr;
    _ = &argtype;
    return _IOC(_IOC_READ, @"type", nr, _IOC_TYPECHECK(argtype));
}
pub inline fn _IOW(@"type": anytype, nr: anytype, argtype: anytype) @TypeOf(_IOC(_IOC_WRITE, @"type", nr, _IOC_TYPECHECK(argtype))) {
    _ = &@"type";
    _ = &nr;
    _ = &argtype;
    return _IOC(_IOC_WRITE, @"type", nr, _IOC_TYPECHECK(argtype));
}
pub inline fn _IOWR(@"type": anytype, nr: anytype, argtype: anytype) @TypeOf(_IOC(_IOC_READ | _IOC_WRITE, @"type", nr, _IOC_TYPECHECK(argtype))) {
    _ = &@"type";
    _ = &nr;
    _ = &argtype;
    return _IOC(_IOC_READ | _IOC_WRITE, @"type", nr, _IOC_TYPECHECK(argtype));
}
pub inline fn _IOR_BAD(@"type": anytype, nr: anytype, argtype: anytype) @TypeOf(_IOC(_IOC_READ, @"type", nr, __helpers.sizeof(argtype))) {
    _ = &@"type";
    _ = &nr;
    _ = &argtype;
    return _IOC(_IOC_READ, @"type", nr, __helpers.sizeof(argtype));
}
pub inline fn _IOW_BAD(@"type": anytype, nr: anytype, argtype: anytype) @TypeOf(_IOC(_IOC_WRITE, @"type", nr, __helpers.sizeof(argtype))) {
    _ = &@"type";
    _ = &nr;
    _ = &argtype;
    return _IOC(_IOC_WRITE, @"type", nr, __helpers.sizeof(argtype));
}
pub inline fn _IOWR_BAD(@"type": anytype, nr: anytype, argtype: anytype) @TypeOf(_IOC(_IOC_READ | _IOC_WRITE, @"type", nr, __helpers.sizeof(argtype))) {
    _ = &@"type";
    _ = &nr;
    _ = &argtype;
    return _IOC(_IOC_READ | _IOC_WRITE, @"type", nr, __helpers.sizeof(argtype));
}
pub inline fn _IOC_DIR(nr: anytype) @TypeOf((nr >> _IOC_DIRSHIFT) & _IOC_DIRMASK) {
    _ = &nr;
    return (nr >> _IOC_DIRSHIFT) & _IOC_DIRMASK;
}
pub inline fn _IOC_TYPE(nr: anytype) @TypeOf((nr >> _IOC_TYPESHIFT) & _IOC_TYPEMASK) {
    _ = &nr;
    return (nr >> _IOC_TYPESHIFT) & _IOC_TYPEMASK;
}
pub inline fn _IOC_NR(nr: anytype) @TypeOf((nr >> _IOC_NRSHIFT) & _IOC_NRMASK) {
    _ = &nr;
    return (nr >> _IOC_NRSHIFT) & _IOC_NRMASK;
}
pub inline fn _IOC_SIZE(nr: anytype) @TypeOf((nr >> _IOC_SIZESHIFT) & _IOC_SIZEMASK) {
    _ = &nr;
    return (nr >> _IOC_SIZESHIFT) & _IOC_SIZEMASK;
}
pub const IOC_IN = _IOC_WRITE << _IOC_DIRSHIFT;
pub const IOC_OUT = _IOC_READ << _IOC_DIRSHIFT;
pub const IOC_INOUT = (_IOC_WRITE | _IOC_READ) << _IOC_DIRSHIFT;
pub const IOCSIZE_MASK = _IOC_SIZEMASK << _IOC_SIZESHIFT;
pub const IOCSIZE_SHIFT = _IOC_SIZESHIFT;
pub const TCGETS = @as(c_int, 0x5401);
pub const TCSETS = @as(c_int, 0x5402);
pub const TCSETSW = @as(c_int, 0x5403);
pub const TCSETSF = @as(c_int, 0x5404);
pub const TCGETA = @as(c_int, 0x5405);
pub const TCSETA = @as(c_int, 0x5406);
pub const TCSETAW = @as(c_int, 0x5407);
pub const TCSETAF = @as(c_int, 0x5408);
pub const TCSBRK = @as(c_int, 0x5409);
pub const TCXONC = @as(c_int, 0x540A);
pub const TCFLSH = @as(c_int, 0x540B);
pub const TIOCEXCL = @as(c_int, 0x540C);
pub const TIOCNXCL = @as(c_int, 0x540D);
pub const TIOCSCTTY = @as(c_int, 0x540E);
pub const TIOCGPGRP = @as(c_int, 0x540F);
pub const TIOCSPGRP = @as(c_int, 0x5410);
pub const TIOCOUTQ = @as(c_int, 0x5411);
pub const TIOCSTI = @as(c_int, 0x5412);
pub const TIOCGWINSZ = @as(c_int, 0x5413);
pub const TIOCSWINSZ = @as(c_int, 0x5414);
pub const TIOCMGET = @as(c_int, 0x5415);
pub const TIOCMBIS = @as(c_int, 0x5416);
pub const TIOCMBIC = @as(c_int, 0x5417);
pub const TIOCMSET = @as(c_int, 0x5418);
pub const TIOCGSOFTCAR = @as(c_int, 0x5419);
pub const TIOCSSOFTCAR = @as(c_int, 0x541A);
pub const FIONREAD = @as(c_int, 0x541B);
pub const TIOCINQ = FIONREAD;
pub const TIOCLINUX = @as(c_int, 0x541C);
pub const TIOCCONS = @as(c_int, 0x541D);
pub const TIOCGSERIAL = @as(c_int, 0x541E);
pub const TIOCSSERIAL = @as(c_int, 0x541F);
pub const TIOCPKT = @as(c_int, 0x5420);
pub const FIONBIO = @as(c_int, 0x5421);
pub const TIOCNOTTY = @as(c_int, 0x5422);
pub const TIOCSETD = @as(c_int, 0x5423);
pub const TIOCGETD = @as(c_int, 0x5424);
pub const TCSBRKP = @as(c_int, 0x5425);
pub const TIOCSBRK = @as(c_int, 0x5427);
pub const TIOCCBRK = @as(c_int, 0x5428);
pub const TIOCGSID = @as(c_int, 0x5429);
pub const TCGETS2 = @compileError("unable to translate macro: undefined identifier `termios2`"); // /usr/include/asm-generic/ioctls.h:61:9
pub const TCSETS2 = @compileError("unable to translate macro: undefined identifier `termios2`"); // /usr/include/asm-generic/ioctls.h:62:9
pub const TCSETSW2 = @compileError("unable to translate macro: undefined identifier `termios2`"); // /usr/include/asm-generic/ioctls.h:63:9
pub const TCSETSF2 = @compileError("unable to translate macro: undefined identifier `termios2`"); // /usr/include/asm-generic/ioctls.h:64:9
pub const TIOCGRS485 = @as(c_int, 0x542E);
pub const TIOCSRS485 = @as(c_int, 0x542F);
pub const TIOCGPTN = _IOR('T', @as(c_int, 0x30), c_uint);
pub const TIOCSPTLCK = _IOW('T', @as(c_int, 0x31), c_int);
pub const TIOCGDEV = _IOR('T', @as(c_int, 0x32), c_uint);
pub const TCGETX = @as(c_int, 0x5432);
pub const TCSETX = @as(c_int, 0x5433);
pub const TCSETXF = @as(c_int, 0x5434);
pub const TCSETXW = @as(c_int, 0x5435);
pub const TIOCSIG = _IOW('T', @as(c_int, 0x36), c_int);
pub const TIOCVHANGUP = @as(c_int, 0x5437);
pub const TIOCGPKT = _IOR('T', @as(c_int, 0x38), c_int);
pub const TIOCGPTLCK = _IOR('T', @as(c_int, 0x39), c_int);
pub const TIOCGEXCL = _IOR('T', @as(c_int, 0x40), c_int);
pub const TIOCGPTPEER = _IO('T', @as(c_int, 0x41));
pub const TIOCGISO7816 = @compileError("unable to translate macro: undefined identifier `serial_iso7816`"); // /usr/include/asm-generic/ioctls.h:82:9
pub const TIOCSISO7816 = @compileError("unable to translate macro: undefined identifier `serial_iso7816`"); // /usr/include/asm-generic/ioctls.h:83:9
pub const FIONCLEX = @as(c_int, 0x5450);
pub const FIOCLEX = @as(c_int, 0x5451);
pub const FIOASYNC = @as(c_int, 0x5452);
pub const TIOCSERCONFIG = @as(c_int, 0x5453);
pub const TIOCSERGWILD = @as(c_int, 0x5454);
pub const TIOCSERSWILD = @as(c_int, 0x5455);
pub const TIOCGLCKTRMIOS = @as(c_int, 0x5456);
pub const TIOCSLCKTRMIOS = @as(c_int, 0x5457);
pub const TIOCSERGSTRUCT = @as(c_int, 0x5458);
pub const TIOCSERGETLSR = @as(c_int, 0x5459);
pub const TIOCSERGETMULTI = @as(c_int, 0x545A);
pub const TIOCSERSETMULTI = @as(c_int, 0x545B);
pub const TIOCMIWAIT = @as(c_int, 0x545C);
pub const TIOCGICOUNT = @as(c_int, 0x545D);
pub const FIOQSIZE = @as(c_int, 0x5460);
pub const TIOCPKT_DATA = @as(c_int, 0);
pub const TIOCPKT_FLUSHREAD = @as(c_int, 1);
pub const TIOCPKT_FLUSHWRITE = @as(c_int, 2);
pub const TIOCPKT_STOP = @as(c_int, 4);
pub const TIOCPKT_START = @as(c_int, 8);
pub const TIOCPKT_NOSTOP = @as(c_int, 16);
pub const TIOCPKT_DOSTOP = @as(c_int, 32);
pub const TIOCPKT_IOCTL = @as(c_int, 64);
pub const TIOCSER_TEMT = @as(c_int, 0x01);
pub const _LINUX_SOCKIOS_H = "";
pub const __ASM_X86_BITSPERLONG_H = "";
pub const __BITS_PER_LONG = @as(c_int, 64);
pub const __ASM_GENERIC_BITS_PER_LONG = "";
pub const __BITS_PER_LONG_LONG = @as(c_int, 64);
pub const __ASM_GENERIC_SOCKIOS_H = "";
pub const FIOSETOWN = __helpers.promoteIntLiteral(c_int, 0x8901, .hex);
pub const SIOCSPGRP = __helpers.promoteIntLiteral(c_int, 0x8902, .hex);
pub const FIOGETOWN = __helpers.promoteIntLiteral(c_int, 0x8903, .hex);
pub const SIOCGPGRP = __helpers.promoteIntLiteral(c_int, 0x8904, .hex);
pub const SIOCATMARK = __helpers.promoteIntLiteral(c_int, 0x8905, .hex);
pub const SIOCGSTAMP_OLD = __helpers.promoteIntLiteral(c_int, 0x8906, .hex);
pub const SIOCGSTAMPNS_OLD = __helpers.promoteIntLiteral(c_int, 0x8907, .hex);
pub const SIOCINQ = FIONREAD;
pub const SIOCOUTQ = TIOCOUTQ;
pub const SOCK_IOC_TYPE = @as(c_int, 0x89);
pub const SIOCGSTAMP_NEW = _IOR(SOCK_IOC_TYPE, @as(c_int, 0x06), c_longlong[@as(usize, @intCast(@as(c_int, 2)))]);
pub const SIOCGSTAMPNS_NEW = _IOR(SOCK_IOC_TYPE, @as(c_int, 0x07), c_longlong[@as(usize, @intCast(@as(c_int, 2)))]);
pub const SIOCGSTAMP = SIOCGSTAMP_OLD;
pub const SIOCGSTAMPNS = SIOCGSTAMPNS_OLD;
pub const SIOCADDRT = __helpers.promoteIntLiteral(c_int, 0x890B, .hex);
pub const SIOCDELRT = __helpers.promoteIntLiteral(c_int, 0x890C, .hex);
pub const SIOCRTMSG = __helpers.promoteIntLiteral(c_int, 0x890D, .hex);
pub const SIOCGIFNAME = __helpers.promoteIntLiteral(c_int, 0x8910, .hex);
pub const SIOCSIFLINK = __helpers.promoteIntLiteral(c_int, 0x8911, .hex);
pub const SIOCGIFCONF = __helpers.promoteIntLiteral(c_int, 0x8912, .hex);
pub const SIOCGIFFLAGS = __helpers.promoteIntLiteral(c_int, 0x8913, .hex);
pub const SIOCSIFFLAGS = __helpers.promoteIntLiteral(c_int, 0x8914, .hex);
pub const SIOCGIFADDR = __helpers.promoteIntLiteral(c_int, 0x8915, .hex);
pub const SIOCSIFADDR = __helpers.promoteIntLiteral(c_int, 0x8916, .hex);
pub const SIOCGIFDSTADDR = __helpers.promoteIntLiteral(c_int, 0x8917, .hex);
pub const SIOCSIFDSTADDR = __helpers.promoteIntLiteral(c_int, 0x8918, .hex);
pub const SIOCGIFBRDADDR = __helpers.promoteIntLiteral(c_int, 0x8919, .hex);
pub const SIOCSIFBRDADDR = __helpers.promoteIntLiteral(c_int, 0x891a, .hex);
pub const SIOCGIFNETMASK = __helpers.promoteIntLiteral(c_int, 0x891b, .hex);
pub const SIOCSIFNETMASK = __helpers.promoteIntLiteral(c_int, 0x891c, .hex);
pub const SIOCGIFMETRIC = __helpers.promoteIntLiteral(c_int, 0x891d, .hex);
pub const SIOCSIFMETRIC = __helpers.promoteIntLiteral(c_int, 0x891e, .hex);
pub const SIOCGIFMEM = __helpers.promoteIntLiteral(c_int, 0x891f, .hex);
pub const SIOCSIFMEM = __helpers.promoteIntLiteral(c_int, 0x8920, .hex);
pub const SIOCGIFMTU = __helpers.promoteIntLiteral(c_int, 0x8921, .hex);
pub const SIOCSIFMTU = __helpers.promoteIntLiteral(c_int, 0x8922, .hex);
pub const SIOCSIFNAME = __helpers.promoteIntLiteral(c_int, 0x8923, .hex);
pub const SIOCSIFHWADDR = __helpers.promoteIntLiteral(c_int, 0x8924, .hex);
pub const SIOCGIFENCAP = __helpers.promoteIntLiteral(c_int, 0x8925, .hex);
pub const SIOCSIFENCAP = __helpers.promoteIntLiteral(c_int, 0x8926, .hex);
pub const SIOCGIFHWADDR = __helpers.promoteIntLiteral(c_int, 0x8927, .hex);
pub const SIOCGIFSLAVE = __helpers.promoteIntLiteral(c_int, 0x8929, .hex);
pub const SIOCSIFSLAVE = __helpers.promoteIntLiteral(c_int, 0x8930, .hex);
pub const SIOCADDMULTI = __helpers.promoteIntLiteral(c_int, 0x8931, .hex);
pub const SIOCDELMULTI = __helpers.promoteIntLiteral(c_int, 0x8932, .hex);
pub const SIOCGIFINDEX = __helpers.promoteIntLiteral(c_int, 0x8933, .hex);
pub const SIOGIFINDEX = SIOCGIFINDEX;
pub const SIOCSIFPFLAGS = __helpers.promoteIntLiteral(c_int, 0x8934, .hex);
pub const SIOCGIFPFLAGS = __helpers.promoteIntLiteral(c_int, 0x8935, .hex);
pub const SIOCDIFADDR = __helpers.promoteIntLiteral(c_int, 0x8936, .hex);
pub const SIOCSIFHWBROADCAST = __helpers.promoteIntLiteral(c_int, 0x8937, .hex);
pub const SIOCGIFCOUNT = __helpers.promoteIntLiteral(c_int, 0x8938, .hex);
pub const SIOCGIFBR = __helpers.promoteIntLiteral(c_int, 0x8940, .hex);
pub const SIOCSIFBR = __helpers.promoteIntLiteral(c_int, 0x8941, .hex);
pub const SIOCGIFTXQLEN = __helpers.promoteIntLiteral(c_int, 0x8942, .hex);
pub const SIOCSIFTXQLEN = __helpers.promoteIntLiteral(c_int, 0x8943, .hex);
pub const SIOCETHTOOL = __helpers.promoteIntLiteral(c_int, 0x8946, .hex);
pub const SIOCGMIIPHY = __helpers.promoteIntLiteral(c_int, 0x8947, .hex);
pub const SIOCGMIIREG = __helpers.promoteIntLiteral(c_int, 0x8948, .hex);
pub const SIOCSMIIREG = __helpers.promoteIntLiteral(c_int, 0x8949, .hex);
pub const SIOCWANDEV = __helpers.promoteIntLiteral(c_int, 0x894A, .hex);
pub const SIOCOUTQNSD = __helpers.promoteIntLiteral(c_int, 0x894B, .hex);
pub const SIOCGSKNS = __helpers.promoteIntLiteral(c_int, 0x894C, .hex);
pub const SIOCDARP = __helpers.promoteIntLiteral(c_int, 0x8953, .hex);
pub const SIOCGARP = __helpers.promoteIntLiteral(c_int, 0x8954, .hex);
pub const SIOCSARP = __helpers.promoteIntLiteral(c_int, 0x8955, .hex);
pub const SIOCDRARP = __helpers.promoteIntLiteral(c_int, 0x8960, .hex);
pub const SIOCGRARP = __helpers.promoteIntLiteral(c_int, 0x8961, .hex);
pub const SIOCSRARP = __helpers.promoteIntLiteral(c_int, 0x8962, .hex);
pub const SIOCGIFMAP = __helpers.promoteIntLiteral(c_int, 0x8970, .hex);
pub const SIOCSIFMAP = __helpers.promoteIntLiteral(c_int, 0x8971, .hex);
pub const SIOCADDDLCI = __helpers.promoteIntLiteral(c_int, 0x8980, .hex);
pub const SIOCDELDLCI = __helpers.promoteIntLiteral(c_int, 0x8981, .hex);
pub const SIOCGIFVLAN = __helpers.promoteIntLiteral(c_int, 0x8982, .hex);
pub const SIOCSIFVLAN = __helpers.promoteIntLiteral(c_int, 0x8983, .hex);
pub const SIOCBONDENSLAVE = __helpers.promoteIntLiteral(c_int, 0x8990, .hex);
pub const SIOCBONDRELEASE = __helpers.promoteIntLiteral(c_int, 0x8991, .hex);
pub const SIOCBONDSETHWADDR = __helpers.promoteIntLiteral(c_int, 0x8992, .hex);
pub const SIOCBONDSLAVEINFOQUERY = __helpers.promoteIntLiteral(c_int, 0x8993, .hex);
pub const SIOCBONDINFOQUERY = __helpers.promoteIntLiteral(c_int, 0x8994, .hex);
pub const SIOCBONDCHANGEACTIVE = __helpers.promoteIntLiteral(c_int, 0x8995, .hex);
pub const SIOCBRADDBR = __helpers.promoteIntLiteral(c_int, 0x89a0, .hex);
pub const SIOCBRDELBR = __helpers.promoteIntLiteral(c_int, 0x89a1, .hex);
pub const SIOCBRADDIF = __helpers.promoteIntLiteral(c_int, 0x89a2, .hex);
pub const SIOCBRDELIF = __helpers.promoteIntLiteral(c_int, 0x89a3, .hex);
pub const SIOCSHWTSTAMP = __helpers.promoteIntLiteral(c_int, 0x89b0, .hex);
pub const SIOCGHWTSTAMP = __helpers.promoteIntLiteral(c_int, 0x89b1, .hex);
pub const SIOCDEVPRIVATE = __helpers.promoteIntLiteral(c_int, 0x89F0, .hex);
pub const SIOCPROTOPRIVATE = __helpers.promoteIntLiteral(c_int, 0x89E0, .hex);
pub const TIOCM_LE = @as(c_int, 0x001);
pub const TIOCM_DTR = @as(c_int, 0x002);
pub const TIOCM_RTS = @as(c_int, 0x004);
pub const TIOCM_ST = @as(c_int, 0x008);
pub const TIOCM_SR = @as(c_int, 0x010);
pub const TIOCM_CTS = @as(c_int, 0x020);
pub const TIOCM_CAR = @as(c_int, 0x040);
pub const TIOCM_RNG = @as(c_int, 0x080);
pub const TIOCM_DSR = @as(c_int, 0x100);
pub const TIOCM_CD = TIOCM_CAR;
pub const TIOCM_RI = TIOCM_RNG;
pub const N_TTY = @as(c_int, 0);
pub const N_SLIP = @as(c_int, 1);
pub const N_MOUSE = @as(c_int, 2);
pub const N_PPP = @as(c_int, 3);
pub const N_STRIP = @as(c_int, 4);
pub const N_AX25 = @as(c_int, 5);
pub const N_X25 = @as(c_int, 6);
pub const N_6PACK = @as(c_int, 7);
pub const N_MASC = @as(c_int, 8);
pub const N_R3964 = @as(c_int, 9);
pub const N_PROFIBUS_FDL = @as(c_int, 10);
pub const N_IRDA = @as(c_int, 11);
pub const N_SMSBLOCK = @as(c_int, 12);
pub const N_HDLC = @as(c_int, 13);
pub const N_SYNC_PPP = @as(c_int, 14);
pub const N_HCI = @as(c_int, 15);
pub const _SYS_TTYDEFAULTS_H_ = "";
pub const TTYDEF_IFLAG = @compileError("unable to translate macro: undefined identifier `BRKINT`"); // /usr/include/sys/ttydefaults.h:46:9
pub const TTYDEF_OFLAG = @compileError("unable to translate macro: undefined identifier `OPOST`"); // /usr/include/sys/ttydefaults.h:47:9
pub const TTYDEF_LFLAG = @compileError("unable to translate macro: undefined identifier `ECHO`"); // /usr/include/sys/ttydefaults.h:48:9
pub const TTYDEF_CFLAG = @compileError("unable to translate macro: undefined identifier `CREAD`"); // /usr/include/sys/ttydefaults.h:49:9
pub const TTYDEF_SPEED = @compileError("unable to translate macro: undefined identifier `B9600`"); // /usr/include/sys/ttydefaults.h:50:9
pub inline fn CTRL(x: anytype) @TypeOf(x & @as(c_int, 0o37)) {
    _ = &x;
    return x & @as(c_int, 0o37);
}
pub const CEOF = CTRL('d');
pub const CEOL = '\x00';
pub const CERASE = @as(c_int, 0o177);
pub const CINTR = CTRL('c');
pub const CSTATUS = '\x00';
pub const CKILL = CTRL('u');
pub const CMIN = @as(c_int, 1);
pub const CQUIT = @as(c_int, 0o34);
pub const CSUSP = CTRL('z');
pub const CTIME = @as(c_int, 0);
pub const CDSUSP = CTRL('y');
pub const CSTART = CTRL('q');
pub const CSTOP = CTRL('s');
pub const CLNEXT = CTRL('v');
pub const CDISCARD = CTRL('o');
pub const CWERASE = CTRL('w');
pub const CREPRINT = CTRL('r');
pub const CEOT = CEOF;
pub const CBRK = CEOL;
pub const CRPRNT = CREPRINT;
pub const CFLUSH = CDISCARD;
pub const _SYS_TYPES_H = @as(c_int, 1);
pub const __u_char_defined = "";
pub const __ino_t_defined = "";
pub const __dev_t_defined = "";
pub const __gid_t_defined = "";
pub const __mode_t_defined = "";
pub const __nlink_t_defined = "";
pub const __uid_t_defined = "";
pub const __off_t_defined = "";
pub const __pid_t_defined = "";
pub const __id_t_defined = "";
pub const __ssize_t_defined = "";
pub const __daddr_t_defined = "";
pub const __key_t_defined = "";
pub const __clock_t_defined = @as(c_int, 1);
pub const __clockid_t_defined = @as(c_int, 1);
pub const __timer_t_defined = @as(c_int, 1);
pub const __need_size_t = "";
pub const __STDC_VERSION_STDDEF_H__ = @as(c_long, 202311);
pub const NULL = __helpers.cast(?*anyopaque, @as(c_int, 0));
pub const offsetof = @compileError("unable to translate macro: undefined identifier `__builtin_offsetof`"); // /home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw/include/stddef.h:18:9
pub const _BITS_STDINT_INTN_H = @as(c_int, 1);
pub const __BIT_TYPES_DEFINED__ = @as(c_int, 1);
pub const _ENDIAN_H = @as(c_int, 1);
pub const LITTLE_ENDIAN = __LITTLE_ENDIAN;
pub const BIG_ENDIAN = __BIG_ENDIAN;
pub const PDP_ENDIAN = __PDP_ENDIAN;
pub const BYTE_ORDER = __BYTE_ORDER;
pub const _BITS_BYTESWAP_H = @as(c_int, 1);
pub inline fn __bswap_constant_16(x: anytype) __uint16_t {
    _ = &x;
    return __helpers.cast(__uint16_t, ((x >> @as(c_int, 8)) & @as(c_int, 0xff)) | ((x & @as(c_int, 0xff)) << @as(c_int, 8)));
}
pub inline fn __bswap_constant_32(x: anytype) @TypeOf(((((x & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24))) {
    _ = &x;
    return ((((x & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24));
}
pub inline fn __bswap_constant_64(x: anytype) @TypeOf(((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56))) {
    _ = &x;
    return ((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56));
}
pub const _BITS_UINTN_IDENTITY_H = @as(c_int, 1);
pub inline fn htobe16(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn htole16(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn be16toh(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn le16toh(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn htobe32(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn htole32(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn be32toh(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn le32toh(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn htobe64(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn htole64(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub inline fn be64toh(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn le64toh(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub const __blksize_t_defined = "";
pub const __blkcnt_t_defined = "";
pub const __fsblkcnt_t_defined = "";
pub const __fsfilcnt_t_defined = "";
pub const _BITS_PTHREADTYPES_COMMON_H = @as(c_int, 1);
pub const _THREAD_SHARED_TYPES_H = @as(c_int, 1);
pub const _BITS_PTHREADTYPES_ARCH_H = @as(c_int, 1);
pub const __SIZEOF_PTHREAD_MUTEX_T = @as(c_int, 40);
pub const __SIZEOF_PTHREAD_ATTR_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_RWLOCK_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_BARRIER_T = @as(c_int, 32);
pub const __SIZEOF_PTHREAD_MUTEXATTR_T = @as(c_int, 4);
pub const __SIZEOF_PTHREAD_COND_T = @as(c_int, 48);
pub const __SIZEOF_PTHREAD_CONDATTR_T = @as(c_int, 4);
pub const __SIZEOF_PTHREAD_RWLOCKATTR_T = @as(c_int, 8);
pub const __SIZEOF_PTHREAD_BARRIERATTR_T = @as(c_int, 4);
pub const __LOCK_ALIGNMENT = "";
pub const __ONCE_ALIGNMENT = "";
pub const _BITS_ATOMIC_WIDE_COUNTER_H = "";
pub const _THREAD_MUTEX_INTERNAL_H = @as(c_int, 1);
pub const __PTHREAD_MUTEX_HAVE_PREV = @as(c_int, 1);
pub const __PTHREAD_MUTEX_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/struct_mutex.h:55:10
pub const _RWLOCK_INTERNAL_H = "";
pub inline fn __PTHREAD_RWLOCK_INITIALIZER(__flags: anytype) @TypeOf(__flags) {
    _ = &__flags;
    return blk: {
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        break :blk __flags;
    };
}
pub const __ONCE_FLAG_INIT = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/thread-shared-types.h:114:9
pub const __have_pthread_attr_t = @as(c_int, 1);
pub const _LINUX_TYPES_H = "";
pub const _ASM_GENERIC_TYPES_H = "";
pub const _ASM_GENERIC_INT_LL64_H = "";
pub const _LINUX_POSIX_TYPES_H = "";
pub const _LINUX_STDDEF_H = "";
pub inline fn __struct_group_tag(TAG: anytype) @TypeOf(TAG) {
    _ = &TAG;
    return TAG;
}
pub const __struct_group = @compileError("unable to translate C expr: unexpected token 'union'"); // /usr/include/linux/stddef.h:32:9
pub const __DECLARE_FLEX_ARRAY = @compileError("unable to translate macro: undefined identifier `__empty_`"); // /usr/include/linux/stddef.h:53:9
pub inline fn __counted_by(m: anytype) void {
    _ = &m;
    return;
}
pub inline fn __counted_by_le(m: anytype) void {
    _ = &m;
    return;
}
pub inline fn __counted_by_be(m: anytype) void {
    _ = &m;
    return;
}
pub inline fn __counted_by_ptr(m: anytype) void {
    _ = &m;
    return;
}
pub const __kernel_nonstring = "";
pub const __FD_SETSIZE = @as(c_int, 1024);
pub const _ASM_X86_POSIX_TYPES_64_H = "";
pub const __ASM_GENERIC_POSIX_TYPES_H = "";
pub const __bitwise = "";
pub const __bitwise__ = "";
pub const __aligned_u64 = @compileError("unable to translate macro: undefined identifier `aligned`"); // /usr/include/linux/types.h:50:9
pub const __aligned_s64 = @compileError("unable to translate macro: undefined identifier `aligned`"); // /usr/include/linux/types.h:51:9
pub const __aligned_be64 = @compileError("unable to translate macro: undefined identifier `aligned`"); // /usr/include/linux/types.h:52:9
pub const __aligned_le64 = @compileError("unable to translate macro: undefined identifier `aligned`"); // /usr/include/linux/types.h:53:9
pub const input_event_sec = @compileError("unable to translate macro: undefined identifier `time`"); // /usr/include/linux/input.h:29:9
pub const input_event_usec = @compileError("unable to translate macro: undefined identifier `time`"); // /usr/include/linux/input.h:30:9
pub const EV_VERSION = __helpers.promoteIntLiteral(c_int, 0x010001, .hex);
pub const INPUT_KEYMAP_BY_INDEX = @as(c_int, 1) << @as(c_int, 0);
pub const EVIOCGVERSION = _IOR('E', @as(c_int, 0x01), c_int);
pub const EVIOCGID = _IOR('E', @as(c_int, 0x02), struct_input_id);
pub const EVIOCGREP = _IOR('E', @as(c_int, 0x03), c_uint[@as(usize, @intCast(@as(c_int, 2)))]);
pub const EVIOCSREP = _IOW('E', @as(c_int, 0x03), c_uint[@as(usize, @intCast(@as(c_int, 2)))]);
pub const EVIOCGKEYCODE = _IOR('E', @as(c_int, 0x04), c_uint[@as(usize, @intCast(@as(c_int, 2)))]);
pub const EVIOCGKEYCODE_V2 = _IOR('E', @as(c_int, 0x04), struct_input_keymap_entry);
pub const EVIOCSKEYCODE = _IOW('E', @as(c_int, 0x04), c_uint[@as(usize, @intCast(@as(c_int, 2)))]);
pub const EVIOCSKEYCODE_V2 = _IOW('E', @as(c_int, 0x04), struct_input_keymap_entry);
pub inline fn EVIOCGNAME(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x06), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x06), len);
}
pub inline fn EVIOCGPHYS(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x07), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x07), len);
}
pub inline fn EVIOCGUNIQ(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x08), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x08), len);
}
pub inline fn EVIOCGPROP(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x09), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x09), len);
}
pub inline fn EVIOCGMTSLOTS(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x0a), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x0a), len);
}
pub inline fn EVIOCGKEY(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x18), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x18), len);
}
pub inline fn EVIOCGLED(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x19), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x19), len);
}
pub inline fn EVIOCGSND(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x1a), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x1a), len);
}
pub inline fn EVIOCGSW(len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x1b), len)) {
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x1b), len);
}
pub inline fn EVIOCGBIT(ev: anytype, len: anytype) @TypeOf(_IOC(_IOC_READ, 'E', @as(c_int, 0x20) + ev, len)) {
    _ = &ev;
    _ = &len;
    return _IOC(_IOC_READ, 'E', @as(c_int, 0x20) + ev, len);
}
pub inline fn EVIOCGABS(abs_1: anytype) @TypeOf(_IOR('E', @as(c_int, 0x40) + abs_1, struct_input_absinfo)) {
    _ = &abs_1;
    return _IOR('E', @as(c_int, 0x40) + abs_1, struct_input_absinfo);
}
pub inline fn EVIOCSABS(abs_1: anytype) @TypeOf(_IOW('E', @as(c_int, 0xc0) + abs_1, struct_input_absinfo)) {
    _ = &abs_1;
    return _IOW('E', @as(c_int, 0xc0) + abs_1, struct_input_absinfo);
}
pub const EVIOCSFF = _IOW('E', @as(c_int, 0x80), struct_ff_effect);
pub const EVIOCRMFF = _IOW('E', @as(c_int, 0x81), c_int);
pub const EVIOCGEFFECTS = _IOR('E', @as(c_int, 0x84), c_int);
pub const EVIOCGRAB = _IOW('E', @as(c_int, 0x90), c_int);
pub const EVIOCREVOKE = _IOW('E', @as(c_int, 0x91), c_int);
pub const EVIOCGMASK = _IOR('E', @as(c_int, 0x92), struct_input_mask);
pub const EVIOCSMASK = _IOW('E', @as(c_int, 0x93), struct_input_mask);
pub const EVIOCSCLOCKID = _IOW('E', @as(c_int, 0xa0), c_int);
pub const ID_BUS = @as(c_int, 0);
pub const ID_VENDOR = @as(c_int, 1);
pub const ID_PRODUCT = @as(c_int, 2);
pub const ID_VERSION = @as(c_int, 3);
pub const BUS_PCI = @as(c_int, 0x01);
pub const BUS_ISAPNP = @as(c_int, 0x02);
pub const BUS_USB = @as(c_int, 0x03);
pub const BUS_HIL = @as(c_int, 0x04);
pub const BUS_BLUETOOTH = @as(c_int, 0x05);
pub const BUS_VIRTUAL = @as(c_int, 0x06);
pub const BUS_ISA = @as(c_int, 0x10);
pub const BUS_I8042 = @as(c_int, 0x11);
pub const BUS_XTKBD = @as(c_int, 0x12);
pub const BUS_RS232 = @as(c_int, 0x13);
pub const BUS_GAMEPORT = @as(c_int, 0x14);
pub const BUS_PARPORT = @as(c_int, 0x15);
pub const BUS_AMIGA = @as(c_int, 0x16);
pub const BUS_ADB = @as(c_int, 0x17);
pub const BUS_I2C = @as(c_int, 0x18);
pub const BUS_HOST = @as(c_int, 0x19);
pub const BUS_GSC = @as(c_int, 0x1A);
pub const BUS_ATARI = @as(c_int, 0x1B);
pub const BUS_SPI = @as(c_int, 0x1C);
pub const BUS_RMI = @as(c_int, 0x1D);
pub const BUS_CEC = @as(c_int, 0x1E);
pub const BUS_INTEL_ISHTP = @as(c_int, 0x1F);
pub const BUS_AMD_SFH = @as(c_int, 0x20);
pub const BUS_SDW = @as(c_int, 0x21);
pub const MT_TOOL_FINGER = @as(c_int, 0x00);
pub const MT_TOOL_PEN = @as(c_int, 0x01);
pub const MT_TOOL_PALM = @as(c_int, 0x02);
pub const MT_TOOL_DIAL = @as(c_int, 0x0a);
pub const MT_TOOL_MAX = @as(c_int, 0x0f);
pub const FF_STATUS_STOPPED = @as(c_int, 0x00);
pub const FF_STATUS_PLAYING = @as(c_int, 0x01);
pub const FF_STATUS_MAX = @as(c_int, 0x01);
pub const FF_HAPTIC = @as(c_int, 0x4f);
pub const FF_RUMBLE = @as(c_int, 0x50);
pub const FF_PERIODIC = @as(c_int, 0x51);
pub const FF_CONSTANT = @as(c_int, 0x52);
pub const FF_SPRING = @as(c_int, 0x53);
pub const FF_FRICTION = @as(c_int, 0x54);
pub const FF_DAMPER = @as(c_int, 0x55);
pub const FF_INERTIA = @as(c_int, 0x56);
pub const FF_RAMP = @as(c_int, 0x57);
pub const FF_EFFECT_MIN = FF_HAPTIC;
pub const FF_EFFECT_MAX = FF_RAMP;
pub const FF_SQUARE = @as(c_int, 0x58);
pub const FF_TRIANGLE = @as(c_int, 0x59);
pub const FF_SINE = @as(c_int, 0x5a);
pub const FF_SAW_UP = @as(c_int, 0x5b);
pub const FF_SAW_DOWN = @as(c_int, 0x5c);
pub const FF_CUSTOM = @as(c_int, 0x5d);
pub const FF_WAVEFORM_MIN = FF_SQUARE;
pub const FF_WAVEFORM_MAX = FF_CUSTOM;
pub const FF_GAIN = @as(c_int, 0x60);
pub const FF_AUTOCENTER = @as(c_int, 0x61);
pub const FF_MAX_EFFECTS = FF_GAIN;
pub const FF_MAX = @as(c_int, 0x7f);
pub const FF_CNT = FF_MAX + @as(c_int, 1);
pub const __STDC_VERSION_STDARG_H__ = @as(c_int, 0);
pub const va_start = @compileError("unable to translate macro: undefined identifier `__builtin_va_start`"); // /home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw/include/stdarg.h:12:9
pub const va_end = @compileError("unable to translate macro: undefined identifier `__builtin_va_end`"); // /home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw/include/stdarg.h:14:9
pub const va_arg = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg`"); // /home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw/include/stdarg.h:15:9
pub const __va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`"); // /home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw/include/stdarg.h:18:9
pub const va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`"); // /home/logan/Developer/pangolin_desktop-main/river-main/river/zig-pkg/aro-0.0.0-JSD1QmbSNgDrBkBPRoDPwy1rN1ABGBa7B1NzC-lqnGxw/include/stdarg.h:22:9
pub const __GNUC_VA_LIST = @as(c_int, 1);
pub const LIBEVDEV_ATTRIBUTE_PRINTF = @compileError("unable to translate macro: undefined identifier `format`"); // /usr/include/libevdev-1.0/libevdev/libevdev.h:36:9
pub const LIBEVDEV_DEPRECATED = @compileError("unable to translate macro: undefined identifier `deprecated`"); // /usr/include/libevdev-1.0/libevdev/libevdev.h:2369:9
pub const LIBINPUT_H = "";
pub const _LIBUDEV_H_ = "";
pub const _SYS_SYSMACROS_H = @as(c_int, 1);
pub const _BITS_SYSMACROS_H = @as(c_int, 1);
pub inline fn major(dev: anytype) @TypeOf(gnu_dev_major(dev)) {
    _ = &dev;
    return gnu_dev_major(dev);
}
pub inline fn minor(dev: anytype) @TypeOf(gnu_dev_minor(dev)) {
    _ = &dev;
    return gnu_dev_minor(dev);
}
pub inline fn makedev(maj: anytype, min: anytype) @TypeOf(gnu_dev_makedev(maj, min)) {
    _ = &maj;
    _ = &min;
    return gnu_dev_makedev(maj, min);
}
pub const udev_list_entry_foreach = @compileError("unable to translate C expr: unexpected token 'for'"); // /usr/include/libudev.h:55:9
pub const _STDINT_H = @as(c_int, 1);
pub const _BITS_WCHAR_H = @as(c_int, 1);
pub const __WCHAR_MAX = __WCHAR_MAX__;
pub const __WCHAR_MIN = -__WCHAR_MAX - @as(c_int, 1);
pub const _BITS_STDINT_UINTN_H = @as(c_int, 1);
pub const _BITS_STDINT_LEAST_H = @as(c_int, 1);
pub const __intptr_t_defined = "";
pub const __INT64_C = __helpers.L_SUFFIX;
pub const __UINT64_C = __helpers.UL_SUFFIX;
pub const INT8_MIN = -@as(c_int, 128);
pub const INT16_MIN = -@as(c_int, 32767) - @as(c_int, 1);
pub const INT32_MIN = -__helpers.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const INT64_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT8_MAX = @as(c_int, 127);
pub const INT16_MAX = @as(c_int, 32767);
pub const INT32_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT64_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT8_MAX = @as(c_int, 255);
pub const UINT16_MAX = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT32_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT64_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INT_LEAST8_MIN = -@as(c_int, 128);
pub const INT_LEAST16_MIN = -@as(c_int, 32767) - @as(c_int, 1);
pub const INT_LEAST32_MIN = -__helpers.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const INT_LEAST64_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT_LEAST8_MAX = @as(c_int, 127);
pub const INT_LEAST16_MAX = @as(c_int, 32767);
pub const INT_LEAST32_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT_LEAST64_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT_LEAST8_MAX = @as(c_int, 255);
pub const UINT_LEAST16_MAX = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST32_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST64_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INT_FAST8_MIN = -@as(c_int, 128);
pub const INT_FAST16_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INT_FAST32_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INT_FAST64_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT_FAST8_MAX = @as(c_int, 127);
pub const INT_FAST16_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INT_FAST32_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INT_FAST64_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT_FAST8_MAX = @as(c_int, 255);
pub const UINT_FAST16_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST32_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST64_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INTPTR_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INTPTR_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const UINTPTR_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const INTMAX_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INTMAX_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINTMAX_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const PTRDIFF_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const PTRDIFF_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const SIG_ATOMIC_MIN = -__helpers.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const SIG_ATOMIC_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const SIZE_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const WCHAR_MIN = __WCHAR_MIN;
pub const WCHAR_MAX = __WCHAR_MAX;
pub const WINT_MIN = @as(c_uint, 0);
pub const WINT_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub inline fn INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const INT64_C = __helpers.L_SUFFIX;
pub inline fn UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const UINT32_C = __helpers.U_SUFFIX;
pub const UINT64_C = __helpers.UL_SUFFIX;
pub const INTMAX_C = __helpers.L_SUFFIX;
pub const UINTMAX_C = __helpers.UL_SUFFIX;
pub const __GLIBC_USE_LIB_EXT2 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT_C23 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT_C23 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_TYPES_EXT = @as(c_int, 0);
pub const __need_wchar_t = "";
pub const __need_NULL = "";
pub const _STDLIB_H = @as(c_int, 1);
pub const WNOHANG = @as(c_int, 1);
pub const WUNTRACED = @as(c_int, 2);
pub const WSTOPPED = @as(c_int, 2);
pub const WEXITED = @as(c_int, 4);
pub const WCONTINUED = @as(c_int, 8);
pub const WNOWAIT = __helpers.promoteIntLiteral(c_int, 0x01000000, .hex);
pub const __WNOTHREAD = __helpers.promoteIntLiteral(c_int, 0x20000000, .hex);
pub const __WALL = __helpers.promoteIntLiteral(c_int, 0x40000000, .hex);
pub const __WCLONE = __helpers.promoteIntLiteral(c_int, 0x80000000, .hex);
pub inline fn __WEXITSTATUS(status: anytype) @TypeOf((status & __helpers.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8)) {
    _ = &status;
    return (status & __helpers.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8);
}
pub inline fn __WTERMSIG(status: anytype) @TypeOf(status & @as(c_int, 0x7f)) {
    _ = &status;
    return status & @as(c_int, 0x7f);
}
pub inline fn __WSTOPSIG(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    _ = &status;
    return __WEXITSTATUS(status);
}
pub inline fn __WIFEXITED(status: anytype) @TypeOf(__WTERMSIG(status) == @as(c_int, 0)) {
    _ = &status;
    return __WTERMSIG(status) == @as(c_int, 0);
}
pub inline fn __WIFSIGNALED(status: anytype) @TypeOf((__helpers.cast(i8, (status & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0)) {
    _ = &status;
    return (__helpers.cast(i8, (status & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0);
}
pub inline fn __WIFSTOPPED(status: anytype) @TypeOf((status & @as(c_int, 0xff)) == @as(c_int, 0x7f)) {
    _ = &status;
    return (status & @as(c_int, 0xff)) == @as(c_int, 0x7f);
}
pub inline fn __WIFCONTINUED(status: anytype) @TypeOf(status == __W_CONTINUED) {
    _ = &status;
    return status == __W_CONTINUED;
}
pub inline fn __WCOREDUMP(status: anytype) @TypeOf(status & __WCOREFLAG) {
    _ = &status;
    return status & __WCOREFLAG;
}
pub inline fn __W_EXITCODE(ret: anytype, sig: anytype) @TypeOf((ret << @as(c_int, 8)) | sig) {
    _ = &ret;
    _ = &sig;
    return (ret << @as(c_int, 8)) | sig;
}
pub inline fn __W_STOPCODE(sig: anytype) @TypeOf((sig << @as(c_int, 8)) | @as(c_int, 0x7f)) {
    _ = &sig;
    return (sig << @as(c_int, 8)) | @as(c_int, 0x7f);
}
pub const __W_CONTINUED = __helpers.promoteIntLiteral(c_int, 0xffff, .hex);
pub const __WCOREFLAG = @as(c_int, 0x80);
pub inline fn WEXITSTATUS(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    _ = &status;
    return __WEXITSTATUS(status);
}
pub inline fn WTERMSIG(status: anytype) @TypeOf(__WTERMSIG(status)) {
    _ = &status;
    return __WTERMSIG(status);
}
pub inline fn WSTOPSIG(status: anytype) @TypeOf(__WSTOPSIG(status)) {
    _ = &status;
    return __WSTOPSIG(status);
}
pub inline fn WIFEXITED(status: anytype) @TypeOf(__WIFEXITED(status)) {
    _ = &status;
    return __WIFEXITED(status);
}
pub inline fn WIFSIGNALED(status: anytype) @TypeOf(__WIFSIGNALED(status)) {
    _ = &status;
    return __WIFSIGNALED(status);
}
pub inline fn WIFSTOPPED(status: anytype) @TypeOf(__WIFSTOPPED(status)) {
    _ = &status;
    return __WIFSTOPPED(status);
}
pub inline fn WIFCONTINUED(status: anytype) @TypeOf(__WIFCONTINUED(status)) {
    _ = &status;
    return __WIFCONTINUED(status);
}
pub const _BITS_FLOATN_H = "";
pub const __HAVE_FLOAT128 = @as(c_int, 1);
pub const __HAVE_DISTINCT_FLOAT128 = @as(c_int, 1);
pub const __HAVE_FLOAT64X = @as(c_int, 1);
pub const __HAVE_FLOAT64X_LONG_DOUBLE = @as(c_int, 1);
pub const __f128 = @compileError("unable to translate macro: undefined identifier `f128`"); // /usr/include/bits/floatn.h:72:12
pub const __CFLOAT128 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn.h:86:12
pub const _BITS_FLOATN_COMMON_H = "";
pub const __HAVE_FLOAT16 = @as(c_int, 0);
pub const __HAVE_FLOAT32 = @as(c_int, 1);
pub const __HAVE_FLOAT64 = @as(c_int, 1);
pub const __HAVE_FLOAT32X = @as(c_int, 1);
pub const __HAVE_FLOAT128X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT16 = __HAVE_FLOAT16;
pub const __HAVE_DISTINCT_FLOAT32 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT32X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT128X = __HAVE_FLOAT128X;
pub const __HAVE_FLOAT128_UNLIKE_LDBL = (__HAVE_DISTINCT_FLOAT128 != 0) and (__LDBL_MANT_DIG__ != @as(c_int, 113));
pub const __HAVE_FLOATN_NOT_TYPEDEF = @as(c_int, 1);
pub const __f32 = @compileError("unable to translate macro: undefined identifier `f32`"); // /usr/include/bits/floatn-common.h:93:12
pub const __f64 = @compileError("unable to translate macro: undefined identifier `f64`"); // /usr/include/bits/floatn-common.h:105:12
pub const __f32x = @compileError("unable to translate macro: undefined identifier `f32x`"); // /usr/include/bits/floatn-common.h:113:12
pub const __f64x = @compileError("unable to translate macro: undefined identifier `f64x`"); // /usr/include/bits/floatn-common.h:125:12
pub const __CFLOAT32 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:151:12
pub const __CFLOAT64 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:163:12
pub const __CFLOAT32X = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:171:12
pub const __CFLOAT64X = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:183:12
pub const __ldiv_t_defined = @as(c_int, 1);
pub const __lldiv_t_defined = @as(c_int, 1);
pub const RAND_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const EXIT_FAILURE = @as(c_int, 1);
pub const EXIT_SUCCESS = @as(c_int, 0);
pub const MB_CUR_MAX = __ctype_get_mb_cur_max();
pub const _ALLOCA_H = @as(c_int, 1);
pub const __COMPAR_FN_T = "";
pub const LIBINPUT_ATTRIBUTE_PRINTF = @compileError("unable to translate macro: undefined identifier `format`"); // /usr/include/libinput.h:37:9
pub const LIBINPUT_ATTRIBUTE_DEPRECATED = @compileError("unable to translate macro: undefined identifier `deprecated`"); // /usr/include/libinput.h:39:9
pub const timeval = struct_timeval;
pub const timespec = struct_timespec;
pub const timezone = struct_timezone;
pub const __itimer_which = enum___itimer_which;
pub const itimerval = struct_itimerval;
pub const winsize = struct_winsize;
pub const __pthread_internal_list = struct___pthread_internal_list;
pub const __pthread_internal_slist = struct___pthread_internal_slist;
pub const __pthread_mutex_s = struct___pthread_mutex_s;
pub const __pthread_rwlock_arch_t = struct___pthread_rwlock_arch_t;
pub const __pthread_cond_s = struct___pthread_cond_s;
pub const input_event = struct_input_event;
pub const input_id = struct_input_id;
pub const input_absinfo = struct_input_absinfo;
pub const input_keymap_entry = struct_input_keymap_entry;
pub const input_mask = struct_input_mask;
pub const ff_replay = struct_ff_replay;
pub const ff_trigger = struct_ff_trigger;
pub const ff_envelope = struct_ff_envelope;
pub const ff_constant_effect = struct_ff_constant_effect;
pub const ff_ramp_effect = struct_ff_ramp_effect;
pub const ff_condition_effect = struct_ff_condition_effect;
pub const ff_periodic_effect = struct_ff_periodic_effect;
pub const ff_rumble_effect = struct_ff_rumble_effect;
pub const ff_haptic_effect = struct_ff_haptic_effect;
pub const ff_effect = struct_ff_effect;
pub const libevdev = struct_libevdev;
pub const libevdev_read_flag = enum_libevdev_read_flag;
pub const libevdev_log_priority = enum_libevdev_log_priority;
pub const libevdev_grab_mode = enum_libevdev_grab_mode;
pub const libevdev_read_status = enum_libevdev_read_status;
pub const libevdev_led_value = enum_libevdev_led_value;
pub const udev = struct_udev;
pub const udev_list_entry = struct_udev_list_entry;
pub const udev_device = struct_udev_device;
pub const udev_monitor = struct_udev_monitor;
pub const udev_enumerate = struct_udev_enumerate;
pub const udev_queue = struct_udev_queue;
pub const udev_hwdb = struct_udev_hwdb;
pub const random_data = struct_random_data;
pub const drand48_data = struct_drand48_data;
pub const libinput = struct_libinput;
pub const libinput_device = struct_libinput_device;
pub const libinput_device_group = struct_libinput_device_group;
pub const libinput_seat = struct_libinput_seat;
pub const libinput_tablet_tool = struct_libinput_tablet_tool;
pub const libinput_event = struct_libinput_event;
pub const libinput_event_device_notify = struct_libinput_event_device_notify;
pub const libinput_event_keyboard = struct_libinput_event_keyboard;
pub const libinput_event_pointer = struct_libinput_event_pointer;
pub const libinput_event_touch = struct_libinput_event_touch;
pub const libinput_event_gesture = struct_libinput_event_gesture;
pub const libinput_event_tablet_tool = struct_libinput_event_tablet_tool;
pub const libinput_event_tablet_pad = struct_libinput_event_tablet_pad;
pub const libinput_log_priority = enum_libinput_log_priority;
pub const libinput_device_capability = enum_libinput_device_capability;
pub const libinput_key_state = enum_libinput_key_state;
pub const libinput_led = enum_libinput_led;
pub const libinput_button_state = enum_libinput_button_state;
pub const libinput_pointer_axis = enum_libinput_pointer_axis;
pub const libinput_pointer_axis_source = enum_libinput_pointer_axis_source;
pub const libinput_tablet_pad_ring_axis_source = enum_libinput_tablet_pad_ring_axis_source;
pub const libinput_tablet_pad_strip_axis_source = enum_libinput_tablet_pad_strip_axis_source;
pub const libinput_tablet_tool_type = enum_libinput_tablet_tool_type;
pub const libinput_tablet_tool_proximity_state = enum_libinput_tablet_tool_proximity_state;
pub const libinput_tablet_tool_tip_state = enum_libinput_tablet_tool_tip_state;
pub const libinput_tablet_pad_mode_group = struct_libinput_tablet_pad_mode_group;
pub const libinput_switch_state = enum_libinput_switch_state;
pub const libinput_switch = enum_libinput_switch;
pub const libinput_event_switch = struct_libinput_event_switch;
pub const libinput_event_type = enum_libinput_event_type;
pub const libinput_interface = struct_libinput_interface;
pub const libinput_plugin_system_flags = enum_libinput_plugin_system_flags;
pub const libinput_config_status = enum_libinput_config_status;
pub const libinput_config_tap_state = enum_libinput_config_tap_state;
pub const libinput_config_tap_button_map = enum_libinput_config_tap_button_map;
pub const libinput_config_clickfinger_button_map = enum_libinput_config_clickfinger_button_map;
pub const libinput_config_drag_state = enum_libinput_config_drag_state;
pub const libinput_config_drag_lock_state = enum_libinput_config_drag_lock_state;
pub const libinput_config_3fg_drag_state = enum_libinput_config_3fg_drag_state;
pub const libinput_config_area_rectangle = struct_libinput_config_area_rectangle;
pub const libinput_config_send_events_mode = enum_libinput_config_send_events_mode;
pub const libinput_config_accel_profile = enum_libinput_config_accel_profile;
pub const libinput_config_accel = struct_libinput_config_accel;
pub const libinput_config_accel_type = enum_libinput_config_accel_type;
pub const libinput_config_click_method = enum_libinput_config_click_method;
pub const libinput_config_middle_emulation_state = enum_libinput_config_middle_emulation_state;
pub const libinput_config_scroll_method = enum_libinput_config_scroll_method;
pub const libinput_config_scroll_button_lock_state = enum_libinput_config_scroll_button_lock_state;
pub const libinput_config_dwt_state = enum_libinput_config_dwt_state;
pub const libinput_config_dwtp_state = enum_libinput_config_dwtp_state;
pub const libinput_config_eraser_button_mode = enum_libinput_config_eraser_button_mode;
