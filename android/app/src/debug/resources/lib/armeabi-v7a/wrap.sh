#!/system/bin/sh
# Debug builds, 32-bit only. Some older GPU drivers free the same memory
# twice; since Android 11 the allocator (Scudo) ends the app for it, mid
# test. Android's malloc debug holds freed memory back (free_track), notices
# the second free and logs it instead. It slows allocation down, which is
# why it is limited to debug builds on 32-bit phones; release builds never
# carry this file.
LIBC_DEBUG_MALLOC_OPTIONS="free_track=8192 free_track_backtrace_num_frames=0" exec "$@"
