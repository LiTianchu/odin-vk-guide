# test run
export LIBRARY_PATH="/usr/local/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

odin run ./tutorial/02_drawing_with_compute \
    -debug \
    --out:./build/02_drawing_with_compute \
    --collection:libs=./libs \
    -extra-linker-flags:"-L/usr/local/lib -Wl,-rpath,/usr/local/lib" \
    -show-system-calls
