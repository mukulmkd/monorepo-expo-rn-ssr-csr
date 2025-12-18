if(NOT TARGET fbjni::fbjni)
add_library(fbjni::fbjni SHARED IMPORTED)
set_target_properties(fbjni::fbjni PROPERTIES
    IMPORTED_LOCATION "/Users/mukulkishore/.gradle/caches/8.14.3/transforms/9cc05dafd13eea6070ed9b7e94a27c3b/transformed/fbjni-0.7.0/prefab/modules/fbjni/libs/android.x86_64/libfbjni.so"
    INTERFACE_INCLUDE_DIRECTORIES "/Users/mukulkishore/.gradle/caches/8.14.3/transforms/9cc05dafd13eea6070ed9b7e94a27c3b/transformed/fbjni-0.7.0/prefab/modules/fbjni/include"
    INTERFACE_LINK_LIBRARIES ""
)
endif()

