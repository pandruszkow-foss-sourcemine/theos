
#program_export
start :: () {
    screen := cast(*u8) 0xb8000;

    for cast([] u8) "This is a fun test, again" {
        screen[it_index * 2] = it;
    }
}
